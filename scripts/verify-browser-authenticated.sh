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

session_payload="$(ssh "${ssh_args[@]}" "$target" "ubus call session create '{ \"timeout\": 1800 }'")"
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
# Grant precisely the application file ACLs (with staged path substitution for preview).
acl_path="$project_root/files/usr/share/rpcd/acl.d/ddk-field-console.json"
if [[ "${DDK_BROWSER_STAGED:-0}" == 1 ]]; then
 acl_path=/tmp/ddk-v3-full/usr/share/rpcd/acl.d/ddk-field-console.json
fi
jq -nc --arg session "$session" --slurpfile acl "$acl_path" '{ubus_rpc_session:$session,scope:"file",objects:([$acl[0]["ddk-field-console"] | (.read.file,.write.file) | to_entries[] | .key as $path | .value[] | [$path,.]])}' |
 ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'

auth_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --cookie "sysauth_http=$session" "$browser_base/cgi-bin/luci/admin/ddk/overview" || true)"
[[ "$auth_http" == '200' ]] || {
	printf 'Transient LuCI session preflight returned HTTP %s.\n' "$auth_http" >&2
	exit 1
}

DDK_BROWSER_BASE="$browser_base" DDK_BROWSER_SESSION="$session" node "$project_root/scripts/verify-browser.mjs"
destroy_session
trap - EXIT HUP INT TERM
printf '%s\n' 'Transient LuCI browser session destroyed.'
