#!/bin/sh

set -eu

pass_count=0
warning_count=0
identity_fixture=""

cleanup_identity_fixture() {
	case "$identity_fixture" in
		/tmp/ddk-usb-identity-test.*) rm -rf -- "$identity_fixture" ;;
	esac
	identity_fixture=""
}

trap cleanup_identity_fixture EXIT
trap 'exit 130' HUP INT TERM

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

[ "$(cat /usr/share/ddk-field-console/VERSION 2>/dev/null || true)" = '2.0.0' ] || fail 'Field Console version is not 2.0.0'
pass 'Field Console version 2.0.0'

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
	/usr/share/ddk-field-console/usb-identity.lua \
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
DDK_IDENTITY_FILE=/usr/share/ddk-field-console/usb-identity.lua lua -e 'assert(loadfile(os.getenv("DDK_IDENTITY_FILE")))' || fail 'USB identity module syntax check failed'
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

for identity_manifest in android-repair apple-repair firmware-programming; do
	manifest="/usr/share/ddk-field-console/tools/$identity_manifest.json"
	[ "$(jsonfilter -i "$manifest" -e '@.enabled')" = 'true' ] || fail "identity module is not enabled: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.no_device_state')" = 'READY / NO DEVICE' ] || fail "identity no-device state is incorrect: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[0].class')" = 'INFO' ] || fail "identity action lost INFO classification: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[0].enabled')" = 'true' ] || fail "identity action is disabled: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[1].class')" = 'INFO' ] || fail "operator guide lost INFO classification: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[1].enabled')" = 'true' ] || fail "operator guide is disabled: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[2].class')" = 'DISRUPTIVE' ] || fail "device-changing placeholder lost its risk class: $identity_manifest"
	[ "$(jsonfilter -i "$manifest" -e '@.actions[2].enabled')" = 'false' ] || fail "device-changing placeholder was unexpectedly enabled: $identity_manifest"
done

identity_fixture="$(mktemp -d /tmp/ddk-usb-identity-test.XXXXXX)"
fixture="$identity_fixture/fixture"
mkdir -p "$fixture/7-1" "$fixture/7-1:1.0" "$fixture/7-2" "$fixture/7-3" "$fixture/7-4" "$fixture/7-5"
printf %s 18d1 > "$fixture/7-1/idVendor"
printf %s 4ee7 > "$fixture/7-1/idProduct"
printf %s Google > "$fixture/7-1/manufacturer"
printf %s 'Pixel 9' > "$fixture/7-1/product"
printf %s 'Customer-Android-123' > "$fixture/7-1/serial"
printf %s 480 > "$fixture/7-1/speed"
printf %s ff > "$fixture/7-1:1.0/bInterfaceClass"
printf %s 42 > "$fixture/7-1:1.0/bInterfaceSubClass"
printf %s 01 > "$fixture/7-1:1.0/bInterfaceProtocol"
printf %s 00 > "$fixture/7-1:1.0/bInterfaceNumber"
printf %s 05ac > "$fixture/7-2/idVendor"
printf %s 12a8 > "$fixture/7-2/idProduct"
printf %s 'Apple Inc.' > "$fixture/7-2/manufacturer"
printf %s 'Apple Mobile Device (Recovery Mode)' > "$fixture/7-2/product"
printf %s '00008020-PRIVATE' > "$fixture/7-2/serial"
printf %s 1366 > "$fixture/7-3/idVendor"
printf %s 0105 > "$fixture/7-3/idProduct"
printf %s SEGGER > "$fixture/7-3/manufacturer"
printf %s 'J-Link' > "$fixture/7-3/product"
printf %s 'PROBE-123' > "$fixture/7-3/serial"
printf %s 05ac > "$fixture/7-4/idVendor"
printf %s 8290 > "$fixture/7-4/idProduct"
printf %s 'Apple Inc.' > "$fixture/7-4/manufacturer"
printf %s 'Bluetooth Host Controller' > "$fixture/7-4/product"
printf %s 0403 > "$fixture/7-5/idVendor"
printf %s 6001 > "$fixture/7-5/idProduct"
printf %s FTDI > "$fixture/7-5/manufacturer"
printf %s 'FT232R USB UART' > "$fixture/7-5/product"
DDK_FIXTURE="$fixture" lua - <<'LUA'
local identity = dofile("/usr/share/ddk-field-console/usb-identity.lua")
local result = identity.scan(os.getenv("DDK_FIXTURE"))
assert(#result.android == 1, "Android fixture count")
assert(result.android[1].identity == "ADB USB INTERFACE", "Android fixture mode")
assert(#result.apple_mobile == 1, "Apple fixture count")
assert(result.apple_mobile[1].identity == "RECOVERY MODE DESCRIPTOR", "Apple fixture mode")
assert(#result.programmer == 1, "programmer fixture count")
assert(result.programmer[1].identity == "SEGGER J-Link", "programmer fixture identity")
assert(result.inspected_count == 5, "fixture inspection count")
LUA
cleanup_identity_fixture
pass 'positive USB identity fixtures and conservative false-positive rejection'

identity_jobs_before="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
identity_processes_before="$(pidof adb usbmuxd idevice_id ideviceinfo idevicepair irecovery idevicerestore openocd avrdude dfu-util dfu-programmer flashrom stm32flash bossac lpc21isp ftdi_eeprom 2>/dev/null || true)"
identity_listeners_before="$(netstat -lntup 2>/dev/null | grep -E ':(5037|27015)[[:space:]]' || true)"
for identity_action in android.identify apple.identify firmware.identify; do
	payload="$(/usr/libexec/ddk-console info "$identity_action")"
	printf '%s' "$payload" | json_ok || fail "private identity action failed: $identity_action"
	output="$(printf '%s' "$payload" | jsonfilter -e '@.data.output')"
	printf '%s' "$output" | grep -Fq 'Policy: sysfs metadata only' || fail "sysfs-only declaration is missing: $identity_action"
	printf '%s' "$output" | grep -Fq 'not written to jobs, reports, logs, or persistent storage' || fail "private-retention declaration is missing: $identity_action"
	printf '%s' "$output" | grep -Fq 'Output lifetime: browser memory only' || fail "browser-memory lifetime is missing: $identity_action"
done
for guide_action in android.operator_guide apple.operator_guide firmware.operator_guide; do
	payload="$(/usr/libexec/ddk-console info "$guide_action")"
	printf '%s' "$payload" | json_ok || fail "full CLI handoff failed: $guide_action"
	output="$(printf '%s' "$payload" | jsonfilter -e '@.data.output')"
	printf '%s' "$output" | grep -Fq 'The installed CLI tools retain their full native functionality' || fail "full CLI assurance is missing: $guide_action"
	printf '%s' "$output" | grep -Fq 'The browser does not execute any displayed command' || fail "non-execution declaration is missing: $guide_action"
	printf '%s' "$output" | grep -Fq 'No command above was run by this request.' || fail "handoff completion declaration is missing: $guide_action"
done
identity_jobs_after="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
[ "$identity_jobs_before" = "$identity_jobs_after" ] || fail 'an immediate identity/guide action created a DDK job'
[ "$identity_processes_before" = "$(pidof adb usbmuxd idevice_id ideviceinfo idevicepair irecovery idevicerestore openocd avrdude dfu-util dfu-programmer flashrom stm32flash bossac lpc21isp ftdi_eeprom 2>/dev/null || true)" ] || fail 'identity actions changed a mobile/programmer process state'
[ "$identity_listeners_before" = "$(netstat -lntup 2>/dev/null | grep -E ':(5037|27015)[[:space:]]' || true)" ] || fail 'identity actions changed an ADB/mobile listener state'
pass 'private transient identity and full native-CLI handoff actions'

injection_marker=/tmp/ddk-injection-marker
rm -f "$injection_marker"
if /usr/libexec/ddk-console info 'network.interfaces;touch /tmp/ddk-injection-marker' 2>/dev/null | json_ok; then
	fail 'malicious action ID was accepted'
fi
if /usr/libexec/ddk-console info 'android.identify;touch /tmp/ddk-injection-marker' 2>/dev/null | json_ok; then
	fail 'malicious private identity action ID was accepted'
fi
if /usr/libexec/ddk-console info android.identify unexpected 2>/dev/null | json_ok; then
	fail 'an extra private identity argument was accepted'
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

capture_manifest=/usr/share/ddk-field-console/tools/packet-capture.json
[ "$(jsonfilter -i "$capture_manifest" -e '@.enabled')" = 'true' ] || fail 'packet-capture module is not enabled'
[ "$(jsonfilter -i "$capture_manifest" -e '@.actions[0].id')" = 'capture.lan_metadata_snapshot' ] || fail 'LAN metadata capture action ID is incorrect'
[ "$(jsonfilter -i "$capture_manifest" -e '@.actions[0].class')" = 'SECURITY' ] || fail 'LAN metadata capture lost its SECURITY classification'
[ "$(jsonfilter -i "$capture_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'LAN metadata capture execution mode is incorrect'
[ "$(jsonfilter -i "$capture_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'LAN metadata capture is not explicitly enabled'
[ "$(jsonfilter -i "$capture_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'packet replay was unexpectedly enabled'
[ -x /usr/sbin/tcpdump ] || fail 'the reviewed tcpdump executable is unavailable'
/usr/sbin/tcpdump -i br-lan -p -n -q -s 96 -c 1 -d 'arp or icmp or (ip and udp and (port 67 or port 68))' >/dev/null 2>&1 || fail 'the fixed LAN metadata filter did not compile'
pass 'reviewed LAN metadata manifest, tcpdump path, and fixed filter'

if /usr/libexec/ddk-console job start 'capture.lan_metadata_snapshot;touch' 2>/dev/null | json_ok; then
	fail 'malformed LAN metadata capture action ID was accepted'
fi
if /usr/libexec/ddk-console job start capture.lan_metadata_snapshot br-lan 2>/dev/null | json_ok; then
	fail 'a browser-supplied capture interface was accepted'
fi

capture_flags_before="$(cat /sys/class/net/br-lan/flags)"
stop_capture_payload="$(/usr/libexec/ddk-console job start capture.lan_metadata_snapshot)"
printf '%s' "$stop_capture_payload" | json_ok || fail 'bounded capture stop proof did not start'
stop_capture_id="$(printf '%s' "$stop_capture_payload" | jsonfilter -e '@.data.id')"
if /usr/libexec/ddk-console job start capture.lan_metadata_snapshot 2>/dev/null | json_ok; then
	fail 'a second concurrent LAN metadata capture was accepted'
fi

attempt=0
stop_capture_status=''
while [ "$attempt" -lt 8 ]; do
	stop_capture_state="$(/usr/libexec/ddk-console job status "$stop_capture_id")"
	stop_capture_status="$(printf '%s' "$stop_capture_state" | jsonfilter -e '@.data.status')"
	stop_capture_pid="$(printf '%s' "$stop_capture_state" | jsonfilter -e '@.data.pid')"
	[ "$stop_capture_status" = 'running' ] && [ -n "$stop_capture_pid" ] && break
	case "$stop_capture_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$stop_capture_status" = 'running' ] || fail "capture stop proof was not active long enough to cancel: $stop_capture_status"
[ "$(cat /sys/class/net/br-lan/flags)" = "$capture_flags_before" ] || fail 'br-lan flags changed while non-promiscuous capture was active'
/usr/libexec/ddk-console job stop "$stop_capture_id" | json_ok || fail 'authenticated capture stop request failed'
attempt=0
while [ "$attempt" -lt 8 ]; do
	stop_capture_state="$(/usr/libexec/ddk-console job status "$stop_capture_id")"
	stop_capture_status="$(printf '%s' "$stop_capture_state" | jsonfilter -e '@.data.status')"
	[ "$stop_capture_status" = 'stopped' ] && break
	attempt=$((attempt + 1))
	sleep 1
done
[ "$stop_capture_status" = 'stopped' ] || fail "capture stop proof ended in state: $stop_capture_status"
printf '%s' "$stop_capture_state" | jsonfilter -e '@.data.stderr' | grep -q 'authenticated DDK request' || fail 'capture worker stop evidence is missing'
[ "$(cat /sys/class/net/br-lan/flags)" = "$capture_flags_before" ] || fail 'br-lan flags changed after capture cancellation'
if pidof tcpdump >/dev/null 2>&1; then fail 'tcpdump remained active after DDK capture cancellation'; fi
pass 'capture singleton, non-promiscuous mode, and DDK-owned cancellation'

capture_payload="$(/usr/libexec/ddk-console job start capture.lan_metadata_snapshot)"
printf '%s' "$capture_payload" | json_ok || fail 'bounded LAN metadata snapshot did not start'
capture_id="$(printf '%s' "$capture_payload" | jsonfilter -e '@.data.id')"
attempt=0
capture_status=''
while [ "$attempt" -lt 30 ]; do
	capture_state="$(/usr/libexec/ddk-console job status "$capture_id")"
	capture_status="$(printf '%s' "$capture_state" | jsonfilter -e '@.data.status')"
	case "$capture_status" in complete|failed|stopped) break ;; esac
	attempt=$((attempt + 1))
	sleep 1
done
[ "$capture_status" = 'complete' ] || fail "bounded LAN metadata snapshot ended in state: $capture_status"
capture_output="$(printf '%s' "$capture_state" | jsonfilter -e '@.data.stdout')"
printf '%s' "$capture_state" | jsonfilter -e '@.data.metadata.class' | grep -qx 'SECURITY' || fail 'capture job metadata class is incorrect'
printf '%s' "$capture_output" | grep -Fq 'Scope source: network.interface.lan / br-lan (server-derived)' || fail 'capture scope evidence is missing'
printf '%s' "$capture_output" | grep -Fq 'Profile: ARP, ICMP, and IPv4 DHCP metadata only; decoded text, no PCAP file' || fail 'capture fixed-profile evidence is missing'
printf '%s' "$capture_output" | grep -Fq 'Safety: non-promiscuous (-p), no DNS (-n), quiet decode (-q), no payload dump' || fail 'capture safety declaration is missing'
printf '%s' "$capture_output" | grep -Fq 'Limits: 20-second window, 128 packets, 96-byte snap length, 64 KiB text output' || fail 'capture limits declaration is missing'
printf '%s' "$capture_output" | grep -Fq 'Stop condition:' || fail 'capture stop-condition evidence is missing'
printf '%s' "$capture_output" | grep -Fq "Interface flags: $capture_flags_before before / $capture_flags_before after" || fail 'capture interface-flag evidence is missing'
[ "$(printf '%s' "$capture_output" | wc -c)" -le 65536 ] || fail 'capture stdout exceeded its 64 KiB bound'
if find "/tmp/ddk/jobs/$capture_id" -type f -name '*.pcap*' | grep -q .; then fail 'capture created a prohibited PCAP file'; fi
if pidof tcpdump >/dev/null 2>&1; then fail 'tcpdump remained active after bounded capture completion'; fi
[ "$(cat /sys/class/net/br-lan/flags)" = "$capture_flags_before" ] || fail 'br-lan flags changed after bounded capture completion'
pass 'bounded transient LAN metadata snapshot'

radio_manifest=/usr/share/ddk-field-console/tools/sdr-radio.json
[ "$(jsonfilter -i "$radio_manifest" -e '@.enabled')" = 'true' ] || fail 'SDR/radio module is not enabled'
[ "$(jsonfilter -i "$radio_manifest" -e '@.actions[0].id')" = 'radio.rtl433_snapshot' ] || fail 'RTL-433 action ID is incorrect'
[ "$(jsonfilter -i "$radio_manifest" -e '@.actions[0].class')" = 'ACTION' ] || fail 'RTL-433 action lost its ACTION classification'
[ "$(jsonfilter -i "$radio_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'RTL-433 action execution mode is incorrect'
[ "$(jsonfilter -i "$radio_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'RTL-433 action is not explicitly enabled'
[ "$(jsonfilter -i "$radio_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'AIS receive was unexpectedly enabled'
[ -x /usr/bin/rtl_433 ] || fail 'the reviewed rtl_433 executable is unavailable'
rtl_version_output="$(/usr/bin/rtl_433 -c /dev/null -V 2>&1)" || fail 'rtl_433 rejected the explicit empty-config invocation'
printf '%s' "$rtl_version_output" | grep -Fq 'rtl_433 version' || fail 'rtl_433 version evidence is missing'
if printf '%s' "$rtl_version_output" | grep -Fq 'Trying conf file'; then fail 'rtl_433 ignored the explicit empty-config boundary'; fi
[ "$(uci -q get rtl_tcp.main.disabled)" = '1' ] || fail 'the existing rtl_tcp network service is not disabled'
if pidof rtl_433 rtl_tcp rtl_fm rtl_power rtl_sdr rtl_test rtl_adsb rtl_ais readsb dump1090 >/dev/null 2>&1; then fail 'a radio receiver was active before hardware-gate verification'; fi
if netstat -lntup 2>/dev/null | grep -Eq '(^|[.:])1234[[:space:]]'; then fail 'the rtl_tcp default listener port is active'; fi
pass 'reviewed RTL-433 manifest, executable, empty-config boundary, and listener state'

if /usr/libexec/ddk-console job start 'radio.rtl433_snapshot;touch' 2>/dev/null | json_ok; then
	fail 'malformed RTL-433 action ID was accepted'
fi
if /usr/libexec/ddk-console job start radio.rtl433_snapshot 433920000 2>/dev/null | json_ok; then
	fail 'a browser-supplied RTL-433 frequency was accepted'
fi

radio_capabilities="$(/usr/libexec/ddk-console capabilities)"
radio_ready="$(printf '%s' "$radio_capabilities" | jsonfilter -e '@.data[@.id="sdr-radio"].hardware.present')"
radio_state="$(printf '%s' "$radio_capabilities" | jsonfilter -e '@.data[@.id="sdr-radio"].state')"
[ "$(printf '%s' "$radio_capabilities" | jsonfilter -e '@.data[@.id="sdr-radio"].console_enabled')" = 'true' ] || fail 'RTL-433 console module is not enabled'
if [ "$radio_ready" = 'true' ]; then
	[ "$radio_state" = 'READY' ] || fail "reviewed RTL-SDR hardware has inconsistent capability state: $radio_state"
	warn 'reviewed RTL-SDR hardware is attached; run the receiver only through its explicit UI confirmation'
else
	[ "$radio_state" = 'HARDWARE REQUIRED' ] || fail "absent/unready RTL-SDR has incorrect capability state: $radio_state"
	radio_jobs_before="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	radio_rejection="$(/usr/libexec/ddk-console job start radio.rtl433_snapshot 2>/dev/null || true)"
	[ "$(printf '%s' "$radio_rejection" | jsonfilter -e '@.ok')" = 'false' ] || fail 'hardware-gated RTL-433 start was not rejected'
	printf '%s' "$radio_rejection" | jsonfilter -e '@.message' | grep -Fq 'Reviewed RTL-SDR hardware is not ready' || fail 'RTL-433 hardware rejection message is missing'
	radio_jobs_after="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	[ "$radio_jobs_before" = "$radio_jobs_after" ] || fail 'rejected RTL-433 start created a transient job'
	if pidof rtl_433 rtl_tcp rtl_fm rtl_power rtl_sdr rtl_test rtl_adsb rtl_ais readsb dump1090 >/dev/null 2>&1; then fail 'hardware rejection started a radio process'; fi

	radio_worker_probe_id="job-$(date +%s)-$$"
	radio_worker_probe_dir="/tmp/ddk/jobs/$radio_worker_probe_id"
	[ ! -e "$radio_worker_probe_dir" ] || fail 'generated RTL-433 worker-probe ID collided'
	mkdir "$radio_worker_probe_dir"
	chmod 700 "$radio_worker_probe_dir"
	printf '%s\n' queued > "$radio_worker_probe_dir/status"
	printf '%s\n' '{}' > "$radio_worker_probe_dir/metadata.json"
	: > "$radio_worker_probe_dir/stdout"
	: > "$radio_worker_probe_dir/stderr"
	radio_worker_result=0
	/usr/libexec/ddk-job-worker "$radio_worker_probe_id" rtl433_snapshot >/dev/null 2>&1 || radio_worker_result=$?
	radio_worker_status="$(cat "$radio_worker_probe_dir/status" 2>/dev/null || true)"
	radio_worker_error="$(cat "$radio_worker_probe_dir/stderr" 2>/dev/null || true)"
	rm -f "$radio_worker_probe_dir/pid" "$radio_worker_probe_dir/status" "$radio_worker_probe_dir/metadata.json" \
		"$radio_worker_probe_dir/stdout" "$radio_worker_probe_dir/stderr" "$radio_worker_probe_dir/rtl433.output" "$radio_worker_probe_dir/rtl433.stderr"
	rmdir "$radio_worker_probe_dir"
	[ "$radio_worker_result" -eq 65 ] || fail "independent RTL-433 worker gate returned $radio_worker_result instead of 65"
	[ "$radio_worker_status" = 'failed' ] || fail "independent RTL-433 worker gate ended in state: $radio_worker_status"
	printf '%s' "$radio_worker_error" | grep -Fq 'Exactly one reviewed RTL-SDR USB device' || fail 'independent RTL-433 worker rejection evidence is missing'
	if pidof rtl_433 rtl_tcp rtl_fm rtl_power rtl_sdr rtl_test rtl_adsb rtl_ais readsb dump1090 >/dev/null 2>&1; then fail 'independent hardware rejection started a radio process'; fi
	pass 'RTL-433 backend/worker hardware gates and no-device refusal path'
fi

camera_manifest=/usr/share/ddk-field-console/tools/camera.json
[ "$(jsonfilter -i "$camera_manifest" -e '@.enabled')" = 'true' ] || fail 'camera module is not enabled'
[ "$(jsonfilter -i "$camera_manifest" -e '@.actions[0].id')" = 'camera.still_snapshot' ] || fail 'camera still action ID is incorrect'
[ "$(jsonfilter -i "$camera_manifest" -e '@.actions[0].class')" = 'ACTION' ] || fail 'camera still action lost its ACTION classification'
[ "$(jsonfilter -i "$camera_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'camera still action execution mode is incorrect'
[ "$(jsonfilter -i "$camera_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'camera still action is not explicitly enabled'
[ "$(jsonfilter -i "$camera_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'camera streaming was unexpectedly enabled'
[ -x /usr/bin/fswebcam ] || fail 'the reviewed fswebcam executable is unavailable'
[ -x /usr/bin/v4l2-ctl ] || fail 'the reviewed v4l2-ctl executable is unavailable'
[ "$(uci -q get mjpg-streamer.core.enabled)" = '0' ] || fail 'mjpg-streamer is not explicitly UCI-disabled'
[ "$(uci -q get motion.general.enabled)" = '0' ] || fail 'Motion is not explicitly UCI-disabled'
if /etc/init.d/mjpg-streamer enabled >/dev/null 2>&1 || /etc/init.d/motion enabled >/dev/null 2>&1; then fail 'a camera service is enabled at boot'; fi
if pidof fswebcam mjpg_streamer motion v4l2rtspserver >/dev/null 2>&1; then fail 'a camera client or service was active before hardware-gate verification'; fi
grep -Fq '"cgi-io": [ "exec", "download" ]' /usr/share/rpcd/acl.d/ddk-field-console.json || fail 'authenticated artifact download permission is missing'
grep -Fq '"/tmp/ddk/jobs/job-[0-9]*-[0-9]*/snapshot.jpg": [ "read" ]' /usr/share/rpcd/acl.d/ddk-field-console.json || fail 'camera artifact path ACL is missing or too broad'
pass 'reviewed camera manifest, installed tools, disabled services, and artifact ACL'

if /usr/libexec/ddk-console job start 'camera.still_snapshot;touch' 2>/dev/null | json_ok; then
	fail 'malformed camera action ID was accepted'
fi
if /usr/libexec/ddk-console job start camera.still_snapshot /dev/video0 2>/dev/null | json_ok; then
	fail 'a browser-supplied camera device was accepted'
fi

camera_capabilities="$(/usr/libexec/ddk-console capabilities)"
camera_ready="$(printf '%s' "$camera_capabilities" | jsonfilter -e '@.data[@.id="camera"].hardware.present')"
camera_state="$(printf '%s' "$camera_capabilities" | jsonfilter -e '@.data[@.id="camera"].state')"
[ "$(printf '%s' "$camera_capabilities" | jsonfilter -e '@.data[@.id="camera"].console_enabled')" = 'true' ] || fail 'camera console module is not enabled'
if [ "$camera_ready" = 'true' ]; then
	[ "$camera_state" = 'READY' ] || fail "reviewed UVC hardware has inconsistent capability state: $camera_state"
	warn 'reviewed UVC camera hardware is attached; capture requires explicit privacy confirmation in the UI'
else
	[ "$camera_state" = 'HARDWARE REQUIRED' ] || fail "absent/unready UVC camera has incorrect capability state: $camera_state"
	camera_jobs_before="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	camera_rejection="$(/usr/libexec/ddk-console job start camera.still_snapshot 2>/dev/null || true)"
	[ "$(printf '%s' "$camera_rejection" | jsonfilter -e '@.ok')" = 'false' ] || fail 'hardware-gated camera start was not rejected'
	printf '%s' "$camera_rejection" | jsonfilter -e '@.message' | grep -Fq 'Reviewed UVC camera hardware is not ready' || fail 'camera hardware rejection message is missing'
	camera_jobs_after="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	[ "$camera_jobs_before" = "$camera_jobs_after" ] || fail 'rejected camera start created a transient job'
	if pidof fswebcam mjpg_streamer motion v4l2rtspserver >/dev/null 2>&1; then fail 'camera hardware rejection started a process'; fi

	camera_worker_probe_id="job-$(date +%s)-$$"
	camera_worker_probe_dir="/tmp/ddk/jobs/$camera_worker_probe_id"
	[ ! -e "$camera_worker_probe_dir" ] || fail 'generated camera worker-probe ID collided'
	mkdir "$camera_worker_probe_dir"
	chmod 700 "$camera_worker_probe_dir"
	printf '%s\n' queued > "$camera_worker_probe_dir/status"
	printf '%s\n' '{}' > "$camera_worker_probe_dir/metadata.json"
	: > "$camera_worker_probe_dir/stdout"
	: > "$camera_worker_probe_dir/stderr"
	camera_worker_result=0
	/usr/libexec/ddk-job-worker "$camera_worker_probe_id" camera_snapshot >/dev/null 2>&1 || camera_worker_result=$?
	camera_worker_status="$(cat "$camera_worker_probe_dir/status" 2>/dev/null || true)"
	camera_worker_error="$(cat "$camera_worker_probe_dir/stderr" 2>/dev/null || true)"
	rm -f "$camera_worker_probe_dir/pid" "$camera_worker_probe_dir/status" "$camera_worker_probe_dir/metadata.json" \
		"$camera_worker_probe_dir/stdout" "$camera_worker_probe_dir/stderr" "$camera_worker_probe_dir/camera.info" \
		"$camera_worker_probe_dir/camera.stderr" "$camera_worker_probe_dir/snapshot.jpg" "$camera_worker_probe_dir/snapshot.jpg.next"
	rmdir "$camera_worker_probe_dir"
	[ "$camera_worker_result" -eq 65 ] || fail "independent camera worker gate returned $camera_worker_result instead of 65"
	[ "$camera_worker_status" = 'failed' ] || fail "independent camera worker gate ended in state: $camera_worker_status"
	printf '%s' "$camera_worker_error" | grep -Fq 'Exactly one reviewed USB UVC camera is required.' || fail 'independent camera worker rejection evidence is missing'
	if pidof fswebcam mjpg_streamer motion v4l2rtspserver >/dev/null 2>&1; then fail 'independent camera rejection started a process'; fi
	if find /tmp/ddk/jobs -maxdepth 2 -type f -name 'snapshot.jpg*' | grep -q .; then fail 'camera no-device verification left an image artifact'; fi
	pass 'camera backend/worker hardware gates and no-device refusal path'
fi

gps_manifest=/usr/share/ddk-field-console/tools/gps-gnss.json
[ "$(jsonfilter -i "$gps_manifest" -e '@.enabled')" = 'true' ] || fail 'GPS/GNSS module is not enabled'
[ "$(jsonfilter -i "$gps_manifest" -e '@.actions[0].id')" = 'gps.snapshot' ] || fail 'GPS/GNSS snapshot action ID is incorrect'
[ "$(jsonfilter -i "$gps_manifest" -e '@.actions[0].class')" = 'ACTION' ] || fail 'GPS/GNSS snapshot lost its ACTION classification'
[ "$(jsonfilter -i "$gps_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'GPS/GNSS snapshot execution mode is incorrect'
[ "$(jsonfilter -i "$gps_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'GPS/GNSS snapshot is not explicitly enabled'
[ "$(jsonfilter -i "$gps_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'GPS/GNSS NTRIP was unexpectedly enabled'
[ -x /usr/bin/gpsdecode ] || fail 'the reviewed gpsdecode executable is unavailable'
[ "$(uci -q get gpsd.core.enabled)" = '0' ] || fail 'the existing gpsd configuration is not disabled'
if pidof gpsd >/dev/null 2>&1; then fail 'gpsd was active before GPS/GNSS hardware-gate verification'; fi
if netstat -lntup 2>/dev/null | grep -Eq '(^|[.:])2947[[:space:]]'; then fail 'the gpsd listener port was active before verification'; fi
pass 'reviewed GPS/GNSS manifest, decoder, and inactive gpsd boundary'

if /usr/libexec/ddk-console job start 'gps.snapshot;touch' 2>/dev/null | json_ok; then
	fail 'malformed GPS/GNSS action ID was accepted'
fi
if /usr/libexec/ddk-console job start gps.snapshot /dev/ttyACM0 2>/dev/null | json_ok; then
	fail 'a browser-supplied GPS/GNSS device was accepted'
fi

gps_status="$(/usr/libexec/ddk-console status)"
gps_capabilities="$(/usr/libexec/ddk-console capabilities)"
gps_ready="$(printf '%s' "$gps_status" | jsonfilter -e '@.data.hardware.gps.ready')"
gps_hardware_present="$(printf '%s' "$gps_status" | jsonfilter -e '@.data.hardware.gps.hardware_present')"
gps_state="$(printf '%s' "$gps_capabilities" | jsonfilter -e '@.data[@.id="gps-gnss"].state')"
gps_action_ready="$(printf '%s' "$gps_capabilities" | jsonfilter -e '@.data[@.id="gps-gnss"].action_ready')"
[ "$(printf '%s' "$gps_capabilities" | jsonfilter -e '@.data[@.id="gps-gnss"].console_enabled')" = 'true' ] || fail 'GPS/GNSS console module is not enabled'
if [ "$gps_ready" = 'true' ]; then
	[ "$gps_hardware_present" = 'true' ] || fail 'ready GPS/GNSS receiver is not marked present'
	[ "$gps_state" = 'READY' ] || fail "ready GPS/GNSS receiver has inconsistent capability state: $gps_state"
	[ "$gps_action_ready" = 'true' ] || fail 'ready GPS/GNSS receiver did not enable the reviewed action'
	warn 'reviewed USB GNSS hardware is attached; live position capture requires explicit privacy confirmation in the UI'
else
	[ "$gps_hardware_present" = 'false' ] || [ "$gps_state" = 'NOT CONFIGURED' ] || fail "present but unready GPS/GNSS receiver has incorrect state: $gps_state"
	if [ "$gps_hardware_present" = 'false' ]; then [ "$gps_state" = 'HARDWARE REQUIRED' ] || fail "absent GPS/GNSS receiver has incorrect state: $gps_state"; fi
	[ "$gps_action_ready" = 'false' ] || fail 'unready GPS/GNSS action was exposed as ready'
	gps_jobs_before="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	gps_rejection="$(/usr/libexec/ddk-console job start gps.snapshot 2>/dev/null || true)"
	[ "$(printf '%s' "$gps_rejection" | jsonfilter -e '@.ok')" = 'false' ] || fail 'hardware-gated GPS/GNSS start was not rejected'
	printf '%s' "$gps_rejection" | jsonfilter -e '@.message' | grep -Fq 'Reviewed USB GNSS hardware is not ready' || fail 'GPS/GNSS hardware rejection message is missing'
	gps_jobs_after="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	[ "$gps_jobs_before" = "$gps_jobs_after" ] || fail 'rejected GPS/GNSS start created a transient job'

	gps_worker_probe_id="job-$(date +%s)-$$"
	gps_worker_probe_dir="/tmp/ddk/jobs/$gps_worker_probe_id"
	[ ! -e "$gps_worker_probe_dir" ] || fail 'generated GPS/GNSS worker-probe ID collided'
	mkdir "$gps_worker_probe_dir"
	chmod 700 "$gps_worker_probe_dir"
	printf '%s\n' queued > "$gps_worker_probe_dir/status"
	printf '%s\n' '{}' > "$gps_worker_probe_dir/metadata.json"
	: > "$gps_worker_probe_dir/stdout"
	: > "$gps_worker_probe_dir/stderr"
	gps_worker_result=0
	/usr/libexec/ddk-job-worker "$gps_worker_probe_id" gps_snapshot >/dev/null 2>&1 || gps_worker_result=$?
	gps_worker_status="$(cat "$gps_worker_probe_dir/status" 2>/dev/null || true)"
	gps_worker_error="$(cat "$gps_worker_probe_dir/stderr" 2>/dev/null || true)"
	rm -f "$gps_worker_probe_dir/pid" "$gps_worker_probe_dir/status" "$gps_worker_probe_dir/metadata.json" \
		"$gps_worker_probe_dir/stdout" "$gps_worker_probe_dir/stderr" "$gps_worker_probe_dir/gnss.raw" \
		"$gps_worker_probe_dir/gnss.decoded" "$gps_worker_probe_dir/gnss.stderr"
	rmdir "$gps_worker_probe_dir"
	[ "$gps_worker_result" -eq 65 ] || fail "independent GPS/GNSS worker gate returned $gps_worker_result instead of 65"
	[ "$gps_worker_status" = 'failed' ] || fail "independent GPS/GNSS worker gate ended in state: $gps_worker_status"
	printf '%s' "$gps_worker_error" | grep -Fq 'Exactly one reviewed USB GNSS receiver is required.' || fail 'independent GPS/GNSS worker rejection evidence is missing'
	if pidof gpsd gpsdecode >/dev/null 2>&1; then fail 'GPS/GNSS hardware rejection started or left a process'; fi
	if find /tmp/ddk/jobs -maxdepth 2 -type f \( -name 'gnss.raw' -o -name 'gnss.decoded' \) | grep -q .; then fail 'GPS/GNSS no-device verification left raw location data'; fi
	pass 'GPS/GNSS backend/worker gates, privacy cleanup, and no-device refusal path'
fi

can_manifest=/usr/share/ddk-field-console/tools/can.json
[ "$(jsonfilter -i "$can_manifest" -e '@.enabled')" = 'true' ] || fail 'CAN module is not enabled'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[0].id')" = 'can.capture' ] || fail 'passive CAN action ID is incorrect'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[0].class')" = 'ACTION' ] || fail 'passive CAN capture lost its ACTION classification'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[0].execution')" = 'job' ] || fail 'passive CAN capture execution mode is incorrect'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[0].enabled')" = 'true' ] || fail 'passive CAN capture is not explicitly enabled'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[1].class')" = 'DISRUPTIVE' ] || fail 'CAN transmit placeholder lost its DISRUPTIVE classification'
[ "$(jsonfilter -i "$can_manifest" -e '@.actions[1].enabled')" = 'false' ] || fail 'CAN transmit was unexpectedly enabled'
opkg status canutils 2>/dev/null | grep -Fq 'Status: install user installed' || fail 'the existing canutils package record is unavailable'
pass 'reviewed passive CAN manifest and installed package record'

if /usr/libexec/ddk-console job start 'can.capture;touch' 2>/dev/null | json_ok; then
	fail 'malformed CAN action ID was accepted'
fi
if /usr/libexec/ddk-console job start can.capture can0 2>/dev/null | json_ok; then
	fail 'a browser-supplied CAN interface was accepted'
fi

can_status="$(/usr/libexec/ddk-console status)"
can_capabilities="$(/usr/libexec/ddk-console capabilities)"
can_ready="$(printf '%s' "$can_status" | jsonfilter -e '@.data.hardware.can.ready')"
can_hardware_present="$(printf '%s' "$can_status" | jsonfilter -e '@.data.hardware.can.hardware_present')"
can_binary_present="$(printf '%s' "$can_status" | jsonfilter -e '@.data.hardware.can.capture_binary_present')"
can_reason="$(printf '%s' "$can_status" | jsonfilter -e '@.data.hardware.can.reason')"
can_state="$(printf '%s' "$can_capabilities" | jsonfilter -e '@.data[@.id="can"].state')"
can_action_ready="$(printf '%s' "$can_capabilities" | jsonfilter -e '@.data[@.id="can"].action_ready')"
[ "$(printf '%s' "$can_capabilities" | jsonfilter -e '@.data[@.id="can"].console_enabled')" = 'true' ] || fail 'CAN console module is not enabled'
if [ "$can_ready" = 'true' ]; then
	[ "$can_hardware_present" = 'true' ] || fail 'ready CAN interface is not marked present'
	[ "$can_binary_present" = 'true' ] || fail 'ready CAN capture lacks candump'
	[ "$can_state" = 'READY' ] || fail "ready CAN interface has inconsistent capability state: $can_state"
	[ "$can_action_ready" = 'true' ] || fail 'ready CAN interface did not enable the reviewed action'
	warn 'one up physical CAN interface and candump are ready; live frame capture requires explicit authorization in the UI'
else
	[ "$can_action_ready" = 'false' ] || fail 'unready CAN action was exposed as ready'
	if [ "$can_hardware_present" = 'false' ]; then
		[ "$can_state" = 'HARDWARE REQUIRED' ] || fail "absent CAN interface has incorrect state: $can_state"
	else
		[ "$can_state" = 'NOT CONFIGURED' ] || fail "present but unready CAN interface has incorrect state: $can_state"
	fi
	if [ "$can_binary_present" = 'false' ]; then
		printf '%s' "$can_reason" | grep -Fq 'CANDUMP EXECUTABLE UNAVAILABLE' || fail 'missing candump is not visible in CAN readiness state'
	fi
	can_jobs_before="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	can_rejection="$(/usr/libexec/ddk-console job start can.capture 2>/dev/null || true)"
	[ "$(printf '%s' "$can_rejection" | jsonfilter -e '@.ok')" = 'false' ] || fail 'unready CAN capture was not rejected'
	printf '%s' "$can_rejection" | jsonfilter -e '@.message' | grep -Fq 'Passive CAN capture is not ready' || fail 'CAN readiness rejection message is missing'
	can_jobs_after="$(find /tmp/ddk/jobs -maxdepth 1 -type d -name 'job-*' 2>/dev/null | wc -l)"
	[ "$can_jobs_before" = "$can_jobs_after" ] || fail 'rejected CAN capture created a transient job'

	can_worker_probe_id="job-$(date +%s)-$$"
	can_worker_probe_dir="/tmp/ddk/jobs/$can_worker_probe_id"
	[ ! -e "$can_worker_probe_dir" ] || fail 'generated CAN worker-probe ID collided'
	mkdir "$can_worker_probe_dir"
	chmod 700 "$can_worker_probe_dir"
	printf '%s\n' queued > "$can_worker_probe_dir/status"
	printf '%s\n' '{}' > "$can_worker_probe_dir/metadata.json"
	: > "$can_worker_probe_dir/stdout"
	: > "$can_worker_probe_dir/stderr"
	can_worker_result=0
	/usr/libexec/ddk-job-worker "$can_worker_probe_id" can_capture >/dev/null 2>&1 || can_worker_result=$?
	can_worker_status="$(cat "$can_worker_probe_dir/status" 2>/dev/null || true)"
	can_worker_error="$(cat "$can_worker_probe_dir/stderr" 2>/dev/null || true)"
	rm -f "$can_worker_probe_dir/pid" "$can_worker_probe_dir/status" "$can_worker_probe_dir/metadata.json" \
		"$can_worker_probe_dir/stdout" "$can_worker_probe_dir/stderr" "$can_worker_probe_dir/can.frames" "$can_worker_probe_dir/can.stderr"
	rmdir "$can_worker_probe_dir"
	[ "$can_worker_result" -eq 65 ] || fail "independent CAN worker gate returned $can_worker_result instead of 65"
	[ "$can_worker_status" = 'failed' ] || fail "independent CAN worker gate ended in state: $can_worker_status"
	if [ "$can_hardware_present" = 'false' ]; then
		printf '%s' "$can_worker_error" | grep -Fq 'Exactly one reviewed physical CAN interface named canN is required.' || fail 'independent CAN hardware rejection evidence is missing'
	elif [ "$can_binary_present" = 'false' ]; then
		printf '%s' "$can_worker_error" | grep -Fq 'candump is unavailable at the reviewed path' || fail 'independent CAN executable rejection evidence is missing'
	fi
	if pidof candump cansend cangen canplayer >/dev/null 2>&1; then fail 'CAN rejection started or left a CAN utility process'; fi
	if find /tmp/ddk/jobs -maxdepth 2 -type f -name 'can.frames' | grep -q .; then fail 'CAN no-device verification left captured frames'; fi
	pass 'CAN backend/worker gates, missing-runtime visibility, and no-device refusal path'
fi

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
report_view="$(/usr/libexec/ddk-console report view "$report_id")"
printf '%s' "$report_view" | json_ok || fail 'authenticated report view failed'
report_content="$(printf '%s' "$report_view" | jsonfilter -e '@.data.content')"
if printf '%s' "$report_content" | grep -Eq 'Latitude:|Longitude:|gnss\.raw|gnss\.decoded|Serial identifier:|ANDROID USB IDENTITY|APPLE MOBILE USB IDENTITY|FIRMWARE PROGRAMMER USB IDENTITY'; then fail 'system report contains prohibited precise-location or customer-device identity data'; fi
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
	1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6 /etc/config/rpcd \
	500d071555f688b493b2937f8ef1edf7f56dfddd3888aa584e8b572d5db3f2ad /etc/config/rtl_tcp \
	00f24dd633bac043f1063b36ae60bef53659c52237e3cfefc27a611b4806944f /etc/config/mjpg-streamer \
	574743e3859793b10328389d2f1a37e4dce88f0e753029a102a43d073b6ca22f /etc/config/motion \
	e500321d73a7329e11423769f37ea1bb7c11d2dc20f10a3cc126c67b9a7bf078 /etc/config/gpsd |
	sha256sum -c - >/dev/null || fail 'a protected configuration hash changed'
pass 'network, firewall, wireless, uhttpd, rpcd, radio, camera, and gpsd configurations are untouched'

if netstat -lntup 2>/dev/null | grep -q 'ddk'; then fail 'a DDK listener exists'; fi
# BusyBox on this target has no standalone pgrep.
# shellcheck disable=SC2009
if ps w | grep '[d]dk-job-worker' >/dev/null 2>&1; then fail 'a DDK job worker is unexpectedly active'; fi
if pidof nmap tcpdump uqmi qmicli qmi-proxy ModemManager rtl_433 rtl_tcp rtl_fm rtl_power rtl_sdr rtl_test rtl_adsb rtl_ais readsb dump1090 fswebcam mjpg_streamer motion v4l2rtspserver gpsd gpsdecode candump cansend cangen canplayer adb usbmuxd idevice_id ideviceinfo idevicepair irecovery idevicerestore openocd avrdude dfu-util dfu-programmer flashrom stm32flash bossac lpc21isp ftdi_eeprom >/dev/null 2>&1; then fail 'a bounded-operation or device-management client is unexpectedly active'; fi
pass 'no DDK listener or idle operation worker exists'

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
