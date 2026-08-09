#!/bin/sh

set -eu
umask 077

backup_path="${1:-}"
swap_file=/overlay/ddk-install.swap

fail() {
	printf 'SWAP AUTOSTART ROLLBACK REFUSED: %s\n' "$1" >&2
	exit 1
}

if [ -z "$backup_path" ]; then
	[ -f /root/ddk-backups/ddk-swap-autostart-latest ] || fail 'latest swap-backup pointer is missing'
	backup_path="$(cat /root/ddk-backups/ddk-swap-autostart-latest)"
fi

case "$backup_path" in /root/ddk-backups/*) ;; *) fail 'backup path is outside /root/ddk-backups' ;; esac
backup_name="${backup_path#/root/ddk-backups/}"
case "$backup_name" in
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-swap-autostart|\
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-swap-autostart-[0-9]*) ;;
	*) fail 'backup name does not match a DDK swap-autostart backup' ;;
esac
case "$backup_name" in *..*|*/*|*[!A-Za-z0-9_.-]*) fail 'backup name contains unsafe characters' ;; esac

[ -d "$backup_path" ] || fail 'backup directory does not exist'
[ -f "$backup_path/fstab.before" ] || fail 'fstab.before is missing'
[ -f "$backup_path/fstab.after" ] || fail 'fstab.after is missing'
[ -f "$backup_path/checksums.sha256" ] || fail 'checksum manifest is missing'
(cd "$backup_path" && sha256sum -c checksums.sha256 >/dev/null) || fail 'backup checksum validation failed'
[ -z "$(uci -q changes fstab || true)" ] || fail 'fstab has uncommitted UCI changes; refusing to overwrite them'

before_sha256="$(sha256sum "$backup_path/fstab.before" | awk '{print $1}')"
after_sha256="$(sha256sum "$backup_path/fstab.after" | awk '{print $1}')"
current_sha256="$(sha256sum /etc/config/fstab | awk '{print $1}')"

model="$(ubus call system board | jsonfilter -e '@.model' 2>/dev/null || true)"
board="$(ubus call system board | jsonfilter -e '@.board_name' 2>/dev/null || true)"
# Target firmware file confirmed during discovery.
# shellcheck disable=SC1091
. /etc/openwrt_release
[ "$model" = 'GL.iNet GL-X750' ] || fail "unexpected model: $model"
[ "$board" = 'glinet,gl-x750-nor' ] || fail "unexpected board: $board"
[ "$DISTRIB_RELEASE" = '22.03.4' ] || fail "unexpected OpenWrt release: $DISTRIB_RELEASE"
mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail '/dev/sda1 extroot is not active'
awk -v file="$swap_file" '$1 == file && $2 == "file" { found=1 } END { exit !found }' /proc/swaps ||
	fail "$swap_file is not active; refusing configuration rollback"

if [ "$current_sha256" = "$before_sha256" ]; then
	printf '%s\n' 'Swap autostart configuration is already rolled back exactly; no file was changed.'
	exit 0
fi
[ "$current_sha256" = "$after_sha256" ] || fail '/etc/config/fstab changed after configuration; refusing to overwrite newer work'

temporary="/etc/config/fstab.ddk-rollback-$$"
cp -p "$backup_path/fstab.before" "$temporary"
mv "$temporary" /etc/config/fstab
uci -q show fstab >/dev/null || fail 'restored fstab does not parse through UCI'
[ "$(sha256sum /etc/config/fstab | awk '{print $1}')" = "$before_sha256" ] || fail 'restored fstab hash does not match the backup'
awk -v file="$swap_file" '$1 == file && $2 == "file" { found=1 } END { exit !found }' /proc/swaps ||
	fail 'active swap disappeared during configuration rollback'
mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail 'extroot changed during configuration rollback'
date -u +%Y%m%dT%H%M%SZ > "$backup_path/rollback-completed-utc"

printf 'RESTORED_SWAP_BACKUP_PATH=%s\n' "$backup_path"
printf '%s\n' 'The pre-change fstab was restored. Active swap and mount state were unchanged and no service was restarted.'
