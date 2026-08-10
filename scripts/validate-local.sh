#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
	printf 'LOCAL VALIDATION FAILED: %s\n' "$1" >&2
	exit 1
}

git diff --check
[[ "$(tr -d '\r\n' < files/usr/share/ddk-field-console/VERSION)" == '2.1.0' ]] || fail 'source version is not 2.1.0'
rg -F "X750 / v2.1.0" files/www/luci-static/resources/ddk/console-app.js >/dev/null || fail 'frontend appliance version is not 2.1.0'
rg -F "Field Console version 2.1.0" scripts/router-verify.sh >/dev/null || fail 'router verifier version is not 2.1.0'
bash -n deploy.sh verify.sh rollback.sh configure-swap-autostart.sh rollback-swap-autostart.sh post-reboot-verify.sh scripts/verify-browser-authenticated.sh
sh -n scripts/router-install.sh scripts/router-verify.sh scripts/router-rollback.sh \
	scripts/router-configure-swap-autostart.sh scripts/router-rollback-swap-autostart.sh \
	scripts/router-post-reboot-verify.sh files/usr/libexec/ddk-job-worker files/usr/libexec/ddk-apple-worker
node --check scripts/verify-browser.mjs >/dev/null

brand_root=files/www/luci-static/resources/ddk/brand
for asset in dropkick-logo.png overview.webp tools.webp packages.webp jobs.webp settings.webp; do
	[[ -f "$brand_root/$asset" ]] || fail "brand asset is missing: $asset"
done
[[ "$(find "$brand_root" -maxdepth 1 -type f | wc -l)" -eq 6 ]] || fail 'unexpected file exists in the brand asset directory'
[[ "$(stat -c %s "$brand_root/dropkick-logo.png")" -le 10240 ]] || fail 'optimized logo exceeds 10 KiB'
while IFS= read -r scene; do
	[[ "$(stat -c %s "$scene")" -le 45056 ]] || fail "optimized scene exceeds 44 KiB: $scene"
done < <(find "$brand_root" -maxdepth 1 -type f -name '*.webp' | sort)
[[ "$(du -cb "$brand_root"/* | tail -n 1 | awk '{print $1}')" -le 174080 ]] || fail 'brand asset set exceeds 170 KiB'
if rg -ni 'https?://|//[^/]' files/www/luci-static/resources/ddk/console.css files/www/luci-static/resources/ddk/console-app.js files/usr/lib/lua/luci/view/ddk/shell.htm; then
	fail 'console presentation contains a remote asset or request reference'
fi

shortcut_file=files/www/ddk/gl_home.html
[[ -f "$shortcut_file" ]] || fail 'the /ddk shortcut page is missing'
rg -F 'content="0;url=/cgi-bin/luci/admin/ddk/overview"' "$shortcut_file" >/dev/null || fail 'the /ddk shortcut target is incorrect'
rg -F 'href="/cgi-bin/luci/admin/ddk/overview"' "$shortcut_file" >/dev/null || fail 'the /ddk fallback target is incorrect'
if rg -ni 'https?://|<form|<script|fetch\(|xmlhttprequest|/cgi-bin/cgi-exec' "$shortcut_file"; then
	fail 'the /ddk shortcut contains an external, executable, or backend reference'
fi

while IFS= read -r file; do
	node --check "$file" >/dev/null
done < <(find files/www/luci-static/resources -type f -name '*.js' | sort)

while IFS= read -r file; do
	jq -e . "$file" >/dev/null
done < <(find files -type f -name '*.json' | sort)

if rg -n 'opkg[[:space:]]+upgrade|--force-depends|--force-overwrite' files scripts/router-install.sh scripts/router-verify.sh scripts/router-rollback.sh deploy.sh verify.sh rollback.sh; then
	fail 'forbidden package operation found'
fi

if rg -n 'uci[[:space:]]+(-q[[:space:]]+)?(set|add|delete|commit|revert)|firewall[.-](restart|reload)|/etc/init.d/(network|firewall|tailscale)[[:space:]]+(restart|reload|stop|start)|(^|[;&|])[[:space:]]*(cp|mv|sed[^[:space:]]*[[:space:]]+-i)[^\n]*/etc/config/(network|firewall|wireless)' \
	files scripts/router-install.sh scripts/router-verify.sh scripts/router-rollback.sh \
	scripts/router-configure-swap-autostart.sh scripts/router-rollback-swap-autostart.sh \
	scripts/router-post-reboot-verify.sh deploy.sh verify.sh rollback.sh \
	configure-swap-autostart.sh rollback-swap-autostart.sh post-reboot-verify.sh |
	grep -v '^scripts/router-configure-swap-autostart\.sh:'; then
	fail 'production configuration mutation found'
fi

swap_mutation_count="$(rg -n 'uci[[:space:]]+(-q[[:space:]]+)?(set|add|delete|commit|revert)' scripts/router-configure-swap-autostart.sh | wc -l)"
[[ "$swap_mutation_count" -eq 6 ]] || fail "unexpected number of approved fstab mutations: $swap_mutation_count"
for approved_mutation in \
	"uci -q revert fstab.ddk_install_swap || true" \
	"uci -q delete fstab.ddk_install_swap || true" \
	"uci set fstab.ddk_install_swap='swap'" \
	"uci set fstab.ddk_install_swap.device='/overlay/ddk-install.swap'" \
	"uci set fstab.ddk_install_swap.enabled='1'" \
	"uci commit fstab"
do
	rg -F "$approved_mutation" scripts/router-configure-swap-autostart.sh >/dev/null || fail "approved swap mutation is missing: $approved_mutation"
done
if rg -n 'swapoff|mkswap|block[[:space:]]+mount|/etc/init\.d/|reboot|poweroff|uci[[:space:]]+(-q[[:space:]]+)?(set|add|delete|commit|revert)[^\n]*(network|firewall|wireless|uhttpd|rpcd|tailscale)' \
	scripts/router-configure-swap-autostart.sh scripts/router-rollback-swap-autostart.sh configure-swap-autostart.sh rollback-swap-autostart.sh; then
	fail 'swap-autostart tooling contains a prohibited operation'
fi

if rg -n 'cmd=[^[:space:]]|[?&]cmd=|action_id=.*shell|kill[[:space:]]+\$[A-Za-z_][A-Za-z0-9_]*' files/www files/usr/libexec; then
	fail 'generic browser command or PID-kill pattern found'
fi

while IFS= read -r action; do
	action_class="$(jq -r --arg id "$action" '.actions[] | select(.id == $id) | .class' files/usr/share/ddk-field-console/tools/*.json | head -n 1)"
	case "$action_class" in
		INFO) ;;
		ACTION)
			rg -Fx "$action" scripts/enabled-action-ids.txt >/dev/null || fail "enabled ACTION was not explicitly reviewed: $action"
			;;
		SECURITY)
			rg -Fx "$action" scripts/enabled-security-actions.txt >/dev/null || fail "enabled SECURITY action was not explicitly reviewed: $action"
			;;
		DISRUPTIVE)
			rg -Fx "$action" scripts/enabled-disruptive-actions.txt >/dev/null || fail "enabled DISRUPTIVE action was not explicitly reviewed: $action"
			;;
		*) fail "enabled action has an unknown class: $action ($action_class)" ;;
	esac
	disable_count="$(jq -r --arg id "$action" '[.actions[] | select(.id == $id and .enabled == true)] | length' files/usr/share/ddk-field-console/tools/*.json | awk '{sum += $1} END{print sum+0}')"
	[[ "$disable_count" -gt 0 ]] || fail "enabled module action is not explicitly enabled: $action"
	rg -F "[\"$action\"]" files/usr/libexec/ddk-console >/dev/null || fail "enabled action missing from backend allowlist: $action"
done < <(jq -r 'select(.enabled == true) | .actions[] | select(.enabled == true) | .id' files/usr/share/ddk-field-console/tools/*.json | sort -u)

while IFS= read -r action || [[ -n "$action" ]]; do
	[[ -z "$action" || "$action" == \#* ]] && continue
	[[ "$action" =~ ^[a-z0-9][a-z0-9._-]+$ ]] || fail "invalid reviewed SECURITY action ID: $action"
	enabled_count="$(jq -r --arg id "$action" '[.actions[] | select(.id == $id and .class == "SECURITY" and .enabled == true)] | length' files/usr/share/ddk-field-console/tools/*.json | awk '{sum += $1} END{print sum+0}')"
	[[ "$enabled_count" -eq 1 ]] || fail "reviewed SECURITY action is missing or duplicated: $action"
done < scripts/enabled-security-actions.txt

while IFS= read -r action || [[ -n "$action" ]]; do
	[[ -z "$action" || "$action" == \#* ]] && continue
	[[ "$action" =~ ^[a-z0-9][a-z0-9._-]+$ ]] || fail "invalid reviewed ACTION ID: $action"
	enabled_count="$(jq -r --arg id "$action" '[.actions[] | select(.id == $id and .class == "ACTION" and .enabled == true)] | length' files/usr/share/ddk-field-console/tools/*.json | awk '{sum += $1} END{print sum+0}')"
	[[ "$enabled_count" -eq 1 ]] || fail "reviewed ACTION is missing or duplicated: $action"
done < scripts/enabled-action-ids.txt

while IFS= read -r action || [[ -n "$action" ]]; do
	[[ -z "$action" || "$action" == \#* ]] && continue
	[[ "$action" =~ ^[a-z0-9][a-z0-9._-]+$ ]] || fail "invalid reviewed DISRUPTIVE action ID: $action"
	enabled_count="$(jq -r --arg id "$action" '[.actions[] | select(.id == $id and .class == "DISRUPTIVE" and .enabled == true)] | length' files/usr/share/ddk-field-console/tools/*.json | awk '{sum += $1} END{print sum+0}')"
	[[ "$enabled_count" -eq 1 ]] || fail "reviewed DISRUPTIVE action is missing or duplicated: $action"
done < scripts/enabled-disruptive-actions.txt

identity_module=files/usr/share/ddk-field-console/usb-identity.lua
[[ -f "$identity_module" ]] || fail 'USB identity classifier is missing'
for identity_guard in \
	'/sys/bus/usb/devices' \
	'ff:42:01' \
	'ff:42:03' \
	'06:01:01' \
	'05ac' \
	'1366' \
	'result.inspected_count >= 64' \
	'#device.interfaces >= 16' \
	'root:find("..", 1, true)'
do
	rg -F -- "$identity_guard" "$identity_module" >/dev/null || fail "USB identity guard is missing: $identity_guard"
done

for identity_manifest in firmware-programming; do
	manifest="files/usr/share/ddk-field-console/tools/$identity_manifest.json"
	[[ "$(jq -r '.enabled' "$manifest")" == true ]] || fail "identity module is not enabled: $identity_manifest"
	[[ "$(jq -r '.no_device_state' "$manifest")" == 'READY / NO DEVICE' ]] || fail "identity no-device state is unsafe: $identity_manifest"
	[[ "$(jq '[.actions[] | select(.class == "INFO" and .enabled == true)] | length' "$manifest")" -eq 2 ]] || fail "identity INFO action count is incorrect: $identity_manifest"
	[[ "$(jq '[.actions[] | select(.class == "DISRUPTIVE")] | length' "$manifest")" -eq 1 ]] || fail "identity module lost its declared device-changing action: $identity_manifest"
done
apple_manifest=files/usr/share/ddk-field-console/tools/apple-repair.json
[[ "$(jq -r '.enabled' "$apple_manifest")" == true ]] || fail 'Apple module is not enabled'
[[ "$(jq -r '.no_device_state' "$apple_manifest")" == 'READY / NO DEVICE' ]] || fail 'Apple no-device state is unsafe'
[[ "$(jq '[.actions[] | select(.class == "INFO" and .enabled == true)] | length' "$apple_manifest")" -eq 2 ]] || fail 'Apple identity/guide action count is incorrect'
[[ "$(jq '[.actions[] | select(.class == "ACTION" and .execution == "job" and .parameter_schema == "operator-v1" and .enabled == true)] | length' "$apple_manifest")" -eq 2 ]] || fail 'Apple normal-mode ACTION contracts are incomplete'
[[ "$(jq '[.actions[] | select(.class == "DISRUPTIVE" and .execution == "job" and .parameter_schema == "operator-v1" and .enabled == true)] | length' "$apple_manifest")" -eq 3 ]] || fail 'Apple device-changing Operator Mode contracts are incomplete'
android_manifest=files/usr/share/ddk-field-console/tools/android-repair.json
[[ "$(jq -r '.enabled' "$android_manifest")" == true ]] || fail 'Android module is not enabled'
[[ "$(jq -r '.no_device_state' "$android_manifest")" == 'READY / NO DEVICE' ]] || fail 'Android no-device state is unsafe'
[[ "$(jq '[.actions[] | select(.class == "INFO" and .enabled == true)] | length' "$android_manifest")" -eq 2 ]] || fail 'Android identity/guide action count is incorrect'
[[ "$(jq '[.actions[] | select(.id == "android.adb_diagnostics" and .class == "ACTION" and .execution == "job" and .parameter_schema == "operator-v1" and .enabled == true)] | length' "$android_manifest")" -eq 1 ]] || fail 'Android diagnostics Operator Mode action contract is missing'
[[ "$(jq '[.actions[] | select(.id == "android.adb_manage" and .class == "DISRUPTIVE" and .execution == "job" and .parameter_schema == "operator-v1" and .enabled == true)] | length' "$android_manifest")" -eq 1 ]] || fail 'Android management Operator Mode action contract is missing'

for identity_action in \
	android.identify android.operator_guide \
	apple.identify apple.operator_guide \
	firmware.identify firmware.operator_guide
do
	rg -F "[\"$identity_action\"]" files/usr/libexec/ddk-console >/dev/null || fail "identity action is missing from the exact backend allowlist: $identity_action"
done

for identity_guard in \
	'Policy: sysfs metadata only' \
	'not written to jobs, reports, logs, or persistent storage' \
	'The browser does not execute any displayed command' \
	'No command above was run by this request.'
do
	rg -F -- "$identity_guard" files/usr/libexec/ddk-console >/dev/null || fail "identity privacy/handoff guard is missing: $identity_guard"
done

capture_worker=files/usr/libexec/ddk-job-worker
operator_module=files/usr/share/ddk-field-console/operator-actions.lua
apple_operator_module=files/usr/share/ddk-field-console/operator-apple.lua
[[ -f "$operator_module" ]] || fail 'Operator Mode action module is missing'
[[ -f "$apple_operator_module" ]] || fail 'Apple Operator Mode action module is missing'
for operator_guard in \
	'MAX_TARGETS = 64' \
	'Target must be an IPv4/IPv6 address, CIDR, hostname, or validated IPv4 octet range' \
	'Unknown Nmap option:' \
	'Exclude targets must use the same IP family as the Nmap job' \
	'Capture filter exceeds 1024 bytes or contains control characters' \
	'Unknown tcpdump option:' \
	'Server mode requires an exact currently assigned bind address' \
	'Client-only iperf3 options must remain at their defaults in server mode' \
	'Bind address is not assigned to the selected bind device' \
	'Unknown iperf3 option:' \
	'Unknown rtl_433 option:' \
	'RTL-SDR device is not present in the live reviewed hardware inventory' \
	'Unknown fswebcam option:' \
	'Camera node is not present in the live reviewed UVC inventory' \
	'Unknown serial option:' \
	'Serial device is not present in the live reviewed general-purpose inventory' \
	'Transmit payload exceeds 4096 bytes' \
	'Unknown GPS/GNSS option:' \
	'GNSS device is not present in the live reviewed receiver inventory' \
	'Unknown ADB diagnostics option:' \
	'Unknown ADB management option:' \
	'ADB device is not present in the live reviewed USB transport inventory' \
	'ADB backup requires all apps, shared storage, or at least one package' \
	'cannot contain dot traversal segments' \
	'argv = { "/usr/bin/nmap" }' \
	'local argv = { "/usr/sbin/tcpdump", "-i", normalized.interface }' \
	'local argv = { "/usr/bin/iperf3" }' \
	'local argv = { "/usr/bin/rtl_433", "-c", "/dev/null", "-d", normalized.device }' \
	'local argv = { "/usr/bin/fswebcam", "--quiet", "--device", normalized.device' \
	'local argv = { "/usr/bin/socat", "-T", tostring(normalized.duration) }' \
	'local argv = { "/bin/dd", "if=" .. normalized.device, "bs=256"' \
	'local decode_argv = { "/usr/bin/gpsdecode", "-d" }' \
	'local argv = { "/usr/bin/adb", "-P", "5038", "-s", normalized.device }'
do
	rg -F -- "$operator_guard" "$operator_module" >/dev/null || fail "Operator Mode validator/argv guard is missing: $operator_guard"
done
if rg -n 'io\.popen|os\.execute|loadstring|loadfile|dofile|/bin/sh|sh[[:space:]]+-c' "$operator_module"; then
	fail 'Operator Mode action module can execute commands or load code'
fi
if rg -n 'io\.popen|os\.execute|loadstring|loadfile|dofile|/bin/sh|sh[[:space:]]+-c' "$apple_operator_module"; then
	fail 'Apple Operator Mode action module can execute commands or load code'
fi
for apple_guard in \
	'defaults(schema, options, "Apple diagnostics")' \
	'defaults(schema, options, "Apple management")' \
	'defaults(schema, options, "Apple capture")' \
	'defaults(schema, options, "Apple recovery")' \
	'defaults(schema, options, "Apple restore")' \
	'Selected normal-mode Apple device is not in the reviewed live inventory' \
	'Selected Apple recovery/DFU ECID is not in the reviewed live inventory' \
	'Selected Apple restore target is not in the reviewed live inventory' \
	'@WORK@/restore-cache' \
	'@ARTIFACT@/apple-screenshot.tiff' \
	'"/usr/bin/idevicerestore"' \
	'"/usr/bin/irecovery"' \
	'confirmation = { required = true'
do
	rg -F -- "$apple_guard" "$apple_operator_module" >/dev/null || fail "Apple Operator Mode validator/argv guard is missing: $apple_guard"
done
for structured_action in network.nmap_lan_discovery capture.lan_metadata_snapshot throughput.iperf3 radio.rtl433_snapshot camera.still_snapshot serial.session gps.snapshot android.adb_diagnostics android.adb_manage apple.mobile_diagnostics apple.mobile_capture apple.mobile_manage apple.recovery apple.restore; do
	[[ "$(jq -r --arg id "$structured_action" '.actions[] | select(.id == $id) | .parameter_schema' files/usr/share/ddk-field-console/tools/*.json | head -n 1)" == 'operator-v1' ]] || fail "structured manifest marker is missing: $structured_action"
	rg -F "[\"$structured_action\"]" files/usr/libexec/ddk-console >/dev/null || fail "structured backend mapping is missing: $structured_action"
done
apple_worker=files/usr/libexec/ddk-apple-worker
for apple_worker_guard in \
	'apple_mobile|apple_recovery|apple_restore' \
	'libimobiledevice utilities drifted from the reviewed 1.3.0 contract.' \
	'usbmuxd drifted from the reviewed 1.1.1 contract.' \
	'irecovery drifted from the reviewed 1.0.0 contract.' \
	'idevicerestore drifted from the reviewed 1.0.0 contract.' \
	'A pre-existing usbmuxd process is active' \
	'/usr/sbin/usbmuxd -f -p -l' \
	'The exact selected Apple UDID was not present after fresh usbmuxd discovery.' \
	'The exact selected recovery/DFU ECID was not available to irecovery.' \
	'workspace-restore-cache' \
	'Apple restore stopped before violating the protected 100 MiB extroot reserve.' \
	'Apple screenshot TIFF magic is invalid.' \
	'Apple syslog capture was empty, unsafe, or exceeded 32 MiB.' \
	'Prepared Apple sealed input failed worker-side SHA-256 verification.' \
	'cleanup_usbmuxd' \
	'cleanup_workspace'
do
	rg -F -- "$apple_worker_guard" "$apple_worker" >/dev/null || fail "Apple worker guard is missing: $apple_worker_guard"
done
for backend_guard in \
	'MAX_OPERATOR_ENVELOPE = 24576' \
	'Unknown structured envelope field:' \
	'fs.rename(path, claim_path)' \
	'backend_allows_executable(backend, plan.argv[1])' \
	'Prepared action does not match an exact Operator Mode backend' \
	'argument:find("[%z\r\n]")' \
	'Operator action builder declared an invalid artifact' \
	'(storage == "tmp" and maximum > MAX_TMP_OPERATOR_ARTIFACT)' \
	'Prepared argv contains an invalid artifact placeholder' \
	'Prepared argv contains an invalid extroot artifact placeholder' \
	'Prepared argv contains an invalid workspace placeholder' \
	'Operator action builder declared an invalid isolated workspace' \
	'if extroot_allocated then remove_artifact_tree(job_id) end' \
	'remove_owned_tree(job_dir, job_dir)' \
	'Operator action builder produced invalid private input' \
	'operator_plan.private_input_hex and not write_file' \
	'acquire_lock("resource-adb", probe_owner)' \
	'release_lock("resource-adb", probe_owner)' \
	'acquire_job_locks' \
	'os.time() - (stat.mtime or os.time()) <= 5' \
	'options = operator_plan and operator_plan.options or nil' \
	'argv_preview = operator_plan and operator_plan.argv_preview or nil'
do
	rg -F -- "$backend_guard" files/usr/libexec/ddk-console >/dev/null || fail "structured backend guard is missing: $backend_guard"
done
for upload_guard in \
	'local UPLOAD_PARENT = "/overlay/ddk-field-console"' \
	'MAX_RETAINED_UPLOADS = 10' \
	'Unknown DDK upload kind' \
	'Upload name or extension is not allowed' \
	'Uploaded file is absent, unsafe, or does not match the declared bounded size' \
	'Uploaded Android backup does not have the required ADB backup header' \
	'Unable to close the authenticated upload path after sealing' \
	'capture("/usr/bin/sha256sum " .. sealed, 256, 1800)' \
	'elseif verb == "upload" and arg[2] == "reserve"' \
	'elseif verb == "upload" and arg[2] == "finalize"' \
	'elseif verb == "upload" and arg[2] == "delete"'
do
	rg -F -- "$upload_guard" files/usr/libexec/ddk-console >/dev/null || fail "upload backend guard is missing: $upload_guard"
done
for worker_guard in \
	'operator_nmap' \
	'operator_tcpdump' \
	'operator_iperf3' \
	'operator_rtl433' \
	'operator_camera' \
	'operator_serial' \
	'operator_gps' \
	'operator_adb' \
	'exec "$@"' \
	'release_locks' \
	'Tcpdump rejected the structured BPF capture filter.' \
	'Rejected Nmap XML artifact without the native nmaprun document root.' \
	'Nmap version drifted from the reviewed 7.91 argv contract.' \
	'Tcpdump version drifted from the reviewed 4.9.3 argv contract.' \
	'iperf3 version drifted from the reviewed 3.11 argv contract.' \
	'rtl_433 package version drifted from the reviewed 20.11-2 argv contract.' \
	'fswebcam version drifted from the reviewed 20140113 argv contract.' \
	'socat version drifted from the reviewed 1.7.4.1 serial contract.' \
	'The Quectel EC25 modem ports are reserved' \
	'original tty state restored on completion, failure, or cancellation' \
	'gpsdecode version drifted from the reviewed 3.23.1 contract.' \
	'The Quectel EC25 modem ports are reserved and cannot be opened by GNSS Operator.' \
	'ADB version drifted from the reviewed 1.0.32 contract.' \
	'Prepared ADB argv does not use the isolated exact executable/port/selector prefix.' \
	'Prepared ADB extroot artifact directory is missing or unsafe.' \
	'Prepared ADB artifact is not bound to extroot storage.' \
	'Prepared ADB argv failed independent operation-specific validation.' \
	'Sealed ADB input failed worker-side SHA-256 verification.' \
	'Sealed ADB restore input has an invalid backup header.' \
	'case "$operation" in logcat|bugreport) native_output="$artifact_path" ;; esac' \
	'Temporary ADB server or listener remained after cleanup.' \
	'no listener was left running.'
do
	rg -F -- "$worker_guard" "$capture_worker" >/dev/null || fail "Operator Mode worker guard is missing: $worker_guard"
done
for browser_guard in \
	'function structuredEnvelope(options)' \
	"exec([ 'action', 'describe', actionId ])" \
	"exec([ 'action', 'prepare', actionId, structuredEnvelope" \
	"[ 'job', 'start', prepared.prepared_id ]" \
	'Server-built native invocation' \
	'function applyOperatorConditions(registry)' \
	"field.type === 'integer_list'" \
	"field.type === 'multiline'" \
	'function downloadOperatorArtifact(job, artifact)' \
	"storage === 'extroot' ? '/overlay/ddk-field-console/artifacts/'" \
	"expectedSize > 16777216" \
	"h('form', { method: 'POST', action: config.download" \
	'frame.remove(); }, 2 * 60 * 60 * 1000)' \
	"'android.adb_diagnostics', 'android.adb_manage'" \
	"'[STDERR]\\n' + job.stderr" \
	'function uploadFile(reservation, file, progress)' \
	"exec([ 'upload', 'reserve', kindSelect.value, structuredEnvelope" \
	"exec([ 'upload', 'finalize', reservation.id ])" \
	"exec([ 'upload', 'delete', upload.id ])"
do
	rg -F -- "$browser_guard" files/www/luci-static/resources/ddk/console-app.js >/dev/null || fail "Operator Mode browser guard is missing: $browser_guard"
done
rg -F 'data-upload="/cgi-bin/cgi-upload"' files/usr/lib/lua/luci/view/ddk/shell.htm >/dev/null || fail 'native authenticated upload endpoint is not passed to the browser'
rg -F '"cgi-io": [ "upload" ]' files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail 'authenticated upload transport ACL is missing'
rg -F '"/overlay/ddk-field-console/uploads/upload-[0-9]*-[0-9]*-[0-9]*/payload.bin": [ "write" ]' files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail 'DDK upload write ACL is missing or broader than reviewed'
rg -F '"/usr/libexec/ddk-console upload *": [ "exec" ]' files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail 'DDK upload backend ACL is missing'
for artifact_acl in nmap.nmap nmap.xml nmap.gnmap capture.pcap iperf3.json rtl433.jsonl rtl433.csv rtl433.txt rtl433.cu8 snapshot.jpg snapshot.png serial.bin gnss.raw gnss.decoded; do
	rg -F "/tmp/ddk/jobs/job-[0-9]*-[0-9]*/$artifact_acl" files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail "Operator artifact ACL is missing: $artifact_acl"
done
for artifact_acl in android-logcat.txt android-bugreport.txt android-pull.bin android-backup.ab apple-screenshot.tiff apple-syslog.txt apple-restore.log; do
	rg -F "/overlay/ddk-field-console/artifacts/job-[0-9]*-[0-9]*/$artifact_acl" files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail "Extroot Operator artifact ACL is missing: $artifact_acl"
done

[[ "$(rg -c '/usr/sbin/tcpdump -i br-lan' "$capture_worker")" -eq 1 ]] || fail 'reviewed tcpdump command is missing or duplicated'
for capture_guard in \
	'-p -n -q -e -l -tttt -s 96 -c 128' \
	"'arp or icmp or (ip and udp and (port 67 or port 68))'" \
	'deadline_epoch=$(( $(date +%s) + 20 ))' \
	'/sys/class/net/br-lan/flags' \
	'head -c 65536 "$job_dir/stdout"'
do
	rg -F -- "$capture_guard" "$capture_worker" >/dev/null || fail "capture safety guard is missing: $capture_guard"
done
legacy_capture_section="$(sed -n '/elif \[ "$task" = "tcpdump_lan_metadata" \]/,/elif \[ "$task" = "rtl433_snapshot" \]/p' "$capture_worker")"
if printf '%s\n' "$legacy_capture_section" | rg -n -- '(^|[[:space:]])-(A|X|XX|w|W|C|G)([[:space:]]|$)|-i[[:space:]]+any'; then
	fail 'legacy metadata profile gained a payload dump, PCAP writer, rotation, or all-interface flag'
fi

radio_worker_section="$(sed -n '/elif \[ "$task" = "rtl433_snapshot" \]/,/elif \[ "$task" = "camera_snapshot" \]/p' "$capture_worker")"
radio_command_section="$(printf '%s\n' "$radio_worker_section" | sed -n '/exec \/usr\/bin\/rtl_433/,/-T 20/p')"
[[ "$(printf '%s\n' "$radio_worker_section" | rg -c '/usr/bin/rtl_433 -c /dev/null')" -eq 1 ]] || fail 'reviewed rtl_433 command is missing or duplicated'
for radio_guard in \
	'0bda' \
	'2832' \
	'2838' \
	'case "$rtl_serial"' \
	'ulimit -f 112' \
	'-d ":$rtl_serial" -f 433920000 -s 250000' \
	'-S none -F json -M time:iso -M protocol -T 20' \
	'deadline_epoch=$(( $(date +%s) + 25 ))' \
	'head -c 57344 "$radio_output"' \
	'head -c 65536 "$job_dir/stdout"'
do
	rg -F -- "$radio_guard" "$capture_worker" >/dev/null || fail "RTL-433 safety guard is missing: $radio_guard"
done
if printf '%s\n' "$radio_worker_section" | rg -n -- '/usr/bin/rtl_tcp|/etc/init\.d/rtl_tcp[[:space:]]+(start|enable|restart)' ||
	printf '%s\n' "$radio_command_section" | rg -n -- '(^|[[:space:]])-(a|A|r|w|W|X)([[:space:]]|$)|-F[[:space:]]+(mqtt|influx|syslog)|-S[[:space:]]+(all|known|unknown)'; then
	fail 'RTL-433 worker contains a listener, analyzer, custom/file input, network output, or raw-save option'
fi

camera_worker_section="$(sed -n '/elif \[ "$task" = "camera_snapshot" \]/,/^else$/p' "$capture_worker")"
camera_command_section="$(printf '%s\n' "$camera_worker_section" | sed -n '/exec \/usr\/bin\/fswebcam/,/snapshot_next"/p')"
[[ "$(printf '%s\n' "$camera_worker_section" | rg -c 'exec /usr/bin/fswebcam')" -eq 1 ]] || fail 'reviewed fswebcam command is missing or duplicated'
for camera_guard in \
	'camera_driver" = '\''uvcvideo'\''' \
	'bInterfaceClass' \
	'camera_primary_count" -eq 1' \
	'camera_number="${camera_device#/dev/video}"' \
	'*[!0-9]*) task_fail' \
	'/proc/[0-9]*/fd/*' \
	'timeout 5 /usr/bin/v4l2-ctl --device "$camera_device" --info' \
	'ulimit -f 512' \
	'--quiet --device "$camera_device" --resolution 640x480' \
	'--fps 10 --skip 5 --frames 1 --no-banner --jpeg 85 "$snapshot_next"' \
	'deadline_epoch=$(( $(date +%s) + 20 ))' \
	'snapshot_size" -gt 262144' \
	'snapshot_magic" != '\''ffd8ff'\''' \
	'chmod 600 "$snapshot_path"'
do
	rg -F -- "$camera_guard" "$capture_worker" >/dev/null || fail "camera safety guard is missing: $camera_guard"
done
if printf '%s\n' "$camera_command_section" | rg -n -- '(^|[[:space:]])(-l|--loop|-b|--background|-o|--output|--exec|--save)([[:space:]]|$)' ||
	printf '%s\n' "$camera_worker_section" | rg -n -- '/etc/init\.d/(mjpg-streamer|motion)[[:space:]]+(start|enable|restart)|/usr/bin/(mjpg_streamer|motion|v4l2rtspserver)'; then
	fail 'camera worker contains a loop, background mode, command hook, stream, daemon, or service activation'
fi
rg -F '"cgi-io": [ "exec", "download" ]' files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail 'camera artifact download permission is missing'
rg -F '"/tmp/ddk/jobs/job-[0-9]*-[0-9]*/snapshot.jpg": [ "read" ]' files/usr/share/rpcd/acl.d/ddk-field-console.json >/dev/null || fail 'camera artifact ACL is missing or broader than reviewed'
rg -F "path = '/tmp/ddk/jobs/' + job.id + '/snapshot.jpg'" files/www/luci-static/resources/ddk/console-app.js >/dev/null || fail 'camera client does not derive the fixed artifact path from a validated job ID'

gps_worker_section="$(sed -n '/elif \[ "$task" = "gps_snapshot" \]/,/elif \[ "$task" = "camera_snapshot" \]/p' "$capture_worker")"
[[ "$(printf '%s\n' "$gps_worker_section" | rg -c 'exec /usr/bin/timeout 15 /bin/dd if="\$gnss_device" bs=256 count=128')" -eq 1 ]] || fail 'reviewed receive-only GNSS byte-read command is missing or duplicated'
[[ "$(printf '%s\n' "$gps_worker_section" | rg -c 'exec /usr/bin/timeout 5 /usr/bin/gpsdecode -d -v')" -eq 1 ]] || fail 'reviewed GPS decoder command is missing or duplicated'
for gps_guard in \
	"'2c7c:0125'" \
	'1546:' \
	'cdc_acm|ftdi_sio|cp210x|pl2303|ch341|usbserial' \
	'Exactly one reviewed USB GNSS receiver is required.' \
	'Exactly one serial node from the reviewed USB GNSS receiver is required.' \
	'/proc/[0-9]*/fd/*' \
	'pidof gpsd' \
	'ulimit -f 64' \
	'Raw bytes inspected: %s (not retained or displayed)' \
	'rm -f "$gnss_raw" "$gnss_decoded" "$gnss_error"' \
	'head -c 32768 "$job_dir/stdout"'
do
	rg -F -- "$gps_guard" "$capture_worker" >/dev/null || fail "GPS/GNSS safety guard is missing: $gps_guard"
done
if printf '%s\n' "$gps_worker_section" | rg -n -- '/etc/init\.d/gpsd[[:space:]]+(start|enable|restart)|/usr/sbin/gpsd|/usr/bin/(gpspipe|gpsctl|ntripclient|curl|wget|socat)|(^|[;&|])[[:space:]]*(gpsd|gpspipe|gpsctl|stty|ntripclient|curl|wget|nc|socat)([[:space:]]|$)|(^|[[:space:]])dd[[:space:]].*of='; then
	fail 'GPS/GNSS worker contains service activation, receiver control, serial mutation, network access, or a device write'
fi
if printf '%s\n' "$gps_worker_section" | rg -n -- 'cat[[:space:]]+"?\$gnss_(raw|decoded)|head[^\n]*"?\$gnss_(raw|decoded)[^\n]*>>[[:space:]]*"?\$job_dir/stdout'; then
	fail 'GPS/GNSS worker exposes raw receiver input instead of whitelisted position fields'
fi

can_worker_section="$(sed -n '/elif \[ "$task" = "can_capture" \]/,/elif \[ "$task" = "camera_snapshot" \]/p' "$capture_worker")"
[[ "$(printf '%s\n' "$can_worker_section" | rg -c 'exec /usr/bin/timeout 25 /usr/bin/candump -L -n 128 -T 20000 "\$can_interface"')" -eq 1 ]] || fail 'reviewed passive candump command is missing or duplicated'
for can_guard in \
	'/sys/class/net/can[0-9]*' \
	"= '280'" \
	'/sys/devices/*' \
	'Exactly one reviewed physical CAN interface named canN is required.' \
	'can_number="${can_interface#can}"' \
	'can_flags_value=$((can_flags_before))' \
	'$((can_flags_value & 1)) -eq 1' \
	'ulimit -f 112' \
	'can_flags_after="$(cat "/sys/class/net/$can_interface/flags"' \
	'if [ "$can_flags_after" != "$can_flags_before" ]' \
	'head -c 57344 "$can_frames"' \
	'head -c 65536 "$job_dir/stdout"'
do
	rg -F -- "$can_guard" "$capture_worker" >/dev/null || fail "CAN safety guard is missing: $can_guard"
done
if printf '%s\n' "$can_worker_section" | rg -n -- '/usr/bin/(cansend|cangen|canplayer|isotpsend)|(^|[;&|])[[:space:]]*(cansend|cangen|canplayer|isotpsend|ip[[:space:]]+link[[:space:]]+set|ifconfig|tc)([[:space:]]|$)|(^|[[:space:]])candump[[:space:]].*(^|[[:space:]])-l([[:space:]]|$)'; then
	fail 'CAN worker contains transmit, replay, interface mutation, traffic control, or persistent-log behavior'
fi

while IFS= read -r file; do
	size="$(wc -c < "$file")"
	[[ "$size" -le 131072 ]] || fail "oversized router asset: $file ($size bytes)"
done < <(find files -type f | sort)

printf 'Local validation passed: shell, JavaScript, JSON, allowlist, mutation, and size checks.\n'
