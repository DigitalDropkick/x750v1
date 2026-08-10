#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${DDK_TARGET:-root@192.168.8.1}"
control_path="${DDK_SSH_CONTROL_PATH:-}"

if [[ "$target" != "root@192.168.8.1" && "$target" != "root@100.122.115.85" ]]; then
	printf 'Refusing unexpected target: %s\n' "$target" >&2
	printf 'Set DDK_TARGET only after updating the identity policy deliberately.\n' >&2
	exit 64
fi

"$project_root/scripts/validate-local.sh"

ssh_args=(-o ConnectTimeout=10 -o StrictHostKeyChecking=yes)
if [[ -n "$control_path" ]]; then
	[[ -S "$control_path" ]] || {
		printf 'SSH control socket is unavailable: %s\n' "$control_path" >&2
		exit 69
	}
	ssh_args+=(-S "$control_path")
fi

printf 'Deploying Digital Dropkick Field Console to %s\n' "$target"
printf 'The remote installer will stop before writes unless identity, extroot, swap, space, and LuCI checks pass.\n'

tar -C "$project_root" -czf - files scripts/router-install.sh scripts/router-rollback.sh |
	ssh "${ssh_args[@]}" "$target" '
		set -eu
		stage="$(mktemp -d /tmp/ddk-field-console-deploy.XXXXXX)"
		trap '\''rm -rf -- "$stage"'\'' EXIT HUP INT TERM
		tar -xzf - -C "$stage"
		"$stage/scripts/router-install.sh" "$stage/files" "$stage/scripts/router-rollback.sh"
	'
