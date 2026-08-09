# Next Modules

The first reviewed SECURITY module and the cellular INFO snapshot are now wired. The remaining order balances field value, implementation risk, and the GL-X750's resource constraints.

## Completed: Nmap LAN host discovery

`network.nmap_lan_discovery` is implemented as one fixed `nmap-full` host-discovery profile. The router derives `br-lan` scope server-side, rejects non-RFC1918 and broader-than-`/24` targets, applies rate/retry/host/wall-time limits, bounds output in `/tmp`, permits one active scan, and retains the `SECURITY` classification. Raw flags and browser target strings are not accepted.

## Completed: Cellular read-only identity and signal snapshot

`cellular.snapshot` validates the exact EC25-AF topology, runs four fixed read-only UQMI actions with per-query limits, and emits only whitelisted modem, registration, and signal fields. Connect/disconnect, subscriber IDs, SIM contents, APN/current settings, bands, PIN/PUK, cell location, scans, resets, raw AT/QMI, and GL.iNet modem configuration are excluded.

## 1. Serial device attribution

Map each `/dev/ttyUSB*` node through sysfs to VID:PID/interface purpose. This prevents the Quectel modem ports from being presented as generic serial adapters.

## 2. Bounded tcpdump capture

Allowlist interfaces from the current link list, validate a small filter grammar or fixed presets, enforce duration and byte limits, save only in `/tmp/ddk/jobs/`, and never enable promiscuous mode persistently.

## 3. RTL-SDR / rtl_433 receive job

Enable only when a reviewed RTL-SDR VID:PID is present. Add duration, frequency range, output, concurrency, and worker-stop limits. Do not start a persistent rtl_tcp listener.

## 4. Camera snapshot

Enable only for an existing `/dev/videoN` node validated against sysfs. Start with one bounded still capture. Streaming remains later because it creates network-exposure and resource questions.

## 5. GPS snapshot

Add exact GNSS hardware attribution, then an on-demand position snapshot. Do not start gpsd automatically or include precise location in reports without an explicit privacy decision.

## 6. CAN read-only capture

Require an existing CAN interface and expose only bounded `candump`. Interface configuration and transmit remain DISRUPTIVE and disabled.

## 7. Android and Apple identification

Add device-presence and identity operations before any shell, recovery, restore, or filesystem action. Treat customer device identifiers as private and transient.

## 8. Firmware-programmer identification

Identify attached programmers without writing. Per-tool flash/read/erase workflows require separate manifests, confirmation, device targeting, power/voltage guidance, image hashing, and recovery procedures.
