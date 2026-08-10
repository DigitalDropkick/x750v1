#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${DDK_TARGET:-root@192.168.8.1}"
backup_path="${1:-}"
control_path="${DDK_SSH_CONTROL_PATH:-}"

if [[ "$target" != "root@192.168.8.1" && "$target" != "root@100.122.115.85" ]]; then
	printf 'Refusing unexpected target: %s\n' "$target" >&2
	exit 64
fi

if [[ -n "$backup_path" && ! "$backup_path" =~ ^/root/ddk-backups/[0-9]{8}T[0-9]{6}Z-field-console-v1(-[0-9]+)?$ ]]; then
	printf 'Refusing invalid backup path: %s\n' "$backup_path" >&2
	exit 64
fi

ssh_args=(-o ConnectTimeout=10 -o StrictHostKeyChecking=yes)
if [[ -n "$control_path" ]]; then
	[[ -S "$control_path" ]] || {
		printf 'SSH control socket is unavailable: %s\n' "$control_path" >&2
		exit 69
	}
	ssh_args+=(-S "$control_path")
fi

printf 'Rolling back Digital Dropkick Field Console on %s\n' "$target"
if [[ -n "$backup_path" ]]; then
	printf 'Requested backup: %s\n' "$backup_path"
fi

# backup_path is either empty or restricted above to a shell-safe absolute path.
# shellcheck disable=SC2029
ssh "${ssh_args[@]}" "$target" "sh -s -- '$backup_path'" < "$project_root/scripts/router-rollback.sh"
