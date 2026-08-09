# Next Modules

The first reviewed SECURITY module is now wired. The remaining order balances field value, implementation risk, and the GL-X750's resource constraints.

## Completed: Nmap LAN host discovery

`network.nmap_lan_discovery` is implemented as one fixed `nmap-full` host-discovery profile. The router derives `br-lan` scope server-side, rejects non-RFC1918 and broader-than-`/24` targets, applies rate/retry/host/wall-time limits, bounds output in `/tmp`, permits one active scan, and retains the `SECURITY` classification. Raw flags and browser target strings are not accepted.

## 1. Cellular read-only identity and signal snapshot

Use known read-only uqmi/qmicli calls against the detected EC25-AF. Explicitly avoid connect/disconnect, band changes, SIM PIN operations, resets, raw AT commands, or GL.iNet modem configuration.

## 2. Serial device attribution

Map each `/dev/ttyUSB*` node through sysfs to VID:PID/interface purpose. This prevents the Quectel modem ports from being presented as generic serial adapters.

## 3. Bounded tcpdump capture

Allowlist interfaces from the current link list, validate a small filter grammar or fixed presets, enforce duration and byte limits, save only in `/tmp/ddk/jobs/`, and never enable promiscuous mode persistently.

## 4. RTL-SDR / rtl_433 receive job

Enable only when a reviewed RTL-SDR VID:PID is present. Add duration, frequency range, output, concurrency, and worker-stop limits. Do not start a persistent rtl_tcp listener.

## 5. Camera snapshot

Enable only for an existing `/dev/videoN` node validated against sysfs. Start with one bounded still capture. Streaming remains later because it creates network-exposure and resource questions.

## 6. GPS snapshot

Add exact GNSS hardware attribution, then an on-demand position snapshot. Do not start gpsd automatically or include precise location in reports without an explicit privacy decision.

## 7. CAN read-only capture

Require an existing CAN interface and expose only bounded `candump`. Interface configuration and transmit remain DISRUPTIVE and disabled.

## 8. Android and Apple identification

Add device-presence and identity operations before any shell, recovery, restore, or filesystem action. Treat customer device identifiers as private and transient.

## 9. Firmware-programmer identification

Identify attached programmers without writing. Per-tool flash/read/erase workflows require separate manifests, confirmation, device targeting, power/voltage guidance, image hashing, and recovery procedures.
