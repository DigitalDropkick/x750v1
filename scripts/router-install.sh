#!/bin/sh

set -eu
umask 077

source_root="${1:-}"
rollback_script="${2:-}"
backup_path=""
install_started=0
install_complete=0

fail() {
	printf 'DEPLOYMENT REFUSED: %s\n' "$1" >&2
	exit 1
}

allowed_target() {
	case "$1" in
		*..*|*[!A-Za-z0-9_./-]*) return 1 ;;
	esac
	case "$1" in
		/usr/share/luci/menu.d/ddk-field-console.json) return 0 ;;
		/usr/share/rpcd/acl.d/ddk-field-console.json) return 0 ;;
		/usr/lib/lua/luci/view/ddk/*) return 0 ;;
		/www/luci-static/resources/ddk/*) return 0 ;;
		/www/ddk/gl_home.html) return 0 ;;
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker) return 0 ;;
		/usr/share/ddk-field-console/*) return 0 ;;
		*) return 1 ;;
	esac
}

rollback_on_failure() {
	result=$?
	if [ "$result" -ne 0 ] && [ "$install_started" -eq 1 ] && [ "$install_complete" -eq 0 ] && [ -n "$backup_path" ]; then
		printf 'Install failed after writes began; restoring %s\n' "$backup_path" >&2
		sh "$rollback_script" "$backup_path" --internal || printf '%s\n' 'AUTOMATIC ROLLBACK FAILED — use the printed backup path.' >&2
	fi
	exit "$result"
}

trap rollback_on_failure EXIT
trap 'exit 130' HUP INT TERM

[ -d "$source_root" ] || fail 'staged source directory is missing'
[ -f "$rollback_script" ] || fail 'staged rollback helper is missing'

model="$(ubus call system board | jsonfilter -e '@.model' 2>/dev/null || true)"
board="$(ubus call system board | jsonfilter -e '@.board_name' 2>/dev/null || true)"
arch="$(opkg print-architecture | awk '$1 == "arch" && $2 == "mips_24kc" {print $2}' | head -n 1)"
release="$(
	# Target firmware file confirmed during discovery.
	# shellcheck disable=SC1091
	. /etc/openwrt_release
	printf '%s' "$DISTRIB_RELEASE"
)"

[ "$model" = 'GL.iNet GL-X750' ] || fail "unexpected model: $model"
[ "$board" = 'glinet,gl-x750-nor' ] || fail "unexpected board: $board"
[ "$arch" = 'mips_24kc' ] || fail "unexpected architecture: $arch"
[ "$release" = '22.03.4' ] || fail "unexpected OpenWrt release: $release"

mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail '/dev/sda1 ext4 is not mounted at /overlay'
grep -q '^/overlay/ddk-install.swap[[:space:]]' /proc/swaps || fail '/overlay/ddk-install.swap is not active; no router files were changed'

available_kb="$(df -Pk /overlay | awk 'NR == 2 {print $4}')"
[ "${available_kb:-0}" -ge 102400 ] || fail 'less than 100 MiB is free on extroot'

[ -d /usr/share/luci/menu.d ] || fail 'modern LuCI menu directory is missing'
[ -d /usr/share/rpcd/acl.d ] || fail 'rpcd ACL directory is missing'
[ -d /usr/lib/lua/luci/view ] || fail 'LuCI template directory is missing'
[ -x /usr/bin/lua ] || fail 'Lua 5.1 runtime is missing'
[ -x /usr/bin/jsonfilter ] || fail 'jsonfilter is missing'
[ -x /usr/bin/nmap ] || fail 'the already-installed nmap-full executable is missing; no package will be installed'
[ -x /sbin/uqmi ] || fail 'the already-installed uqmi executable is missing; no package will be installed'
command -v timeout >/dev/null 2>&1 || fail 'timeout is missing'
[ -x /usr/libexec/cgi-io ] || [ -x /usr/libexec/cgi-io/capture ] || command -v cgi-io >/dev/null 2>&1 || fail 'cgi-io execution support is missing'

root_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ || true)"
luci_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/ || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI preflight returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI preflight returned HTTP $luci_http" ;; esac

printf '%s  %s\n' \
	fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846 /etc/config/network \
	0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f /etc/config/firewall \
	59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa /etc/config/wireless \
	bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18 /etc/config/uhttpd \
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd |
	sha256sum -c - >/dev/null || fail 'protected configuration drifted since discovery'

DDK_LUA_FILE="$source_root/usr/libexec/ddk-console" lua -e 'assert(loadfile(os.getenv("DDK_LUA_FILE")))'
DDK_TEMPLATE_FILE="$source_root/usr/lib/lua/luci/view/ddk/shell.htm" lua -e 'local parser = require "luci.template.parser"; assert(parser.parse(os.getenv("DDK_TEMPLATE_FILE")))'
sh -n "$source_root/usr/libexec/ddk-job-worker"

find "$source_root" -type f -name '*.json' | while IFS= read -r json_file; do
	jsonfilter -i "$json_file" -e '@' >/dev/null
done

find "$source_root" -type f | while IFS= read -r source_file; do
	relative="${source_file#"$source_root"/}"
	target="/$relative"
	allowed_target "$target" || fail "staged file is outside the project allowlist: $target"
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="/root/ddk-backups/${timestamp}-field-console-v1"
if [ -e "$backup_path" ]; then backup_path="${backup_path}-$$"; fi
mkdir -p "$backup_path/files"
: > "$backup_path/existing.list"
: > "$backup_path/new.list"

{
	printf 'created_utc=%s\n' "$timestamp"
	printf 'model=%s\n' "$model"
	printf 'board=%s\n' "$board"
	printf 'release=%s\n' "$release"
	printf 'source_version=%s\n' "$(cat "$source_root/usr/share/ddk-field-console/VERSION")"
} > "$backup_path/metadata"

sha256sum /etc/config/network /etc/config/firewall /etc/config/wireless /etc/config/uhttpd /etc/config/rpcd > "$backup_path/protected-config.sha256"
netstat -lntup 2>/dev/null | awk 'NR > 2 {program=$7; sub(/^[0-9]+\//, "", program); print $1, $4, program}' | sort > "$backup_path/listeners.before"

find "$source_root" -type f | sort | while IFS= read -r source_file; do
	relative="${source_file#"$source_root"/}"
	target="/$relative"
	if [ -e "$target" ] || [ -L "$target" ]; then
		backup_target="$backup_path/files$target"
		mkdir -p "$(dirname "$backup_target")"
		cp -p "$target" "$backup_target"
		printf '%s\n' "$target" >> "$backup_path/existing.list"
	else
		printf '%s\n' "$target" >> "$backup_path/new.list"
	fi
done

install_started=1
find "$source_root" -type f | sort | while IFS= read -r source_file; do
	relative="${source_file#"$source_root"/}"
	target="/$relative"
	target_dir="$(dirname "$target")"
	temporary="$target.ddk-new-$$"
	mkdir -p "$target_dir"
	cp "$source_file" "$temporary"
	case "$target" in
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker) chmod 755 "$temporary" ;;
		*) chmod 644 "$temporary" ;;
	esac
	mv "$temporary" "$target"
done

[ -d /tmp/luci-indexcache ] || rm -f /tmp/luci-indexcache
/etc/init.d/rpcd reload
/usr/libexec/ddk-console status | jsonfilter -e '@.ok' | grep -qx 'true'
/usr/libexec/ddk-console capabilities | jsonfilter -e '@.ok' | grep -qx 'true'

printf '%s\n' "$backup_path" > /root/ddk-backups/ddk-field-console-latest
chmod 600 /root/ddk-backups/ddk-field-console-latest

install_complete=1
trap - EXIT HUP INT TERM
printf 'DDK_BACKUP_PATH=%s\n' "$backup_path"
printf '%s\n' 'Field Console files installed. rpcd ACLs were reloaded; no service was restarted.'
