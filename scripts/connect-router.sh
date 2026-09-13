#!/usr/bin/env bash
# Establish a private reusable SSH connection without putting passwords in files.
set -euo pipefail
target="${DDK_TARGET:-root@100.122.115.85}"
case "$target" in root@192.168.8.1|root@100.122.115.85) ;; *) printf 'Unknown router target: %s\n' "$target" >&2; exit 64 ;; esac
connection_dir="${XDG_RUNTIME_DIR:-/tmp}/ddk-router-${UID}"
if [[ ! -e "$connection_dir" ]]; then (umask 077; mkdir "$connection_dir"); fi
[[ -d "$connection_dir" && ! -L "$connection_dir" && -O "$connection_dir" ]] || exit 73
chmod 700 "$connection_dir"
control_path="$connection_dir/control"
printf 'Router: %s\nEnter the router administrator password in this terminal.\n' "$target"
printf 'Control socket: %s\nLeave this terminal open while working with the router.\n' "$control_path"
exec ssh -M -N -S "$control_path" -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "$target"
