# Next Modules

The first reviewed SECURITY module and the cellular INFO snapshot are now wired. The remaining order balances field value, implementation risk, and the GL-X750's resource constraints.

## Release phases

### Phase 2A — Appliance hardening and serial attribution (next)

1. Decide whether `/overlay/ddk-install.swap` should receive an explicit, rollback-tested boot activation entry. The file survived the observed reboot but did not reactivate; this configuration change requires separate approval.
2. Map every `/dev/ttyUSB*` and `/dev/ttyACM*` node through sysfs to its USB VID:PID, interface number, driver, and parent device without opening the port.
3. Label the EC25-AF modem functions separately from true general-purpose serial adapters so later tools cannot target the wrong port.
4. Add a compact post-reboot verification profile for version, `/ddk`, LuCI authentication, GL.iNet UI, extroot, swap, Tailscale, protected hashes, listeners, and idle workers.

### Phase 2B — Digital Dropkick brand alignment

Translate the public website's visual language into the console before several more tool workflows expand the interface. This is a design-token port, not a copy of the Astro/GoDaddy runtime.

Planned visual elements:

- black and paper-white foundations with a restrained Digital Dropkick green accent;
- the circular brand mark, optimized and stored locally;
- uppercase instrument typography, stronger title scale, thin grid lines, and hard-edged controls;
- subtle top/bottom fades and a lightweight CSS grid texture;
- website-inspired spacing and hierarchy while preserving the console's dense cards, status colors, and fast mobile operation.

Hard limits:

- no website JavaScript, analytics, trackers, external fonts, CDN requests, Astro runtime, or third-party CSS;
- no full-size hero photography in operational views;
- no animation that consumes idle CPU or obscures status;
- keep all CSS namespaced and preserve LuCI/GL.iNet pages;
- target no JavaScript growth, less than 8 KiB additional CSS, and at most one optimized local brand asset around 30 KiB;
- validate at 320 px, 390 px, and desktop widths, including contrast, focus visibility, horizontal overflow, and resource impact.

### Phase 3 — Bounded field operations

After the hardware map and visual system are stable, add packet capture first, then hardware-dependent receive/identify modules in the order below. Each executable workflow remains individually allowlisted, bounded, and tested.

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
