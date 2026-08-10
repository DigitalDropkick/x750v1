#!/usr/bin/env bash

set -euo pipefail
umask 077

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${DDK_TARGET:-root@192.168.8.1}"
control_path="${DDK_SSH_CONTROL_PATH:-}"
target_host="${target#root@}"
browser_base="${DDK_BROWSER_BASE:-http://$target_host}"
session=''
csrf_token=''
artifact_probe_id=''

if [[ "$target" != "root@192.168.8.1" && "$target" != "root@100.122.115.85" ]]; then
	printf 'Refusing unexpected target: %s\n' "$target" >&2
	exit 64
fi
[[ "$browser_base" == "http://$target_host" ]] || {
	printf 'Refusing browser base that does not match the exact target: %s\n' "$browser_base" >&2
	exit 64
}

[[ -n "$control_path" && -S "$control_path" ]] || {
	printf '%s\n' 'A live DDK_SSH_CONTROL_PATH is required for transient browser-session creation.' >&2
	exit 69
}

ssh_args=(-o ConnectTimeout=10 -o StrictHostKeyChecking=yes -S "$control_path")

destroy_session() {
	if [[ "$artifact_probe_id" =~ ^job-[0-9]+-[0-9]+$ ]]; then
		local ending_probe="$artifact_probe_id"
		artifact_probe_id=''
		if ! ssh "${ssh_args[@]}" "$target" sh -s -- "$ending_probe" <<'ROUTER_CLEANUP'
set -eu
probe_id="$1"
case "$probe_id" in job-[0-9]*-[0-9]*) ;; *) exit 64 ;; esac
probe_dir="/tmp/ddk/jobs/$probe_id"
rm -f "$probe_dir/snapshot.jpg"
rmdir "$probe_dir" 2>/dev/null || true
ROUTER_CLEANUP
		then
			printf '%s\n' 'WARNING: transient camera-artifact ACL probe cleanup failed' >&2
		fi
	fi
	if [[ "$session" =~ ^[a-fA-F0-9]{32}$ ]]; then
		local ending_session="$session"
		session=''
		jq -nc --arg session "$ending_session" '{ ubus_rpc_session: $session }' |
			ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session destroy "$payload" >/dev/null' ||
				printf '%s\n' 'WARNING: transient browser session destruction failed' >&2
	fi
}

trap destroy_session EXIT
trap 'exit 130' HUP INT TERM

session_payload="$(ssh "${ssh_args[@]}" "$target" "ubus call session create '{ \"timeout\": 300 }'")"
session="$(printf '%s' "$session_payload" | jq -er '.ubus_rpc_session | select(test("^[a-fA-F0-9]{32}$"))')"
unset session_payload
csrf_token="$(openssl rand -hex 16)"

jq -nc --arg session "$session" --arg token "$csrf_token" '{ ubus_rpc_session: $session, values: { username: "root", token: $token } }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session set "$payload" >/dev/null'
unset csrf_token
jq -nc --arg session "$session" '{ ubus_rpc_session: $session, scope: "access-group", objects: [ [ "ddk-field-console", "read" ] ] }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'
jq -nc --arg session "$session" '{ ubus_rpc_session: $session, scope: "cgi-io", objects: [ [ "exec", "read" ], [ "download", "read" ], [ "upload", "write" ] ] }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'
jq -nc --arg session "$session" '{
	ubus_rpc_session: $session,
	scope: "file",
	objects: [
		[ "/usr/libexec/ddk-console status", "exec" ],
		[ "/usr/libexec/ddk-console capabilities", "exec" ],
		[ "/usr/libexec/ddk-console packages", "exec" ],
		[ "/usr/libexec/ddk-console info *", "exec" ],
		[ "/usr/libexec/ddk-console action *", "exec" ],
		[ "/usr/libexec/ddk-console upload *", "exec" ],
		[ "/usr/libexec/ddk-console job *", "exec" ],
		[ "/usr/libexec/ddk-console report *", "exec" ],
		[ "/overlay/ddk-field-console/uploads/upload-[0-9]*-[0-9]*-[0-9]*/payload.bin", "write" ],
		[ "/tmp/ddk/jobs/job-[0-9]*-[0-9]*/snapshot.jpg", "read" ]
	]
}' | ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'

auth_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --cookie "sysauth_http=$session" "$browser_base/cgi-bin/luci/admin/ddk/overview" || true)"
[[ "$auth_http" == '200' ]] || {
	printf 'Transient LuCI session preflight returned HTTP %s.\n' "$auth_http" >&2
	exit 1
}

artifact_probe_id="job-$(date +%s)-$$"
ssh "${ssh_args[@]}" "$target" sh -s -- "$artifact_probe_id" <<'ROUTER_PROBE'
set -eu
probe_id="$1"
case "$probe_id" in job-[0-9]*-[0-9]*) ;; *) exit 64 ;; esac
probe_dir="/tmp/ddk/jobs/$probe_id"
mkdir "$probe_dir"
chmod 700 "$probe_dir"
printf '%s' DDK_CAMERA_ARTIFACT_ACL_PROOF > "$probe_dir/snapshot.jpg"
chmod 600 "$probe_dir/snapshot.jpg"
ROUTER_PROBE
artifact_reply="$(curl -sS --max-time 8 --cookie "sysauth_http=$session" \
	--data-urlencode "sessionid=$session" \
	--data-urlencode "path=/tmp/ddk/jobs/$artifact_probe_id/snapshot.jpg" \
	--data-urlencode "filename=ddk-camera-$artifact_probe_id.jpg" \
	--write-out $'\nDDK_HTTP_STATUS:%{http_code}' \
	"$browser_base/cgi-bin/cgi-download")"
artifact_http="${artifact_reply##*DDK_HTTP_STATUS:}"
artifact_payload="${artifact_reply%$'\n'DDK_HTTP_STATUS:*}"
unset artifact_reply
[[ "$artifact_http" == '200' && "$artifact_payload" == 'DDK_CAMERA_ARTIFACT_ACL_PROOF' ]] || {
	printf 'Authenticated camera-artifact download proof failed: HTTP %s, %s response bytes.\n' "$artifact_http" "${#artifact_payload}" >&2
	exit 1
}
outside_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --cookie "sysauth_http=$session" \
	--data-urlencode "sessionid=$session" --data-urlencode 'path=/etc/shadow' \
	"$browser_base/cgi-bin/cgi-download" || true)"
[[ "$outside_http" != '200' ]] || {
	printf '%s\n' 'Camera-artifact ACL unexpectedly permitted an outside path.' >&2
	exit 1
}
printf '%s\n' 'Authenticated camera-artifact ACL proof passed; an outside path was denied.'

DDK_BROWSER_BASE="$browser_base" DDK_BROWSER_SESSION="$session" node "$project_root/scripts/verify-browser.mjs"
destroy_session
trap - EXIT HUP INT TERM
printf '%s\n' 'Transient LuCI browser session destroyed.'
