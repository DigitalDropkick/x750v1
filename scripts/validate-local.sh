#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
	printf 'LOCAL VALIDATION FAILED: %s\n' "$1" >&2
	exit 1
}

git diff --check
bash -n deploy.sh verify.sh rollback.sh
sh -n scripts/router-install.sh scripts/router-verify.sh scripts/router-rollback.sh files/usr/libexec/ddk-job-worker
node --check scripts/verify-browser.mjs >/dev/null

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

if rg -n 'uci[[:space:]]+(set|add|delete|commit)|firewall[.-](restart|reload)|/etc/init.d/(network|firewall|tailscale)[[:space:]]+(restart|reload|stop|start)|(^|[;&|])[[:space:]]*(cp|mv|sed[^[:space:]]*[[:space:]]+-i)[^\n]*/etc/config/(network|firewall|wireless)' files scripts/router-install.sh scripts/router-verify.sh scripts/router-rollback.sh; then
	fail 'production configuration mutation found'
fi

if rg -n 'cmd=[^[:space:]]|[?&]cmd=|action_id=.*shell|kill[[:space:]]+\$[A-Za-z_][A-Za-z0-9_]*' files/www files/usr/libexec; then
	fail 'generic browser command or PID-kill pattern found'
fi

while IFS= read -r action; do
	action_class="$(jq -r --arg id "$action" '.actions[] | select(.id == $id) | .class' files/usr/share/ddk-field-console/tools/*.json | head -n 1)"
	case "$action_class" in
		INFO) ;;
		SECURITY)
			rg -Fx "$action" scripts/enabled-security-actions.txt >/dev/null || fail "enabled SECURITY action was not explicitly reviewed: $action"
			;;
		*) fail "enabled action has a prohibited class: $action ($action_class)" ;;
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

while IFS= read -r file; do
	size="$(wc -c < "$file")"
	[[ "$size" -le 131072 ]] || fail "oversized router asset: $file ($size bytes)"
done < <(find files -type f | sort)

printf 'Local validation passed: shell, JavaScript, JSON, allowlist, mutation, and size checks.\n'
