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

json_ok() {
	jsonfilter -e '@.ok' | grep -qx 'true'
}

model="$(ubus call system board | jsonfilter -e '@.model')"
[ "$model" = 'GL.iNet GL-X750' ] || fail "target identity changed: $model"
pass 'GL-X750 target identity'

mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail 'extroot is not active on /dev/sda1'
pass 'extroot remains active'

grep -q '^/overlay/ddk-install.swap[[:space:]]' /proc/swaps || fail '/overlay/ddk-install.swap is not active'
pass 'USB-backed swap remains active'

for file in \
	/usr/share/luci/menu.d/ddk-field-console.json \
	/usr/share/rpcd/acl.d/ddk-field-console.json \
	/usr/libexec/ddk-console \
	/usr/libexec/ddk-job-worker \
	/usr/lib/lua/luci/view/ddk/shell.htm \
	/www/luci-static/resources/ddk/console-app.js \
	/www/luci-static/resources/ddk/console.css
do
	[ -f "$file" ] || fail "installed file is missing: $file"
done
pass 'project-owned LuCI files are installed'

DDK_LUA_FILE=/usr/libexec/ddk-console lua -e 'assert(loadfile(os.getenv("DDK_LUA_FILE")))' || fail 'Lua backend syntax check failed'
DDK_TEMPLATE_FILE=/usr/lib/lua/luci/view/ddk/shell.htm lua -e 'local parser = require "luci.template.parser"; assert(parser.parse(os.getenv("DDK_TEMPLATE_FILE")))' || fail 'LuCI template syntax check failed'
sh -n /usr/libexec/ddk-job-worker || fail 'job worker syntax check failed'
find /usr/share/ddk-field-console/tools -type f -name '*.json' | while IFS= read -r file; do jsonfilter -i "$file" -e '@' >/dev/null; done
pass 'router-side Lua, shell, and JSON syntax'

/usr/libexec/ddk-console status | json_ok || fail 'status API failed'
/usr/libexec/ddk-console capabilities | json_ok || fail 'capability API failed'
/usr/libexec/ddk-console packages | json_ok || fail 'package API failed'
pass 'status, capability, and package APIs'

for action in system.refresh network.interfaces network.routes hardware.usb hardware.serial remote.tailscale storage.mounts system.memory packages.count; do
	/usr/libexec/ddk-console info "$action" | json_ok || fail "INFO action failed: $action"
done
pass 'all phase-one INFO actions'

injection_marker=/tmp/ddk-injection-marker
rm -f "$injection_marker"
if /usr/libexec/ddk-console info 'network.interfaces;touch /tmp/ddk-injection-marker' 2>/dev/null | json_ok; then
	fail 'malicious action ID was accepted'
fi
[ ! -e "$injection_marker" ] || fail 'browser action reached a shell'
if /usr/libexec/ddk-console job stop 1 2>/dev/null | json_ok; then fail 'generic PID stop was accepted'; fi
if /usr/libexec/ddk-console report view ../../etc/shadow 2>/dev/null | json_ok; then fail 'report path traversal was accepted'; fi
pass 'action injection, generic PID, and traversal rejection'

start_payload="$(/usr/libexec/ddk-console job start diagnostic.demo)"
printf '%s' "$start_payload" | json_ok || fail 'asynchronous proof did not start'
job_id="$(printf '%s' "$start_payload" | jsonfilter -e '@.data.id')"
case "$job_id" in job-[0-9]*-[0-9]*) ;; *) fail 'worker returned an invalid job ID' ;; esac

attempt=0
job_status=""
while [ "$attempt" -lt 15 ]; do
	job_payload="$(/usr/libexec/ddk-console job status "$job_id")"
	job_status="$(printf '%s' "$job_payload" | jsonfilter -e '@.data.status')"
	case "$job_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$job_status" = 'complete' ] || fail "asynchronous proof ended in state: $job_status"
printf '%s' "$job_payload" | jsonfilter -e '@.data.stdout' | grep -q 'ASYNCHRONOUS READ-ONLY PROOF' || fail 'asynchronous proof output is missing'
pass 'non-blocking job framework proof'

report_payload="$(/usr/libexec/ddk-console job start report.system)"
printf '%s' "$report_payload" | json_ok || fail 'system report job did not start'
report_job="$(printf '%s' "$report_payload" | jsonfilter -e '@.data.id')"
report_id="$(printf '%s' "$report_payload" | jsonfilter -e '@.data.metadata.report_id')"
attempt=0
report_status=""
while [ "$attempt" -lt 20 ]; do
	report_status_payload="$(/usr/libexec/ddk-console job status "$report_job")"
	report_status="$(printf '%s' "$report_status_payload" | jsonfilter -e '@.data.status')"
	case "$report_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$report_status" = 'complete' ] || fail "system report ended in state: $report_status"
/usr/libexec/ddk-console report view "$report_id" | json_ok || fail 'authenticated report view failed'
pass 'sanitized system report generation and view'

root_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ || true)"
luci_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/ || true)"
dashboard_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/cgi-bin/luci/admin/ddk/overview || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI returned HTTP $luci_http" ;; esac
[ "$dashboard_http" = '403' ] || [ "$dashboard_http" = '302' ] || [ "$dashboard_http" = '200' ] || fail "dashboard route returned HTTP $dashboard_http"
pass 'GL.iNet UI, LuCI, and authenticated dashboard boundary respond'

pidof tailscaled >/dev/null 2>&1 || fail 'tailscaled is not running'
tailscale_ip="$(tailscale ip -4 2>/dev/null || true)"
[ -n "$tailscale_ip" ] || fail 'Tailscale IPv4 address is unavailable'
pass 'Tailscale remains running'

printf '%s  %s\n' \
	fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846 /etc/config/network \
	0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f /etc/config/firewall \
	59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa /etc/config/wireless \
	bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18 /etc/config/uhttpd \
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd |
	sha256sum -c - >/dev/null || fail 'a protected configuration hash changed'
pass 'network, firewall, wireless, uhttpd, and rpcd are untouched'

if netstat -lntup 2>/dev/null | grep -q 'ddk'; then fail 'a DDK listener exists'; fi
pass 'no DDK network listener exists'

available_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
[ "${available_kb:-0}" -ge 16384 ] || fail "available memory is low: ${available_kb:-0} KiB"
disk_kb="$(df -Pk /overlay | awk 'NR == 2 {print $4}')"
[ "${disk_kb:-0}" -ge 102400 ] || fail "extroot free space is low: ${disk_kb:-0} KiB"
pass 'memory and disk safety thresholds'

if logread -l 250 | grep -Ei 'ddk.*(error|failed|traceback)|luci.*traceback|rpcd.*ddk.*error' >/dev/null 2>&1; then
	warn 'recent logs contain a possible DDK/LuCI error; inspect logread output'
else
	pass 'no obvious DDK/LuCI errors in recent logs'
fi

printf '\nVERIFICATION COMPLETE: %s passed, %s warnings\n' "$pass_count" "$warning_count"
printf 'RAM available: %s KiB\n' "$available_kb"
printf 'Load average: %s\n' "$(cut -d ' ' -f 1-3 /proc/loadavg)"
printf 'Extroot free: %s KiB\n' "$disk_kb"
printf 'Tailscale IP: %s\n' "$tailscale_ip"
