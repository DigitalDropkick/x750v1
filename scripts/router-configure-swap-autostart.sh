#!/bin/sh

set -eu
umask 077

swap_file=/overlay/ddk-install.swap
section=ddk_install_swap
backup_path=''
write_started=0
write_complete=0

fail() {
	printf 'SWAP AUTOSTART REFUSED: %s\n' "$1" >&2
	exit 1
}

restore_on_failure() {
	result=$?
	if [ "$result" -ne 0 ] && [ "$write_started" -eq 1 ] && [ "$write_complete" -eq 0 ] && [ -n "$backup_path" ]; then
		temporary="/etc/config/fstab.ddk-restore-$$"
		printf 'Configuration failed after writes began; restoring %s/fstab.before\n' "$backup_path" >&2
		uci -q revert fstab.ddk_install_swap || true
		cp -p "$backup_path/fstab.before" "$temporary" && mv "$temporary" /etc/config/fstab ||
			printf '%s\n' 'AUTOMATIC FSTAB RESTORE FAILED — use rollback-swap-autostart.sh with the printed backup path.' >&2
	fi
	exit "$result"
}

trap restore_on_failure EXIT
trap 'exit 130' HUP INT TERM

model="$(ubus call system board | jsonfilter -e '@.model' 2>/dev/null || true)"
board="$(ubus call system board | jsonfilter -e '@.board_name' 2>/dev/null || true)"
# Target firmware file confirmed during discovery.
# shellcheck disable=SC1091
. /etc/openwrt_release
release="$DISTRIB_RELEASE"

[ "$model" = 'GL.iNet GL-X750' ] || fail "unexpected model: $model"
[ "$board" = 'glinet,gl-x750-nor' ] || fail "unexpected board: $board"
[ "$release" = '22.03.4' ] || fail "unexpected OpenWrt release: $release"
mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail '/dev/sda1 ext4 is not mounted at /overlay'
awk -v file="$swap_file" '$1 == file && $2 == "file" && $3 >= 262000 { found=1 } END { exit !found }' /proc/swaps ||
	fail "$swap_file is not the active 256 MiB-class swap file"

if [ ! -f "$swap_file" ] || [ -L "$swap_file" ]; then
	fail 'swap target is not a regular non-symlink file'
fi
[ "$(stat -c '%a' "$swap_file")" = '600' ] || fail 'swap file mode is not 0600'
[ "$(stat -c '%u:%g' "$swap_file")" = '0:0' ] || fail 'swap file is not owned by root:root'
[ "$(stat -c '%s' "$swap_file")" = '268435456' ] || fail 'swap file size is not exactly 256 MiB'
[ "$(( $(stat -c '%b' "$swap_file") * 512 ))" -ge 268435456 ] || fail 'swap file is sparse or not fully allocated'
file "$swap_file" | grep -q 'Linux swap file' || fail 'swap file signature was not recognized'
if [ ! -f /etc/config/fstab ] || [ -L /etc/config/fstab ]; then
	fail '/etc/config/fstab is not a regular non-symlink file'
fi
[ -z "$(uci -q changes fstab || true)" ] || fail 'fstab has uncommitted UCI changes; refusing to merge or overwrite them'

for existing_section in $(uci show fstab | sed -n 's/^fstab\.\([^=]*\)=swap$/\1/p'); do
	existing_device="$(uci -q get "fstab.$existing_section.device" || true)"
	if [ "$existing_device" = "$swap_file" ] && [ "$existing_section" != "$section" ]; then
		fail "another swap section already targets $swap_file: $existing_section"
	fi
done

expected="fstab.$section=swap
fstab.$section.device='$swap_file'
fstab.$section.enabled='1'"
current="$(uci -q show "fstab.$section" || true)"
if [ "$current" = "$expected" ]; then
	printf '%s\n' 'Swap autostart is already configured exactly; no file was changed.'
	printf 'DDK_SWAP_CONFIG_SHA256=%s\n' "$(sha256sum /etc/config/fstab | awk '{print $1}')"
	exit 0
fi
[ -z "$current" ] || fail "the existing $section section does not match the approved definition"

printf '%s  %s\n' \
	fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846 /etc/config/network \
	0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f /etc/config/firewall \
	59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa /etc/config/wireless \
	bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18 /etc/config/uhttpd \
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd |
	sha256sum -c - >/dev/null || fail 'protected configuration drifted before the swap change'

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="/root/ddk-backups/${timestamp}-swap-autostart"
if [ -e "$backup_path" ]; then backup_path="${backup_path}-$$"; fi
mkdir -p "$backup_path"
cp -p /etc/config/fstab "$backup_path/fstab.before"
before_sha256="$(sha256sum /etc/config/fstab | awk '{print $1}')"
{
	printf 'created_utc=%s\n' "$timestamp"
	printf 'model=%s\n' "$model"
	printf 'board=%s\n' "$board"
	printf 'release=%s\n' "$release"
	printf 'target=%s\n' "$swap_file"
	printf 'section=%s\n' "$section"
	printf 'before_sha256=%s\n' "$before_sha256"
} > "$backup_path/metadata"

write_started=1
[ "$(sha256sum /etc/config/fstab | awk '{print $1}')" = "$before_sha256" ] || fail '/etc/config/fstab changed after backup; refusing the write'
uci -q delete fstab.ddk_install_swap || true
uci set fstab.ddk_install_swap='swap'
uci set fstab.ddk_install_swap.device='/overlay/ddk-install.swap'
uci set fstab.ddk_install_swap.enabled='1'
uci commit fstab

current="$(uci -q show "fstab.$section" || true)"
[ "$current" = "$expected" ] || fail 'committed UCI section failed exact validation'
awk -v file="$swap_file" '$1 == file && $2 == "file" { found=1 } END { exit !found }' /proc/swaps ||
	fail 'active swap disappeared during configuration'
mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail 'extroot changed during configuration'

after_sha256="$(sha256sum /etc/config/fstab | awk '{print $1}')"
cp -p /etc/config/fstab "$backup_path/fstab.after"
printf 'after_sha256=%s\n' "$after_sha256" >> "$backup_path/metadata"
printf '%s  %s\n' "$before_sha256" fstab.before > "$backup_path/checksums.sha256"
printf '%s  %s\n' "$after_sha256" fstab.after >> "$backup_path/checksums.sha256"
printf '%s\n' "$backup_path" > /root/ddk-backups/ddk-swap-autostart-latest
chmod 600 /root/ddk-backups/ddk-swap-autostart-latest

write_complete=1
trap - EXIT HUP INT TERM
printf 'DDK_SWAP_BACKUP_PATH=%s\n' "$backup_path"
printf 'DDK_SWAP_CONFIG_SHA256=%s\n' "$after_sha256"
printf '%s\n' 'Native boot activation is configured. No live swap or mount state was changed and no service was restarted.'
