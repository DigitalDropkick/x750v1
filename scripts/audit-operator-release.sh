#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
	printf 'OPERATOR RELEASE AUDIT FAILED: %s\n' "$1" >&2
	exit 1
}

manifest_root=files/usr/share/ddk-field-console/tools
mapfile -t manifests < <(find "$manifest_root" -maxdepth 1 -type f -name '*.json' | sort)
[[ "${#manifests[@]}" -gt 0 ]] || fail 'no tool manifests were found'

module_count="${#manifests[@]}"
action_count="$(jq -s '[.[].actions[]] | length' "${manifests[@]}")"
enabled_count="$(jq -s '[.[].actions[] | select(.enabled == true)] | length' "${manifests[@]}")"
structured_count="$(jq -s '[.[].actions[] | select(.parameter_schema == "operator-v1")] | length' "${manifests[@]}")"
unavailable_count="$(jq -s '[.[].actions[] | select(.enabled != true)] | length' "${manifests[@]}")"

[[ "$action_count" -eq 59 ]] || fail "release action count changed without review: $action_count"
[[ "$enabled_count" -eq 53 ]] || fail "enabled action count changed without review: $enabled_count"
[[ "$structured_count" -eq 38 ]] || fail "structured action count changed without review: $structured_count"
[[ "$unavailable_count" -eq 6 ]] || fail "unavailable action count changed without review: $unavailable_count"

jq -e -s '
	all(.[];
		type == "object" and
		(.id | type == "string" and test("^[a-z0-9][a-z0-9._-]+$")) and
		(.enabled | type == "boolean") and
		(.actions | type == "array")
	) and
	all(.[].actions[];
		(.id | type == "string" and test("^[a-z0-9][a-z0-9._-]+[.][a-z0-9._-]+$")) and
		(.class == "INFO" or .class == "ACTION" or .class == "SECURITY" or .class == "DISRUPTIVE") and
		(.enabled | type == "boolean") and
		(if .parameter_schema == null then true
		 else .enabled == true and .execution == "job" and .parameter_schema == "operator-v1" end) and
		(if .enabled == true then .unavailable_reason == null
		 else (.unavailable_reason | type == "string" and length >= 40 and length <= 512) end)
	)
' "${manifests[@]}" >/dev/null || fail 'a manifest or action violates the v2.1 release contract'

duplicate_modules="$(jq -s -r '[.[].id] | group_by(.)[] | select(length != 1) | .[0]' "${manifests[@]}")"
[[ -z "$duplicate_modules" ]] || fail "duplicate module ID: $duplicate_modules"
duplicate_actions="$(jq -s -r '[.[].actions[].id] | group_by(.)[] | select(length != 1) | .[0]' "${manifests[@]}")"
[[ -z "$duplicate_actions" ]] || fail "duplicate action ID: $duplicate_actions"

if ! diff -u \
	<(rg -v '^(#|[[:space:]]*$)' scripts/unavailable-action-ids.txt | sort) \
	<(jq -s -r '.[].actions[] | select(.enabled != true) | .id' "${manifests[@]}" | sort)
then
	fail 'the unavailable action inventory differs from the explicitly reviewed list'
fi

legacy_jobs="$(jq -s -r '.[].actions[] | select(.enabled == true and .execution == "job" and .parameter_schema != "operator-v1") | .id' "${manifests[@]}" | sort)"
[[ "$legacy_jobs" = $'can.capture\ncellular.snapshot' ]] || fail "unexpected enabled fixed-profile job remains: ${legacy_jobs//$'\n'/, }"

while IFS= read -r action; do
	[[ -n "$action" ]] || continue
	rg -F "[\"$action\"]" files/usr/libexec/ddk-console >/dev/null || fail "enabled action is absent from the backend: $action"
done < <(jq -s -r '.[].actions[] | select(.enabled == true) | .id' "${manifests[@]}" | sort)

planner_files=(
	files/usr/share/ddk-field-console/operator-actions.lua
	files/usr/share/ddk-field-console/operator-apple.lua
	files/usr/share/ddk-field-console/operator-phase3.lua
	files/usr/share/ddk-field-console/operator-phase4.lua
)
while IFS= read -r action; do
	[[ -n "$action" ]] || continue
	rg -F "[\"$action\"]" files/usr/libexec/ddk-console >/dev/null || fail "structured action is absent from exact backend mapping: $action"
	rg -F "\"$action\"" "${planner_files[@]}" >/dev/null || fail "structured action is absent from a server-owned planner: $action"
done < <(jq -s -r '.[].actions[] | select(.enabled == true and .parameter_schema == "operator-v1") | .id' "${manifests[@]}" | sort)

for gui_guard in \
	'action.unavailable_reason' \
	'ddk-tool-blocker' \
	'Unavailable action: '
do
	rg -F "$gui_guard" files/www/luci-static/resources/ddk/console-app.js >/dev/null || fail "GUI blocker disclosure is missing: $gui_guard"
done

if jq -s -r '.[].actions[] | select(.enabled != true) | .unavailable_reason' "${manifests[@]}" |
	rg -i 'too powerful|security sensitive|classification alone|because it is disruptive' >/dev/null
then
	fail 'an action is unavailable for a policy classification instead of a technical blocker'
fi

printf 'Operator release audit passed: %s modules, %s actions, %s enabled, %s structured, %s technically unavailable.\n' \
	"$module_count" "$action_count" "$enabled_count" "$structured_count" "$unavailable_count"
