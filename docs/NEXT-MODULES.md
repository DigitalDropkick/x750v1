# Release Modules and Future Hardware Acceptance

> Historical v2 roadmap: the fixed-profile and SSH-handoff limitations below record what was production-accepted in versions 1.x–2.0. Repository-root `AGENTS.md` and [Operator Mode](OPERATOR-MODE.md) supersede those limitations as product policy. Version 2.1 must migrate practical native functionality through structured schemas, exact backend argv builders, target validation, resource controls, artifacts, and appropriate confirmation. Classification as `ACTION`, `SECURITY`, or `DISRUPTIVE` is not a blocker.

Version 2.0 completed the earlier base-console plan and remains the production-accepted baseline until the authorized 2.1 deployment passes. Version 2.1 now implements the shared architecture plus network/capture, radio/camera/GPS/serial, Android, Apple, firmware-programming, and storage/recovery migrations. Live acceptance remains conditional on approved attached hardware; industrial/Modbus, Bluetooth/smartcard, CAN expansion, monitoring, and automation remain outstanding.

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

### Phase 3C — Hardware-gated camera still (implemented in 1.7.0)

`camera.still_snapshot` requires exactly one sysfs-attributed USB UVC camera and primary video node, confirms V4L2 capture capability and exclusive availability, then creates one fixed 640×480 JPEG under the existing transient job boundary. The browser receives no device/profile controls and uses native authenticated LuCI download with an exact artifact ACL. `mjpg-streamer`, Motion, RTSP, audio, uploads, and all streaming remain disabled.

No camera was attached during development, so acceptance is limited to the no-device refusal, service/configuration isolation, and authenticated artifact ACL until approved UVC hardware and privacy consent are available. The no-device gate passed on 2026-08-09: 31 production checks completed with no warnings, the authenticated artifact proof allowed only the exact transient JPEG path and denied `/etc/shadow`, responsive browser checks passed, and all 39 deployed files matched source.

### Phase 3D — Hardware-gated GPS/GNSS snapshot (implemented in 1.8.0)

`gps.snapshot` requires exactly one sysfs-attributed external USB GNSS receiver and one exclusive reviewed serial node. It explicitly excludes every EC25-AF port, starts no service, changes no termios setting, reads no more than 32 KiB over 15 seconds, checksum-filters NMEA, renders only whitelisted position fields, and deletes raw data. Precise location requires explicit UI confirmation and is excluded from system reports. No receiver was attached during development, so live fix and cancellation acceptance remain pending approved hardware.

The no-device acceptance gate passed as part of the v1.9 Burn One suite: backend refusal occurred before job creation, the worker independently rejected every EC25-only serial topology, no raw/decoded file or GPS process remained, `gpsd` configuration stayed byte-identical and disabled, and the responsive UI exposed no runnable control.

### Phase 3E — Passive CAN frame snapshot (implemented in 1.9.0)

`can.capture` requires exactly one already-up physical `canN` interface and `/usr/bin/candump`, then runs one fixed receive-only 128-frame/20-second profile with independent wall/file/output limits and interface-flag comparison. Interface setup, bitrate changes, transmit, replay, ISO-TP send, and persistent logs remain disabled. The target currently has no CAN interface, and its installed `canutils` record exposes no executable payload, so the UI reports `HARDWARE REQUIRED` plus missing `candump` and remains disabled without package changes. Live capture and cancellation acceptance remain pending approved hardware and runtime availability.

The no-device/missing-runtime acceptance gate passed as part of the v1.9 Burn One suite: both conditions were visible through the API/UI, backend refusal created no job, the worker independently rejected before any utility launch, no frame file/process remained, and listener/network state stayed unchanged.

## 4. Android and Apple identification (implemented in 2.0.0)

`android.identify` and `apple.identify` read bounded sanitized sysfs only. Customer USB serial identifiers exist only in the confirmed authenticated response; status, jobs, reports, logs, and persistent storage receive none. Positive synthetic ADB and Apple recovery fixtures plus negative Apple Bluetooth/generic FTDI fixtures prove the conservative classifier. `android.operator_guide` and `apple.operator_guide` remain supplemental non-executable native references; structured GUI actions are primary for represented workflows.

Android is subsequently migrated in the local 2.1 source: `android.adb_diagnostics` and `android.adb_manage` use exact ADB 1.0.32 structured controls, live USB transport correlation, an isolated temporary port-5038 server, sealed inputs, bounded artifacts, cancellation, and exact target/material confirmation. Apple is also migrated through five normal/recovery/DFU/restore actions with on-demand usbmuxd, ECID/UDID correlation, sealed inputs, isolated restore cache, and confirmation. See [ANDROID-ADB.md](ANDROID-ADB.md) and [APPLE-OPERATOR.md](APPLE-OPERATOR.md).

## 5. Firmware and storage Operator Mode (implemented in 2.1.0 source)

`firmware.identify` still identifies reviewed programmers without opening them or invoking a tool. Four separate structured jobs now cover OpenOCD, AVRDUDE, USB DFU, and STM32Flash/BOSSA/LPC serial bootloaders with exact target/config/part/input selection, backups, verify/write/erase/boot controls, confirmation, cancellation, and cleanup. The static guide is supplemental rather than primary.

Five storage jobs now cover SMART/read-only checks, confirmed filesystem/media repair, bounded raw imaging, confirmed restore, and isolated SquashFS recovery. The active extroot/system/swap disk is excluded in both inventory and worker. See [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md).

`flashrom` remains genuinely unavailable because its package record has no executable payload. FTDI EEPROM write remains deferred pending an action-owned config serializer. Generic OpenOCD readback remains target-specific rather than pretending one address/length schema is reliable for every target. Live hardware-changing acceptance is pending an approved attached target.

The combined v2 acceptance gate passed on 2026-08-09: 37 production checks completed with no warnings; authenticated browser validation passed at 320 px, 390 px, and desktop widths; every one of the 40 deployed files matched source; protected configurations and listener state remained unchanged; and no device utility, DDK worker, or new listener remained. Hardware-specific classification acceptance is intentionally still pending approved devices.

## Recommended next work

1. Attach one approved firmware or non-system storage target at a time and verify native execution, readback/artifacts, cancellation, cleanup, and consequential confirmation.
2. Audit and migrate exact installed industrial/Modbus tools with connection/unit/register/datatype schemas and confirmed writes.
3. Audit Bluetooth, smartcard, monitoring, and automation families, including on-demand helper ownership where required.
4. Revisit CAN only after an actual CAN interface and executable runtime are present; then add structured receive/filter/config/transmit with target-aware confirmation.
5. Keep `candump`, fastboot, and flashrom unavailable until their genuine payload/runtime requirements are present under separate package/hardware authorization; do not install substitutes implicitly.
