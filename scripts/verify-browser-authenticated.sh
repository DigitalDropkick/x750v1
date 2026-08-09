#!/usr/bin/env bash

set -euo pipefail
umask 077

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${DDK_TARGET:-root@192.168.8.1}"
control_path="${DDK_SSH_CONTROL_PATH:-}"
session=''
csrf_token=''

if [[ "$target" != "root@192.168.8.1" ]]; then
	printf 'Refusing unexpected target: %s\n' "$target" >&2
	exit 64
fi

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

session_payload="$(ssh "${ssh_args[@]}" "$target" "ubus call session create '{ \"timeout\": 300 }'")"
session="$(printf '%s' "$session_payload" | jq -er '.ubus_rpc_session | select(test("^[a-fA-F0-9]{32}$"))')"
unset session_payload
csrf_token="$(openssl rand -hex 16)"

jq -nc --arg session "$session" --arg token "$csrf_token" '{ ubus_rpc_session: $session, values: { username: "root", token: $token } }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session set "$payload" >/dev/null'
unset csrf_token
jq -nc --arg session "$session" '{ ubus_rpc_session: $session, scope: "access-group", objects: [ [ "ddk-field-console", "read" ] ] }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'
jq -nc --arg session "$session" '{ ubus_rpc_session: $session, scope: "cgi-io", objects: [ [ "exec", "read" ] ] }' |
	ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'
jq -nc --arg session "$session" '{
	ubus_rpc_session: $session,
	scope: "file",
	objects: [
		[ "/usr/libexec/ddk-console status", "exec" ],
		[ "/usr/libexec/ddk-console capabilities", "exec" ],
		[ "/usr/libexec/ddk-console packages", "exec" ],
		[ "/usr/libexec/ddk-console info *", "exec" ],
		[ "/usr/libexec/ddk-console job *", "exec" ],
		[ "/usr/libexec/ddk-console report *", "exec" ]
	]
}' | ssh "${ssh_args[@]}" "$target" 'payload="$(read -r line; printf "%s" "$line")"; ubus call session grant "$payload" >/dev/null'

auth_http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --cookie "sysauth_http=$session" http://192.168.8.1/cgi-bin/luci/admin/ddk/overview || true)"
[[ "$auth_http" == '200' ]] || {
	printf 'Transient LuCI session preflight returned HTTP %s.\n' "$auth_http" >&2
	exit 1
}

DDK_BROWSER_SESSION="$session" node "$project_root/scripts/verify-browser.mjs"
destroy_session
trap - EXIT HUP INT TERM
printf '%s\n' 'Transient LuCI browser session destroyed.'
