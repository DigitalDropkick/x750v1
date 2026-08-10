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
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker|/usr/libexec/ddk-apple-worker) return 0 ;;
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
[ -x /usr/sbin/tcpdump ] || fail 'the already-installed tcpdump executable is missing; no package will be installed'
[ -x /usr/bin/iperf3 ] || fail 'the already-installed iperf3 executable is missing; no package will be installed'
[ -x /usr/bin/adb ] || fail 'the already-installed ADB executable is missing; no package will be installed'
for apple_binary in idevice_id ideviceinfo idevicename idevicedate idevicepair idevicediagnostics ideviceenterrecovery idevicesetlocation idevicescreenshot idevicesyslog irecovery idevicerestore; do
	[ -x "/usr/bin/$apple_binary" ] || fail "the already-installed $apple_binary executable is missing; no package will be installed"
done
[ -x /usr/sbin/usbmuxd ] || fail 'the already-installed usbmuxd executable is missing; no package will be installed'
LC_ALL=C /usr/bin/nmap --version 2>&1 | grep -Fq 'Nmap version 7.91 ' || fail 'the installed Nmap version drifted from reviewed 7.91 syntax'
tcpdump_version="$(LC_ALL=C /usr/sbin/tcpdump --version 2>&1 || true)"
printf '%s\n' "$tcpdump_version" | grep -Fq 'tcpdump version 4.9.3' || fail 'the installed tcpdump version drifted from reviewed 4.9.3 syntax'
printf '%s\n' "$tcpdump_version" | grep -Fq 'libpcap version 1.10.1 ' || fail 'the installed libpcap version drifted from reviewed 1.10.1 behavior'
LC_ALL=C /usr/bin/iperf3 --version 2>&1 | grep -Fq 'iperf 3.11 ' || fail 'the installed iperf3 version drifted from reviewed 3.11 syntax'
LC_ALL=C /usr/bin/adb version 2>&1 | grep -Fqx 'Android Debug Bridge version 1.0.32' || fail 'the installed ADB version drifted from reviewed 1.0.32 syntax'
LC_ALL=C /usr/bin/ideviceinfo --version 2>&1 | grep -Fq '1.3.0' || fail 'the installed libimobiledevice utilities drifted from reviewed 1.3.0 syntax'
LC_ALL=C /usr/bin/irecovery --version 2>&1 | grep -Fq '1.0.0' || fail 'the installed irecovery version drifted from reviewed 1.0.0 syntax'
LC_ALL=C /usr/bin/idevicerestore --version 2>&1 | grep -Fq '1.0.0' || fail 'the installed idevicerestore version drifted from reviewed 1.0.0 syntax'
LC_ALL=C /usr/sbin/usbmuxd --version 2>&1 | grep -Fqx 'usbmuxd 1.1.1' || fail 'the installed usbmuxd version drifted from reviewed 1.1.1 behavior'
[ -x /usr/bin/rtl_433 ] || fail 'the already-installed rtl_433 executable is missing; no package will be installed'
[ -x /usr/bin/fswebcam ] || fail 'the already-installed fswebcam executable is missing; no package will be installed'
[ -x /usr/bin/v4l2-ctl ] || fail 'the already-installed v4l2-ctl executable is missing; no package will be installed'
[ -x /usr/bin/file ] || fail 'the already-installed file executable is missing; no package will be installed'
[ -x /usr/bin/gpsdecode ] || fail 'the already-installed gpsdecode executable is missing; no package will be installed'
[ -x /usr/bin/socat ] || fail 'the already-installed socat executable is missing; no package will be installed'
[ -x /usr/bin/xxd ] || fail 'the already-installed xxd executable is missing; no package will be installed'
[ -x /usr/bin/sha256sum ] || fail 'the already-installed SHA-256 executable is missing; no package will be installed'
[ -x /bin/stty ] || fail 'the already-installed stty executable is missing; no package will be installed'
[ -x /sbin/uqmi ] || fail 'the already-installed uqmi executable is missing; no package will be installed'
/usr/bin/rtl_433 -c /dev/null -V >/dev/null 2>&1 || fail 'rtl_433 rejected the reviewed empty-config invocation'
opkg status rtl_433 2>/dev/null | grep -Fqx 'Version: 20.11-2' || fail 'the installed rtl_433 package version drifted from reviewed 20.11-2 syntax'
LC_ALL=C /usr/bin/fswebcam --version 2>&1 | grep -Fqx 'fswebcam 20140113' || fail 'the installed fswebcam version drifted from reviewed 20140113 syntax'
LC_ALL=C /usr/bin/socat -V 2>&1 | grep -Fq 'socat version 1.7.4.1 ' || fail 'the installed socat version drifted from reviewed 1.7.4.1 serial syntax'
LC_ALL=C /bin/stty --version 2>&1 | grep -Fq 'stty (GNU coreutils) 9.0' || fail 'the installed stty version drifted from reviewed 9.0 tty-state behavior'
LC_ALL=C /usr/bin/gpsdecode -V 2>&1 | grep -Fqx 'gpsdecode revision 3.23.1' || fail 'the installed gpsdecode version drifted from reviewed 3.23.1 syntax'
[ "$(uci -q get rtl_tcp.main.disabled)" = '1' ] || fail 'the existing rtl_tcp network service is not explicitly disabled'
[ "$(uci -q get mjpg-streamer.core.enabled)" = '0' ] || fail 'the existing mjpg-streamer service is not explicitly UCI-disabled'
[ "$(uci -q get motion.general.enabled)" = '0' ] || fail 'the existing Motion service is not explicitly UCI-disabled'
if /etc/init.d/mjpg-streamer enabled >/dev/null 2>&1 || /etc/init.d/motion enabled >/dev/null 2>&1; then
	fail 'an existing camera service is enabled at boot'
fi
if pidof fswebcam mjpg_streamer motion v4l2rtspserver >/dev/null 2>&1; then fail 'a camera client or service is already active'; fi
command -v timeout >/dev/null 2>&1 || fail 'timeout is missing'
command -v hexdump >/dev/null 2>&1 || fail 'hexdump is missing'
[ -x /usr/libexec/cgi-io ] || [ -x /usr/libexec/cgi-io/capture ] || command -v cgi-io >/dev/null 2>&1 || fail 'cgi-io execution support is missing'
[ -x /www/cgi-bin/cgi-upload ] || fail 'the native authenticated LuCI upload endpoint is missing'

root_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ || true)"
luci_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/ || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI preflight returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI preflight returned HTTP $luci_http" ;; esac

printf '%s  %s\n' \
	fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846 /etc/config/network \
	0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f /etc/config/firewall \
	59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa /etc/config/wireless \
	bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18 /etc/config/uhttpd \
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd \
	500d071555f688b493b2937f8ef1edf7f56dfddd3888aa584e8b572d5db3f2ad /etc/config/rtl_tcp \
	00f24dd633bac043f1063b36ae60bef53659c52237e3cfefc27a611b4806944f /etc/config/mjpg-streamer \
	574743e3859793b10328389d2f1a37e4dce88f0e753029a102a43d073b6ca22f /etc/config/motion \
	e500321d73a7329e11423769f37ea1bb7c11d2dc20f10a3cc126c67b9a7bf078 /etc/config/gpsd |
	sha256sum -c - >/dev/null || fail 'protected configuration drifted since discovery'

DDK_LUA_FILE="$source_root/usr/libexec/ddk-console" lua -e 'assert(loadfile(os.getenv("DDK_LUA_FILE")))'
DDK_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-actions.lua" lua -e 'assert(loadfile(os.getenv("DDK_OPERATOR_FILE")))'
DDK_APPLE_OPERATOR_FILE="$source_root/usr/share/ddk-field-console/operator-apple.lua" lua -e 'assert(loadfile(os.getenv("DDK_APPLE_OPERATOR_FILE")))'
DDK_IDENTITY_FILE="$source_root/usr/share/ddk-field-console/usb-identity.lua" lua -e 'assert(loadfile(os.getenv("DDK_IDENTITY_FILE")))'
DDK_TEMPLATE_FILE="$source_root/usr/lib/lua/luci/view/ddk/shell.htm" lua -e 'local parser = require "luci.template.parser"; assert(parser.parse(os.getenv("DDK_TEMPLATE_FILE")))'
sh -n "$source_root/usr/libexec/ddk-job-worker"
sh -n "$source_root/usr/libexec/ddk-apple-worker"

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
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker|/usr/libexec/ddk-apple-worker) chmod 755 "$temporary" ;;
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
