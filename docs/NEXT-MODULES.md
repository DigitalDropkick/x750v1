# Next Modules

Phase one deliberately exposes only INFO actions. Suggested wiring order balances field value, implementation risk, and the GL-X750's resource constraints.

## 1. Nmap LAN host discovery

Exact recommended next module: `network.nmap_lan_discovery`.

Start with one fixed `nmap-full` host-discovery profile only. Derive the permitted LAN CIDR server-side, reject WAN/Tailscale/cellular targets, cap host count, set a short host timeout and retry ceiling, write bounded output through the job framework, and retain the `SECURITY` classification. Do not accept raw flags or a free-form target.

## 2. Cellular read-only identity and signal snapshot

Use known read-only uqmi/qmicli calls against the detected EC25-AF. Explicitly avoid connect/disconnect, band changes, SIM PIN operations, resets, raw AT commands, or GL.iNet modem configuration.

## 3. Serial device attribution

Map each `/dev/ttyUSB*` node through sysfs to VID:PID/interface purpose. This prevents the Quectel modem ports from being presented as generic serial adapters.

## 4. Bounded tcpdump capture

Allowlist interfaces from the current link list, validate a small filter grammar or fixed presets, enforce duration and byte limits, save only in `/tmp/ddk/jobs/`, and never enable promiscuous mode persistently.

## 5. RTL-SDR / rtl_433 receive job

Enable only when a reviewed RTL-SDR VID:PID is present. Add duration, frequency range, output, concurrency, and worker-stop limits. Do not start a persistent rtl_tcp listener.

## 6. Camera snapshot

Enable only for an existing `/dev/videoN` node validated against sysfs. Start with one bounded still capture. Streaming remains later because it creates network-exposure and resource questions.

## 7. GPS snapshot

Add exact GNSS hardware attribution, then an on-demand position snapshot. Do not start gpsd automatically or include precise location in reports without an explicit privacy decision.

## 8. CAN read-only capture

Require an existing CAN interface and expose only bounded `candump`. Interface configuration and transmit remain DISRUPTIVE and disabled.

## 9. Android and Apple identification

Add device-presence and identity operations before any shell, recovery, restore, or filesystem action. Treat customer device identifiers as private and transient.

## 10. Firmware-programmer identification

Identify attached programmers without writing. Per-tool flash/read/erase workflows require separate manifests, confirmation, device targeting, power/voltage guidance, image hashing, and recovery procedures.
