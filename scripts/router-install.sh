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
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker|/usr/libexec/ddk-apple-worker|/usr/libexec/ddk-phase3-worker|/usr/libexec/ddk-phase4-worker|/usr/libexec/ddk-v3-worker|/usr/libexec/ddk-compare-range|/usr/libexec/ddk-modbus-client|/usr/libexec/ddk-usbip-client|/usr/libexec/ddk-device-session|/usr/libexec/ddk-input-sealer) return 0 ;;
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
[ -x /usr/bin/openssl ] || fail 'OpenSSL is missing for target-side structured validation'
# Optional tool readiness belongs to the selected operation, not the installer.
# Operator-enabled camera/GNSS/radio services are preserved, including their state.
for core_binary in /usr/bin/sha256sum /usr/bin/xxd /bin/sh; do
	[ -x "$core_binary" ] || fail "required console runtime is missing: $core_binary"
done
lua -e 'local n=require "nixio"; local f=require "nixio.fs"; assert(n.fork and n.exec and n.setsid and n.waitpid and f.statvfs)'
command -v timeout >/dev/null 2>&1 || fail 'timeout is missing'
command -v hexdump >/dev/null 2>&1 || fail 'hexdump is missing'
[ -x /usr/libexec/cgi-io ] || [ -x /usr/libexec/cgi-io/capture ] || command -v cgi-io >/dev/null 2>&1 || fail 'cgi-io execution support is missing'
[ -x /www/cgi-bin/cgi-upload ] || fail 'the native authenticated LuCI upload endpoint is missing'

root_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ || true)"
luci_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/ || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI preflight returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI preflight returned HTTP $luci_http" ;; esac

DDK_LUA_FILE="$source_root/usr/libexec/ddk-console" lua -e 'assert(loadfile(os.getenv("DDK_LUA_FILE")))'
DDK_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-actions.lua" lua -e 'assert(loadfile(os.getenv("DDK_OPERATOR_FILE")))'
DDK_APPLE_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-apple.lua" lua -e 'assert(loadfile(os.getenv("DDK_APPLE_OPERATOR_FILE")))'
DDK_PHASE3_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-phase3.lua" lua -e 'assert(loadfile(os.getenv("DDK_PHASE3_OPERATOR_FILE")))'
DDK_PHASE4_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-phase4.lua" lua -e 'assert(loadfile(os.getenv("DDK_PHASE4_OPERATOR_FILE")))'
DDK_V3_WORKER="$source_root/usr/libexec/ddk-v3-worker" lua -e 'assert(loadfile(os.getenv("DDK_V3_WORKER")))'
DDK_V3_OPERATOR="$source_root/usr/share/ddk-field-console/operator-v3.lua" lua -e 'assert(loadfile(os.getenv("DDK_V3_OPERATOR")))'
DDK_RUNTIME_POLICY="$source_root/usr/share/ddk-field-console/runtime-policy.lua" lua -e 'assert(loadfile(os.getenv("DDK_RUNTIME_POLICY")))'
DDK_USB_TOPOLOGY="$source_root/usr/share/ddk-field-console/usb-topology.lua" lua -e 'assert(loadfile(os.getenv("DDK_USB_TOPOLOGY")))'
DDK_PYTHON_ROOT="$source_root" python3 -c 'import ast,os,pathlib; root=pathlib.Path(os.environ["DDK_PYTHON_ROOT"]); [ast.parse((root/"usr/libexec"/name).read_text()) for name in ["ddk-device-session","ddk-usbip-client","ddk-modbus-client","ddk-compare-range","ddk-input-sealer"]]'
DDK_IDENTITY_FILE="$source_root/usr/share/ddk-field-console/usb-identity.lua" lua -e 'assert(loadfile(os.getenv("DDK_IDENTITY_FILE")))'
DDK_TEMPLATE_FILE="$source_root/usr/lib/lua/luci/view/ddk/shell.htm" lua -e 'local parser = require "luci.template.parser"; assert(parser.parse(os.getenv("DDK_TEMPLATE_FILE")))'
sh -n "$source_root/usr/libexec/ddk-job-worker"
sh -n "$source_root/usr/libexec/ddk-apple-worker"
sh -n "$source_root/usr/libexec/ddk-phase3-worker"
sh -n "$source_root/usr/libexec/ddk-phase4-worker"

find "$source_root" -type f -name '*.json' | while IFS= read -r json_file; do
	jsonfilter -i "$json_file" -e '@' >/dev/null
done

find "$source_root" -type f | while IFS= read -r source_file; do
	relative="${source_file#"$source_root"/}"
	target="/$relative"
	allowed_target "$target" || fail "staged file is outside the project allowlist: $target"
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="/root/ddk-backups/${timestamp}-field-console-v4"
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

sha256sum /etc/config/network /etc/config/firewall /etc/config/wireless /etc/config/uhttpd /etc/config/rpcd \
	/etc/config/rtl_tcp /etc/config/mjpg-streamer /etc/config/motion /etc/config/gpsd > "$backup_path/protected-config.sha256"
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
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker|/usr/libexec/ddk-apple-worker|/usr/libexec/ddk-phase3-worker|/usr/libexec/ddk-phase4-worker|/usr/libexec/ddk-v3-worker|/usr/libexec/ddk-compare-range|/usr/libexec/ddk-modbus-client|/usr/libexec/ddk-usbip-client|/usr/libexec/ddk-device-session|/usr/libexec/ddk-input-sealer) chmod 755 "$temporary" ;;
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

sha256sum -c "$backup_path/protected-config.sha256" >/dev/null || fail "configuration changed during installation"
install_complete=1
trap - EXIT HUP INT TERM
printf 'DDK_BACKUP_PATH=%s\n' "$backup_path"
printf '%s\n' 'Field Console files installed. rpcd ACLs were reloaded; no service was restarted.'
