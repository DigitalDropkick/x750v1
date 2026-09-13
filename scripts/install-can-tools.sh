#!/bin/sh
# Install only the missing userspace CAN payloads from this appliance's native feed.
set -eu
umask 077
[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Run on the router as root.' >&2; exit 1; }
[ -f /etc/openwrt_release ] && grep -q "22.03.4" /etc/openwrt_release || exit 64
[ -d /sys/module/can ] || { printf '%s\n' 'Matching CAN kernel support is not loaded.' >&2; exit 1; }
stage="$(mktemp -d /tmp/ddk-can-tools.XXXXXX)"
cd "$stage"
for package in canutils-candump canutils-cansend canutils-canplayer; do
 opkg status "$package" 2>/dev/null | grep -q '^Status:.* installed' && continue
 opkg download "$package"
done
for entry in \
 'canutils-candump_2021.08.0-2_mips_24kc.ipk:5d04a404bb4d48dff44a136eb2333881330914db962f78f9faf7ccb8fbba4ba3' \
 'canutils-cansend_2021.08.0-2_mips_24kc.ipk:4eae5ea43880efd10393859badc39247abae1d26bf7ab9a20ba9c74259a48494' \
 'canutils-canplayer_2021.08.0-2_mips_24kc.ipk:1c1a201fb677313a9f31a4f98126c3e6343ee338ebbacb446b33e3b8cabe0a7f'; do
 package_file="${entry%%:*}"; expected="${entry#*:}"
 [ -f "$package_file" ] || continue
 printf '%s  %s\n' "$expected" "$package_file" | sha256sum -c -
done
# Native libc and the canutils umbrella package already satisfy these dependencies.
for dependency in libc canutils; do opkg status "$dependency" | grep -q '^Status:.* installed'; done
for package in canutils-candump canutils-cansend canutils-canplayer; do
 if ! opkg status "$package" 2>/dev/null | grep -q '^Status:.* installed'; then
  opkg install "$stage/${package}_2021.08.0-2_mips_24kc.ipk"
 fi
done
for binary in candump cansend canplayer; do [ -x "/usr/bin/$binary" ] || exit 1; done
printf 'CAN userspace tools installed. Staged packages retained in %s\n' "$stage"
printf '%s\n' 'No kernel, library, network, or boot configuration changed.'
