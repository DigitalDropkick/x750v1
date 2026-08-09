#!/bin/sh

set -eu

pass_count=0
warning_count=0

pass() {
	pass_count=$((pass_count + 1))
	printf 'PASS  %s\n' "$1"
}

warn() {
	warning_count=$((warning_count + 1))
	printf 'WARN  %s\n' "$1"
}

fail() {
	printf 'FAIL  %s\n' "$1" >&2
	exit 1
}

model="$(ubus call system board | jsonfilter -e '@.model')"
[ "$model" = 'GL.iNet GL-X750' ] || fail "target identity changed: $model"
[ "$(cat /usr/share/ddk-field-console/VERSION 2>/dev/null || true)" = '1.6.0' ] || fail 'Field Console version is not 1.6.0'
pass 'GL-X750 identity and Field Console 1.6.0'

mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail 'extroot is not active on /dev/sda1'
pass 'extroot mounted from /dev/sda1'

[ "$(uci -q get fstab.ddk_install_swap)" = 'swap' ] || fail 'named swap UCI section is missing'
[ "$(uci -q get fstab.ddk_install_swap.device)" = '/overlay/ddk-install.swap' ] || fail 'swap UCI device is incorrect'
[ "$(uci -q get fstab.ddk_install_swap.enabled)" = '1' ] || fail 'swap UCI section is not enabled'
awk '$1 == "/overlay/ddk-install.swap" && $2 == "file" && $3 >= 262000 { found=1 } END { exit !found }' /proc/swaps ||
	fail '/overlay/ddk-install.swap was not activated during boot'
pass 'native fstab boot activation restored the 256 MiB swap file'

root_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ || true)"
luci_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/ || true)"
dashboard_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/admin/ddk/overview || true)"
shortcut_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ddk || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI returned HTTP $luci_http" ;; esac
case "$dashboard_http" in 302|403) ;; *) fail "unauthenticated dashboard did not enforce login: HTTP $dashboard_http" ;; esac
case "$shortcut_http" in 301|302) ;; *) fail "/ddk shortcut returned HTTP $shortcut_http" ;; esac
pass 'GL.iNet UI, LuCI authentication, dashboard, and /ddk shortcut'

timeout 30 /usr/libexec/ddk-console status | jsonfilter -e '@.ok' | grep -qx 'true' || fail 'status API failed'
serial_payload="$(timeout 10 /usr/libexec/ddk-console info serial.inspect)"
printf '%s' "$serial_payload" | jsonfilter -e '@.ok' | grep -qx 'true' || fail 'serial attribution INFO action failed'
printf '%s' "$serial_payload" | jsonfilter -e '@.data.output' | grep -Fq '4 modem-reserved' || fail 'EC25 serial attribution is missing'
pass 'dashboard backend and EC25-safe serial attribution'

[ "$(uci -q get rtl_tcp.main.disabled)" = '1' ] || fail 'the existing rtl_tcp network service is not disabled'
if netstat -lntup 2>/dev/null | grep -Eq '(^|[.:])1234[[:space:]]'; then fail 'the rtl_tcp default listener port is active'; fi
pass 'rtl_tcp remains disabled with no default-port listener'

pidof tailscaled >/dev/null 2>&1 || fail 'tailscaled is not running'
tailscale_ip="$(tailscale ip -4 2>/dev/null || true)"
[ -n "$tailscale_ip" ] || fail 'Tailscale IPv4 address is unavailable'
pass 'Tailscale remains running'

printf '%s  %s\n' \
	fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846 /etc/config/network \
	0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f /etc/config/firewall \
	59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa /etc/config/wireless \
	bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18 /etc/config/uhttpd \
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd \
	500d071555f688b493b2937f8ef1edf7f56dfddd3888aa584e8b572d5db3f2ad /etc/config/rtl_tcp |
	sha256sum -c - >/dev/null || fail 'a protected configuration hash changed'
pass 'network, firewall, wireless, uhttpd, rpcd, and rtl_tcp remain untouched'

if netstat -lntup 2>/dev/null | grep -q 'ddk'; then fail 'a DDK listener exists'; fi
# BusyBox on this target has no standalone pgrep.
# shellcheck disable=SC2009
if ps w | grep '[d]dk-job-worker' >/dev/null 2>&1; then fail 'a DDK job worker is unexpectedly active'; fi
if pidof nmap tcpdump uqmi qmicli qmi-proxy ModemManager rtl_433 rtl_tcp rtl_fm rtl_power rtl_sdr rtl_test rtl_adsb rtl_ais readsb dump1090 >/dev/null 2>&1; then fail 'a bounded-operation client is unexpectedly active'; fi
pass 'no DDK listener or idle operation worker exists'

available_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
[ "${available_kb:-0}" -ge 16384 ] || fail "available memory is low: ${available_kb:-0} KiB"
disk_kb="$(df -Pk /overlay | awk 'NR == 2 {print $4}')"
[ "${disk_kb:-0}" -ge 102400 ] || fail "extroot free space is low: ${disk_kb:-0} KiB"
pass 'memory and extroot free-space thresholds'

if logread -l 250 | grep -Ei 'ddk.*(error|failed|traceback)|luci.*traceback|rpcd.*ddk.*error|swap.*fail' >/dev/null 2>&1; then
	warn 'recent logs contain a possible DDK/LuCI/swap error; inspect logread'
else
	pass 'no obvious DDK, LuCI, rpcd, or swap errors in recent logs'
fi

printf '\nPOST-REBOOT VERIFICATION COMPLETE: %s passed, %s warnings\n' "$pass_count" "$warning_count"
printf 'RAM available: %s KiB\n' "$available_kb"
printf 'Load average: %s\n' "$(cut -d ' ' -f 1-3 /proc/loadavg)"
printf 'Extroot free: %s KiB\n' "$disk_kb"
printf 'Swap: %s\n' "$(awk '$1 == "/overlay/ddk-install.swap" {print $3 " KiB total, " $4 " KiB used, priority " $5}' /proc/swaps)"
printf 'Tailscale IP: %s\n' "$tailscale_ip"
