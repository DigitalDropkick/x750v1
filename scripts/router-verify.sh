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

[ "$(cat /usr/share/ddk-field-console/VERSION 2>/dev/null || true)" = '1.4.0' ] || fail 'Field Console version is not 1.4.0'
pass 'Field Console version 1.4.0'

mount | grep -q '^/dev/sda1 on /overlay type ext4 ' || fail 'extroot is not active on /dev/sda1'
pass 'extroot remains active'

grep -q '^/overlay/ddk-install.swap[[:space:]]' /proc/swaps || fail '/overlay/ddk-install.swap is not active'
[ "$(uci -q get fstab.ddk_install_swap)" = 'swap' ] || fail 'named swap UCI section is missing'
[ "$(uci -q get fstab.ddk_install_swap.device)" = '/overlay/ddk-install.swap' ] || fail 'swap UCI device is incorrect'
[ "$(uci -q get fstab.ddk_install_swap.enabled)" = '1' ] || fail 'swap UCI section is not enabled'
pass 'USB-backed swap is active and configured for native boot activation'

for file in \
	/usr/share/luci/menu.d/ddk-field-console.json \
	/usr/share/rpcd/acl.d/ddk-field-console.json \
	/usr/libexec/ddk-console \
	/usr/libexec/ddk-job-worker \
	/usr/lib/lua/luci/view/ddk/shell.htm \
	/www/luci-static/resources/ddk/console-app.js \
	/www/luci-static/resources/ddk/console.css \
	/www/luci-static/resources/ddk/brand/dropkick-logo.png \
	/www/luci-static/resources/ddk/brand/overview.webp \
	/www/luci-static/resources/ddk/brand/tools.webp \
	/www/luci-static/resources/ddk/brand/packages.webp \
	/www/luci-static/resources/ddk/brand/jobs.webp \
	/www/luci-static/resources/ddk/brand/settings.webp \
	/www/ddk/gl_home.html
do
	[ -f "$file" ] || fail "installed file is missing: $file"
done
pass 'project-owned LuCI files are installed'

for asset in dropkick-logo.png overview.webp tools.webp packages.webp jobs.webp settings.webp; do
	asset_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1/luci-static/resources/ddk/brand/$asset" || true)"
	[ "$asset_http" = '200' ] || fail "brand asset returned HTTP $asset_http: $asset"
done
pass 'local Digital Dropkick brand assets are served by the existing web stack'

DDK_LUA_FILE=/usr/libexec/ddk-console lua -e 'assert(loadfile(os.getenv("DDK_LUA_FILE")))' || fail 'Lua backend syntax check failed'
DDK_TEMPLATE_FILE=/usr/lib/lua/luci/view/ddk/shell.htm lua -e 'local parser = require "luci.template.parser"; assert(parser.parse(os.getenv("DDK_TEMPLATE_FILE")))' || fail 'LuCI template syntax check failed'
sh -n /usr/libexec/ddk-job-worker || fail 'job worker syntax check failed'
find /usr/share/ddk-field-console/tools -type f -name '*.json' | while IFS= read -r file; do jsonfilter -i "$file" -e '@' >/dev/null; done
pass 'router-side Lua, shell, and JSON syntax'

/usr/libexec/ddk-console status | json_ok || fail 'status API failed'
/usr/libexec/ddk-console capabilities | json_ok || fail 'capability API failed'
/usr/libexec/ddk-console packages | json_ok || fail 'package API failed'
pass 'status, capability, and package APIs'

for action in system.refresh network.interfaces network.routes hardware.usb hardware.serial serial.inspect remote.tailscale storage.mounts system.memory packages.count; do
	/usr/libexec/ddk-console info "$action" | json_ok || fail "INFO action failed: $action"
done
pass 'all phase-one INFO actions'

serial_payload="$(/usr/libexec/ddk-console info serial.inspect)"
serial_output="$(printf '%s' "$serial_payload" | jsonfilter -e '@.data.output')"
printf '%s' "$serial_output" | grep -Fq 'Policy: read metadata only; no serial port was opened.' || fail 'serial action safety declaration is missing'
for node in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
	printf '%s' "$serial_output" | grep -Fq "$node" || fail "serial attribution is missing $node"
done
[ "$(printf '%s' "$serial_output" | grep -c 'Classification: MODEM RESERVED')" -eq 4 ] || fail 'all four EC25 serial functions were not marked modem-reserved'
[ "$(printf '%s' "$serial_output" | grep -c 'USB: 2c7c:0125')" -eq 4 ] || fail 'EC25 VID:PID attribution count is incorrect'
[ "$(printf '%s' "$serial_output" | grep -c 'Driver: option')" -eq 4 ] || fail 'EC25 serial driver attribution count is incorrect'
printf '%s' "$serial_output" | grep -Fq 'Summary: 4 total; 4 modem-reserved; 0 reviewed general-purpose; 0 unreviewed; 0 unattributed.' || fail 'serial attribution summary is incorrect'
if printf '%s' "$serial_output" | grep -Fq 'Generic use allowed: YES'; then fail 'an EC25 port was authorized for generic use'; fi
status_payload="$(/usr/libexec/ddk-console status)"
[ "$(printf '%s' "$status_payload" | jsonfilter -e '@.data.hardware.serial_summary.modem_reserved')" = '4' ] || fail 'status API modem-reserved count is incorrect'
[ "$(printf '%s' "$status_payload" | jsonfilter -e '@.data.hardware.serial_summary.reviewed_general_purpose')" = '0' ] || fail 'status API incorrectly exposes general-purpose serial hardware'
serial_manifest=/usr/share/ddk-field-console/tools/serial.json
[ "$(jsonfilter -i "$serial_manifest" -e '@.enabled')" = 'true' ] || fail 'serial attribution module is not enabled'
[ "$(jsonfilter -i "$serial_manifest" -e '@.actions[0].id')" = 'serial.inspect' ] || fail 'serial INFO action ID is incorrect'
[ "$(jsonfilter -i "$serial_manifest" -e '@.actions[0].class')" = 'INFO' ] || fail 'serial inspection lost its INFO classification'
[ "$(jsonfilter -i "$serial_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'serial inspection is not explicitly enabled'
[ "$(jsonfilter -i "$serial_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'serial session placeholder was unexpectedly enabled'
pass 'EC25 serial ownership and modem-reserved policy'

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

cellular_manifest=/usr/share/ddk-field-console/tools/cellular.json
[ "$(jsonfilter -i "$cellular_manifest" -e '@.enabled')" = 'true' ] || fail 'cellular module is not enabled'
[ "$(jsonfilter -i "$cellular_manifest" -e '@.actions[0].id')" = 'cellular.snapshot' ] || fail 'cellular snapshot manifest ID is incorrect'
[ "$(jsonfilter -i "$cellular_manifest" -e '@.actions[0].class')" = 'INFO' ] || fail 'cellular snapshot lost its INFO classification'
[ "$(jsonfilter -i "$cellular_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'cellular snapshot execution mode is incorrect'
[ "$(jsonfilter -i "$cellular_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'cellular snapshot is not explicitly enabled'
[ -x /sbin/uqmi ] || fail 'already-installed UQMI executable is unavailable'
[ -c /dev/cdc-wdm0 ] || fail 'expected QMI management device is unavailable'
pass 'reviewed cellular manifest, UQMI, and QMI device'

cellular_before="$(ubus call network.interface.wwan status | jsonfilter -e '@.up' -e '@.pending' -e '@.available' -e '@.l3_device')"
cellular_payload="$(/usr/libexec/ddk-console job start cellular.snapshot)"
printf '%s' "$cellular_payload" | json_ok || fail 'cellular snapshot did not start'
cellular_job="$(printf '%s' "$cellular_payload" | jsonfilter -e '@.data.id')"
if /usr/libexec/ddk-console job start cellular.snapshot 2>/dev/null | json_ok; then
	fail 'a second concurrent cellular snapshot was accepted'
fi
attempt=0
cellular_status=''
while [ "$attempt" -lt 40 ]; do
	cellular_state="$(/usr/libexec/ddk-console job status "$cellular_job")"
	cellular_status="$(printf '%s' "$cellular_state" | jsonfilter -e '@.data.status')"
	case "$cellular_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$cellular_status" = 'complete' ] || fail "cellular snapshot ended in state: $cellular_status"
cellular_output="$(printf '%s' "$cellular_state" | jsonfilter -e '@.data.stdout')"
printf '%s' "$cellular_state" | jsonfilter -e '@.data.metadata.class' | grep -qx 'INFO' || fail 'cellular job metadata class is incorrect'
printf '%s' "$cellular_output" | grep -Fq 'Model: Quectel EC25-AF' || fail 'cellular modem identity is missing'
printf '%s' "$cellular_output" | grep -Fq 'Management: /dev/cdc-wdm0 via qmi_wwan' || fail 'cellular management attribution is missing'
printf '%s' "$cellular_output" | grep -Fq 'Operating mode:' || fail 'cellular operating mode is missing'
printf '%s' "$cellular_output" | grep -Fq 'State:' || fail 'cellular registration state is missing'
printf '%s' "$cellular_output" | grep -Fq 'Radio:' || fail 'cellular radio type is missing'
printf '%s' "$cellular_output" | grep -Fq 'RSSI:' || fail 'cellular RSSI is missing'
printf '%s' "$cellular_output" | grep -Fq 'Query status: 4/4 succeeded' || fail 'not all cellular read-only queries succeeded'
if printf '%s' "$cellular_output" | grep -Eiq 'IMEI:|IMSI:|ICCID:|MSISDN:|phone number:|APN:|PIN:|PUK:|password:|username:|plmn_description'; then
	fail 'cellular snapshot exposed an excluded sensitive field'
fi
cellular_after="$(ubus call network.interface.wwan status | jsonfilter -e '@.up' -e '@.pending' -e '@.available' -e '@.l3_device')"
[ "$cellular_before" = "$cellular_after" ] || fail 'WWAN state changed during the cellular snapshot'
if pidof uqmi qmicli qmi-proxy ModemManager >/dev/null 2>&1; then fail 'a cellular client or manager remained running'; fi
pass 'bounded privacy-conscious cellular snapshot'

nmap_manifest=/usr/share/ddk-field-console/tools/network-discovery.json
[ "$(jsonfilter -i "$nmap_manifest" -e '@.enabled')" = 'true' ] || fail 'Nmap discovery module is not enabled'
[ "$(jsonfilter -i "$nmap_manifest" -e '@.actions[0].id')" = 'network.nmap_lan_discovery' ] || fail 'Nmap action manifest ID is incorrect'
[ "$(jsonfilter -i "$nmap_manifest" -e '@.actions[0].class')" = 'SECURITY' ] || fail 'Nmap action lost its SECURITY classification'
[ "$(jsonfilter -i "$nmap_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'Nmap action is not explicitly enabled'
[ -x /usr/bin/nmap ] || fail 'already-installed Nmap executable is unavailable'
pass 'reviewed Nmap manifest and installed executable'

if /usr/libexec/ddk-console job start 'network.nmap_lan_discovery;touch' 2>/dev/null | json_ok; then
	fail 'malformed Nmap action ID was accepted'
fi

stop_scan_payload="$(/usr/libexec/ddk-console job start network.nmap_lan_discovery)"
printf '%s' "$stop_scan_payload" | json_ok || fail 'bounded Nmap stop proof did not start'
stop_scan_id="$(printf '%s' "$stop_scan_payload" | jsonfilter -e '@.data.id')"
if /usr/libexec/ddk-console job start network.nmap_lan_discovery 2>/dev/null | json_ok; then
	fail 'a second concurrent Nmap discovery was accepted'
fi

attempt=0
stop_scan_status=''
while [ "$attempt" -lt 8 ]; do
	stop_scan_state="$(/usr/libexec/ddk-console job status "$stop_scan_id")"
	stop_scan_status="$(printf '%s' "$stop_scan_state" | jsonfilter -e '@.data.status')"
	stop_scan_pid="$(printf '%s' "$stop_scan_state" | jsonfilter -e '@.data.pid')"
	[ "$stop_scan_status" = 'running' ] && [ -n "$stop_scan_pid" ] && break
	case "$stop_scan_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$stop_scan_status" = 'running' ] || fail "Nmap stop proof was not active long enough to cancel: $stop_scan_status"
/usr/libexec/ddk-console job stop "$stop_scan_id" | json_ok || fail 'authenticated Nmap stop request failed'
attempt=0
while [ "$attempt" -lt 8 ]; do
	stop_scan_state="$(/usr/libexec/ddk-console job status "$stop_scan_id")"
	stop_scan_status="$(printf '%s' "$stop_scan_state" | jsonfilter -e '@.data.status')"
	[ "$stop_scan_status" = 'stopped' ] && break
	attempt=$((attempt + 1))
	sleep 1
done
[ "$stop_scan_status" = 'stopped' ] || fail "Nmap stop proof ended in state: $stop_scan_status"
printf '%s' "$stop_scan_state" | jsonfilter -e '@.data.stderr' | grep -q 'authenticated DDK request' || fail 'Nmap worker stop evidence is missing'
pass 'Nmap singleton enforcement and DDK-owned cancellation'

scan_payload="$(/usr/libexec/ddk-console job start network.nmap_lan_discovery)"
printf '%s' "$scan_payload" | json_ok || fail 'bounded Nmap discovery did not start'
scan_id="$(printf '%s' "$scan_payload" | jsonfilter -e '@.data.id')"
attempt=0
scan_status=''
while [ "$attempt" -lt 90 ]; do
	scan_state="$(/usr/libexec/ddk-console job status "$scan_id")"
	scan_status="$(printf '%s' "$scan_state" | jsonfilter -e '@.data.status')"
	case "$scan_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$scan_status" = 'complete' ] || fail "bounded Nmap discovery ended in state: $scan_status"
scan_output="$(printf '%s' "$scan_state" | jsonfilter -e '@.data.stdout')"
lan_cidr="$(ip -o -4 addr show dev br-lan scope global | awk '$3 == "inet" { print $4; exit }')"
printf '%s' "$scan_state" | jsonfilter -e '@.data.metadata.class' | grep -qx 'SECURITY' || fail 'Nmap job metadata class is incorrect'
printf '%s' "$scan_output" | grep -Fq 'Scope source: network.interface.lan / br-lan (server-derived)' || fail 'Nmap scope evidence is missing'
printf '%s' "$scan_output" | grep -Fq "Target: $lan_cidr" || fail 'Nmap did not use the current server-derived LAN CIDR'
printf '%s' "$scan_output" | grep -Fq 'Profile: host discovery only (-sn), no DNS (-n), no port scan' || fail 'Nmap fixed-profile evidence is missing'
printf '%s' "$scan_output" | grep -Fq 'Nmap done:' || fail 'Nmap completion summary is missing'
[ "$(printf '%s' "$scan_output" | wc -c)" -le 131072 ] || fail 'Nmap stdout exceeded its bound'
pass 'bounded server-derived Nmap LAN discovery'

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
shortcut_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/ddk || true)"
shortcut_page="$(curl -sS --max-time 8 http://127.0.0.1/ddk/ || true)"
[ "$root_http" = '200' ] || fail "GL.iNet UI returned HTTP $root_http"
case "$luci_http" in 200|302|403) ;; *) fail "LuCI returned HTTP $luci_http" ;; esac
[ "$dashboard_http" = '403' ] || [ "$dashboard_http" = '302' ] || [ "$dashboard_http" = '200' ] || fail "dashboard route returned HTTP $dashboard_http"
[ "$shortcut_http" = '301' ] || [ "$shortcut_http" = '302' ] || fail "/ddk shortcut returned HTTP $shortcut_http"
printf '%s' "$shortcut_page" | grep -Fq 'content="0;url=/cgi-bin/luci/admin/ddk/overview"' || fail '/ddk shortcut target is incorrect'
printf '%s' "$shortcut_page" | grep -Fq 'Continue to the authenticated console' || fail '/ddk shortcut fallback is missing'
pass 'GL.iNet UI, LuCI, authenticated dashboard, and /ddk shortcut respond'

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
