#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${DDK_TARGET:-root@192.168.8.1}"
control_path="${DDK_SSH_CONTROL_PATH:-}"

if [[ "$target" != "root@192.168.8.1" ]]; then
	printf 'Refusing unexpected target: %s\n' "$target" >&2
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

printf 'Configuring native boot activation for /overlay/ddk-install.swap on %s\n' "$target"
printf '%s\n' 'The router script backs up only /etc/config/fstab and does not alter live swap, mount filesystems, or restart services.'
ssh "${ssh_args[@]}" "$target" 'sh -s' < "$project_root/scripts/router-configure-swap-autostart.sh"
