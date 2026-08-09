# Next Modules

Two reviewed SECURITY modules, one hardware-gated ACTION module, and the cellular INFO snapshot are now wired. The remaining order balances field value, implementation risk, and the GL-X750's resource constraints.

## Release phases

### Phase 2A — Appliance hardening and serial attribution (implemented in 1.3.0)

1. The separately approved native swap entry has guarded configure/rollback tooling and an exact fstab backup model.
2. Every `/dev/ttyUSB*` and `/dev/ttyACM*` node is mapped through sysfs to USB identity, interface number, driver, and parent without opening the port.
3. All EC25-AF serial functions are `MODEM RESERVED`; unreviewed adapters cannot satisfy the general serial hardware class.
4. `post-reboot-verify.sh` checks the boot-critical appliance invariants without starting bounded tools.

The acceptance gate passed on 2026-08-09: 10 compact post-reboot checks and 22 comprehensive checks completed with no warnings, followed by authenticated mobile and desktop browser verification. The router required an attended physical power cycle after the software reboot left it dark; this operational behavior is recorded in the target documentation.

### Phase 2B — Digital Dropkick brand alignment (implemented in 1.4.0)

Translate the public website's visual language into the console before several more tool workflows expand the interface. This is a design-token port, not a copy of the Astro/GoDaddy runtime.

Implemented visual elements:

- black and paper-white foundations with a restrained Digital Dropkick green accent;
- the circular brand mark, optimized and stored locally;
- uppercase instrument typography, stronger title scale, thin grid lines, and hard-edged controls;
- subtle top/bottom fades and a lightweight CSS grid texture;
- website-inspired spacing and hierarchy while preserving the console's dense cards, status colors, and fast mobile operation.

Enforced limits:

- no website JavaScript, analytics, trackers, external fonts, CDN requests, Astro runtime, or third-party CSS;
- compact, 320-pixel-tall source scenes only; each view requests one scene;
- no animation that consumes idle CPU or obscures status;
- keep all CSS namespaced and preserve LuCI/GL.iNet pages;
- six optimized files total no more than 170 KiB, each scene no more than 44 KiB, and the shared logo no more than 10 KiB;
- validate at 320 px, 390 px, and desktop widths, including contrast, focus visibility, horizontal overflow, and resource impact.

The acceptance gate passed on 2026-08-09: 24 production checks completed with no warnings; all five authenticated page headers and both logo placements loaded at mobile and desktop widths; 44-pixel touch targets and keyboard focus were confirmed; and no external request, runtime error, or horizontal document overflow was observed. The deployed tree matched source byte for byte and left no DDK worker or listener active.

### Phase 3 — Bounded field operations

With the hardware map, visual system, and bounded metadata capture in place, add hardware-dependent receive/identify modules in the order below. Each executable workflow remains individually allowlisted, bounded, and tested.

### Phase 3A — Bounded LAN metadata capture (implemented in 1.5.0)

`capture.lan_metadata_snapshot` uses the already-installed `tcpdump` on server-derived `br-lan` with one fixed ARP/ICMP/IPv4-DHCP BPF profile. It is non-promiscuous, accepts no browser arguments, stops after 20 seconds or 128 packets, emits at most 64 KiB of decoded transient text, and never creates a PCAP. General capture and packet replay remain disabled.

The acceptance gate passed on 2026-08-09: 27 production checks completed with no warnings, including stop and full-window capture proofs. Authenticated browser checks passed at 320 px, 390 px, and desktop widths, all 39 deployed files matched source, protected configuration remained unchanged, and no capture process, DDK worker, or DDK listener remained.

## Completed: Nmap LAN host discovery

`network.nmap_lan_discovery` is implemented as one fixed `nmap-full` host-discovery profile. The router derives `br-lan` scope server-side, rejects non-RFC1918 and broader-than-`/24` targets, applies rate/retry/host/wall-time limits, bounds output in `/tmp`, permits one active scan, and retains the `SECURITY` classification. Raw flags and browser target strings are not accepted.

## Completed: Cellular read-only identity and signal snapshot

`cellular.snapshot` validates the exact EC25-AF topology, runs four fixed read-only UQMI actions with per-query limits, and emits only whitelisted modem, registration, and signal fields. Connect/disconnect, subscriber IDs, SIM contents, APN/current settings, bands, PIN/PUK, cell location, scans, resets, raw AT/QMI, and GL.iNet modem configuration are excluded.

## Completed: Serial device attribution

The sysfs-only inspector maps each serial node to VID:PID, parent, interface, and driver. It marks the verified EC25-AF ports modem-reserved and makes no unverified interface-role claims.

### Phase 3B — Hardware-gated RTL-433 receive job (implemented in 1.6.0)

`radio.rtl433_snapshot` is implemented with exact `0bda:2832/2838` hardware and safe-serial gates, a fixed 433.92 MHz/250 kS/s/20-second profile, no raw or network output, child/final file limits, and shared tuner locking. No reviewed dongle was attached, so production acceptance is limited to the no-device refusal path until hardware is available.

The no-device acceptance gate passed on 2026-08-09: 29 production checks completed with no warnings, both backend and worker hardware gates failed closed without starting a receiver, `rtl_tcp` remained unchanged and disabled, port 1234 remained closed, authenticated desktop/mobile UI correctly disabled the ACTION control, and all 39 deployed files matched source. Live receive and cancellation acceptance remain pending hardware.

## 2. Camera snapshot

Enable only for an existing `/dev/videoN` node validated against sysfs. Start with one bounded still capture. Streaming remains later because it creates network-exposure and resource questions.

## 3. GPS snapshot

Add exact GNSS hardware attribution, then an on-demand position snapshot. Do not start gpsd automatically or include precise location in reports without an explicit privacy decision.

## 4. CAN read-only capture

Require an existing CAN interface and expose only bounded `candump`. Interface configuration and transmit remain DISRUPTIVE and disabled.

## 5. Android and Apple identification

Add device-presence and identity operations before any shell, recovery, restore, or filesystem action. Treat customer device identifiers as private and transient.

## 6. Firmware-programmer identification

Identify attached programmers without writing. Per-tool flash/read/erase workflows require separate manifests, confirmation, device targeting, power/voltage guidance, image hashing, and recovery procedures.
