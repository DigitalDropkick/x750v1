# Changelog

## 2.1.0 — 2026-08-10

### Operator Mode foundation

- Added a versioned base64url JSON action envelope, reusable server-owned schemas, strict unknown-field/type/range/character validation, and action-specific literal argv builders in `operator-actions.lua`.
- Added five-minute mode-restricted prepared plans, atomic single-use claims, exact action-to-worker-to-executable checks, target-bound confirmation, normalized job metadata, and server-built invocation review.
- Replaced race-prone job counting with atomic two-slot, action-singleton, and shared-resource locks with cleanup and stale-owner recovery.
- Generalized authenticated job artifacts to fixed action-owned names and exact rpcd ACL patterns without exposing arbitrary router paths.
- Added reusable GUI fields, advanced options, review/confirmation, native error display, and authenticated artifact downloads.
- Added authenticated DDK-controlled input staging with exact upload reservations, extension/size policies, atomic sealing, closed write paths, archive-magic checks, SHA-256 identity, 10-file retention, expiry, listing, and deletion.
- Added action-declared sealed-input binding, per-upload resource locks, start-time hash/size/mode revalidation, private input metadata, and authenticated streaming downloads for artifacts larger than 16 MiB.

### First native tool migration

- Migrated Nmap 7.91 to validated target/exclude, discovery/scan, TCP/UDP, port, timing, detection, OS/traceroute, DNS, reviewed NSE, rate/retry, and native text/XML/grepable output controls without the v2 `/24` clamp.
- Migrated tcpdump 4.9.3/libpcap 1.10.1 to live interface selection, one validated BPF argv element, time/count/snap/promiscuous/decode controls, and bounded authenticated PCAP output.
- Enabled iperf3 3.11 client and temporary server workflows with structured protocol, endpoint, transfer, stream, bitrate, reverse/bidirectional, bind, TCP, interval, and JSON controls.
- Migrated rtl_433 20.11 to live reviewed tuner selection, receive frequency/sample/gain/PPM, decoder/analyzer/metadata, duration, decoded formats, and bounded raw I/Q artifacts.
- Migrated fswebcam 20140113 to live reviewed UVC-node selection, bounded native still controls, JPEG/PNG output, worker hardware revalidation, and authenticated image artifacts.
- Added structured non-EC25 serial receive/transmit sessions through socat 1.7.4.1 and stty 9.0, private transmit input, independent modem-port rejection, and tty-state restoration.
- Migrated GPS/GNSS receive to live reviewed receiver selection, bounded `/bin/dd`, gpsdecode 3.23.1 options, position summary, and raw/decoded artifacts without starting gpsd.
- Migrated ADB 1.0.32 to correlated USB transport selection, structured diagnostics/backup/file/package/device management, fixed shell subcommands, exact target/material confirmation, sealed upload consumption, bounded artifacts, a shared discovery/job resource lock, and an isolated temporary localhost server on port 5038 with cleanup on every exit.
- Migrated Apple tools to exact libimobiledevice 1.3.0, usbmuxd 1.1.1, irecovery 1.0.0, and idevicerestore 1.0.0 workflows: normal-mode diagnostics/management/capture, ECID-bound recovery/DFU operations, authenticated recovery/IPSW/AP-ticket inputs, target-bound confirmation, bounded artifacts, and isolated restore workspaces.
- Added an exact Apple family worker that starts usbmuxd only on demand, refuses pre-existing helper ownership, revalidates UDID/ECID immediately before execution, tracks cancellation, protects extroot free space during restore, and removes its helper/cache/locks on every exit.
- Preserved legacy fixed workers for compatibility while routing the v2.1 GUI through prepared Operator Mode actions.

### Firmware and storage migration

- Migrated OpenOCD 0.11 to reviewed live debug-adapter selection, installed board/interface/target configs, exact USB-topology binding, server-generated no-listener command files, probe/program controls, and confirmed sealed-image writes.
- Migrated AVRDUDE 6.3 to exact installed programmer/part lists, stable USB-serial or reviewed serial-port selection, probe, flash/EEPROM read, verify, write, erase, formats, timing, verification, and authenticated backup artifacts.
- Migrated dfu-util 0.11 and dfu-programmer 0.7.2 to live DFU interface selection, topology/serial or bus/address binding, read/write/detach/erase/launch/get controls, sealed images, confirmations, and binary backups.
- Migrated STM32Flash, BOSSA 1.9.1, and LPC21ISP 1.97 to reviewed non-EC25 serial targets with native information/read/write/verify/erase/CRC/go/reset/security/boot controls where supported by each exact binary.
- Added a conservative non-system USB block inventory that excludes every disk backing root, rom, overlay, extroot, or swap and binds target size/mount state again in the worker.
- Added smartctl 7.2 health/tests, e2fsck 1.46.5 checks/repair, badblocks read/non-destructive tests, 16 GiB byte-range BusyBox dd imaging/restore with SHA-256/compare, and unsquashfs 4.5 stat/list/extract with isolated tar artifacts.
- Added the exact `ddk-phase3-worker` with native-version/argv/target/input revalidation, target/resource locks, cancellation, 100 MiB extroot reserve enforcement, fixed artifacts, and partial-output/workspace cleanup.
- Reframed the v2 static SSH handoffs as supplemental native references; structured GUI actions are now the primary interface for represented mobile, firmware, and storage work.

### Phase 4 tool-family completion

- Added 15 reusable `operator-v1` actions through pure `operator-phase4.lua` schemas and the exact allowlisted `ddk-phase4-worker` for monitoring, wireless/USB inventory, file forensics, packet replay, ADS-B/AIS, Bluetooth discovery, MQTT/relay, Modbus reads, smartcard/YubiKey, temporary camera streams, and NTRIP.
- Added named one-time private inputs for MQTT payload/password, YubiKey secrets, camera passwords, and NTRIP passwords; metadata and invocation previews retain only redacted markers.
- Added sealed forensic/capture input kinds, fixed authenticated Phase 4 artifact ACLs, live target selection, independent target/input/argv validation, wall/output limits, resource locks, cancellation, helper ownership, and cleanup.
- Recorded exact remaining blockers for CAN transmit, Modbus writes, USB power/attach, Wi-Fi monitor-mode changes, and raw cellular commands in `docs/PHASE4-OPERATOR.md`.
- Deployed Phase 4 with rollback snapshot `/root/ddk-backups/20260810T200750Z-field-console-v1`; 49 production checks passed with 0 warnings, authenticated desktop/mobile browser acceptance passed all Phase 4 controls, six safe native workflow families executed, the MQTT failure path proved secret redaction/cleanup, and all 47 deployed files matched source byte for byte with no residual worker/tool/listener/upload.

### Phase 5 release closure

- Added a dynamic release audit for all 24 modules and 59 exact actions: 53 enabled, 38 structured, two reviewed fixed-profile jobs, and six technically unavailable.
- Required every unavailable action to carry a bounded action-level technical reason and added a separately reviewed unavailable-action inventory.
- Displayed exact blockers beside disabled controls and in their accessible titles; browser acceptance now checks all six disclosures.
- Corrected current hardware-selection documentation and explicitly labeled superseded v1 fixed-profile pages as historical acceptance records.
- Added a target-side inventory contract so deployed verification fails on action duplication, schema/enabled drift, undocumented blockers, or an unexpected unavailable action.
- Deployed Phase 5 with rollback snapshot `/root/ddk-backups/20260810T210034Z-field-console-v1`; 50 production checks passed with 0 warnings, authenticated 1440/390/320 px browser acceptance verified all six blocker disclosures, all 47 deployed files matched source, and no worker/private input/proof upload/helper/listener remained.

### Validation and release status

- Updated local policy validation so `ACTION`, `SECURITY`, and reviewed `DISRUPTIVE` actions may be enabled when fully wired; removed tests whose purpose was to enforce the obsolete GUI-disabled/SSH-only policy.
- Added malformed-envelope, unknown-option, prepared-request, loopback Nmap artifact, loopback tcpdump PCAP/BPF, loopback iperf3, upload traversal/size/signature/sealing/hash cleanup, ADB builder/worker/temporary-server rejection, hardware-gate, and reusable browser-control verification.
- Added exact installer preflight for all migrated binaries plus target-Lua compilation/runtime builder validation.
- Added a pure Phase 3 planner suite covering all nine new actions, consequential confirmation, compound artifact/upload placeholders, target binding, active-system-media exclusion, ranges, unknown fields, and path traversal, plus target-safe worker no-device cleanup verification.
- Production deployment passed 48 target checks with 0 warnings plus authenticated desktop/mobile browser acceptance, including structured controls and upload/seal/hash/delete. All 45 deployed files matched source byte for byte; protected configuration remained unchanged; and no DDK worker, operator-tool listener, or browser-proof upload remained. The full v2.0 rollback snapshot is `/root/ddk-backups/20260810T183331Z-field-console-v1`; the later UI-fix preinstall snapshot is `/root/ddk-backups/20260810T190440Z-field-console-v1`.

## 2.0.0 — 2026-08-09

### Added

- Burn Two private/transient `android.identify`, `apple.identify`, and `firmware.identify` INFO actions.
- Dedicated bounded `usb-identity.lua` classifier for Android ADB/fastboot/MTP evidence, Apple mobile/recovery/DFU descriptors, and reviewed firmware programmer identities.
- Live hardware counts/readiness on Overview and in the Tool Registry without exposing customer identifiers through status.
- Full native-CLI handoffs for Android, Apple, and firmware tools, including live executable readiness and copyable SSH references that are never executed by the browser.
- Mobile/programmer privacy, hardware-detection, full-tool handoff, and hardware-acceptance documentation.

### Privacy and operational safety

- Identity reads sanitized sysfs only; it opens no device node and invokes no ADB, fastboot, usbmuxd, idevice, recovery, restore, debugger, DFU, or programmer utility.
- Customer USB serial identifiers exist only in the explicitly confirmed authenticated response. No identity action creates a job, report field, log, cache, temporary file, or persistent record.
- The installed CLI programs remain unmodified and fully functional over SSH. Browser-based shell, pairing, restore, recovery, debug, read, write, erase, and flash placeholders remain disabled.
- The target has no reviewed Android, Apple mobile, or programmer device attached. `fastboot` and `flashrom` executables are unavailable and are reported without package changes.

### Validation status

- Local shell, JavaScript, JSON, allowlist, mutation, identity-boundary, asset, and size validation passes.
- Synthetic tests on the router's Lua 5.1/nixio stack accept reviewed Android ADB, Apple recovery, and SEGGER fixtures while rejecting Apple Bluetooth and generic FTDI false positives.
- The staged v2 backend completed live sysfs status/capability calls and all six new INFO actions without changing DDK job count, related process state, or ADB/mobile listener state.
- Production verification passed 37 checks with 0 warnings, including all six new INFO actions, private-identity/report separation, injection and extra-argument rejection, synthetic positive/negative fixtures, prior bounded workflows, protected configuration, UI endpoints, and absence of residual device-tool processes or listeners.
- Authenticated browser verification passed at 320 px, 390 px, and desktop widths. Identity confirmation/output and full native-CLI handoffs worked; all five local brand scenes loaded; no external request, runtime error, or horizontal overflow occurred; and visual review found the layouts coherent and readable.
- All 40 deployed project files matched source byte for byte and normalized listener state matched the pre-deployment snapshot. The v1.9 rollback backup is `/root/ddk-backups/20260810T011634Z-field-console-v1`.
- Live customer-device classification remains pending approved Android, Apple, and programmer hardware. The production no-device state reports honestly and invokes none of those tools.

## 1.9.0 — 2026-08-09

### Added

- Phase 3E `can.capture` ACTION workflow with exactly-one physical `canN`, `IFF_UP`, `/usr/bin/candump`, singleton, and shared-resource gates.
- Fixed receive-only `candump -L -n 128 -T 20000` profile with a 25-second independent wall limit, 56-KiB child ceiling, 64-KiB final ceiling, DDK-owned cancellation, and interface-flag comparison.
- Explicit UI authorization/privacy confirmation, hardware/runtime readiness reason, and [passive CAN documentation](docs/CAN-PASSIVE-CAPTURE.md).

### Safety and compatibility

- The browser cannot select an interface, bitrate, filter, frame count, duration, output, command, or flag. `cansend`, generation, replay, ISO-TP transmit, link setup, bitrate changes, and persistent capture logs are absent.
- The target's existing `canutils` 2021.08.0-2 record contains no payload, `/usr/bin/candump` is absent, and no CAN interface exists. Version 1.9 reports those facts and stays disabled; it installs, repairs, replaces, and forces nothing.
- GPS/GNSS v1.8, all previous workflows, protected configuration hashes, LuCI authentication, GL.iNet UI, Tailscale, extroot, swap, and zero-idle-process architecture remain unchanged.

### Validation status

- Production verification passed 35 checks with 0 warnings, including both new backend/worker refusal paths, missing-`candump` visibility, coordinate/report separation, protected configuration, prior workflows, UI endpoints, resource health, and absence of residual processes/listeners.
- Authenticated browser verification passed at 320 px, 390 px, and desktop widths. Both controls were visibly `HARDWARE REQUIRED`, ACTION-styled, disabled, and free of external requests, runtime errors, or horizontal overflow.
- All 39 deployed project files matched source byte for byte and listener state matched the pre-deployment snapshot. The v1.7 rollback backup is `/root/ddk-backups/20260810T003641Z-field-console-v1`.
- Live CAN receive, cancellation, output-format, and bus-impact acceptance remain pending an approved adapter, an already-configured physical `canN`, and a reviewed `candump` executable. Backend/worker refusal and missing-runtime visibility are production-testable now.

## 1.8.0 — 2026-08-09

### Added

- Phase 3D `gps.snapshot` ACTION workflow using the already-installed `gpsdecode` and fixed receive-only byte-copy primitives.
- Exact sysfs attribution for one external USB GNSS receiver, one reviewed serial driver/node, exclusive device use, and explicit rejection of the Quectel EC25-AF.
- Bounded 15-second/32-KiB raw capture, checksum-filtered NMEA, whitelisted position rendering, shared GPS resource locking, and raw-data cleanup on success, failure, or stop.
- Dedicated operator privacy confirmation and [GPS/GNSS snapshot documentation](docs/GPS-GNSS-SNAPSHOT.md).

### Security

- The browser cannot choose a device, baud rate, duration, command, output path, decoder, or field set; backend and worker independently derive and validate hardware.
- `gpsd`, serial reconfiguration, receiver commands, NTRIP, RTK correction traffic, and all new network access remain disabled. Precise coordinates are transient and excluded from DDK system reports.
- Existing `/etc/config/gpsd` is hash-protected alongside network, radio, and camera configuration.

### Validation status

- Local shell, JavaScript, JSON, allowlist, mutation, asset, and size validation passes.
- No external USB GNSS receiver was attached during development. Backend/worker no-device refusal and process/config isolation are testable now; live fix quality, receive cancellation, and measured device behavior remain pending approved hardware and explicit privacy consent.

## 1.7.0 — 2026-08-09

### Added

- Phase 3C `camera.still_snapshot` ACTION workflow using the already-installed `fswebcam` 20140113, `v4l-utils` 1.20.0, and `file` 5.41 tools.
- Conservative sysfs UVC attribution, exactly-one-device/primary-node gates, V4L2 capture-capability confirmation, existing-device-use refusal, and a shared `camera` job resource.
- Fixed one-frame 640×480 JPEG profile with explicit privacy/consent confirmation, an independent 20-second wall limit, a 256 KiB file ceiling, and JPEG type/magic validation.
- Authenticated native LuCI camera-artifact view/download with an exact job-path ACL and no file below `/www`.
- Camera-specific operating, privacy, service-isolation, and pending-hardware acceptance documentation.

### Safety and current scope

- The browser cannot choose a camera, node, path, resolution, quality, duration, command hook, output, or destination; the backend and worker independently derive and validate hardware.
- Stopped, failed, and rejected jobs retain no image. A completed mode-0600 JPEG remains only in the mode-0700 transient job directory and follows its four-hour/20-job cleanup boundary.
- `mjpg-streamer`, Motion, and RTSP remain disabled and untouched. No stream, daemon, listener, upload, audio capture, package, service change, or network exposure is added.
- No UVC camera was attached during development. The no-device path and artifact ACL are testable now; live image, cancellation, and capture resource acceptance remain deliberately pending hardware and consent.

### Verification

- Production verification passed 31 checks with 0 warnings, including malformed/extra-argument rejection, backend pre-job refusal, independent worker refusal, disabled/unchanged camera services and configurations, absence of JPEG/process/listener residue, and all prior workflows.
- Authenticated browser verification passed at 320 px, 390 px, and desktop widths. A transient allowlisted artifact downloaded successfully, `/etc/shadow` was denied, camera controls remained visibly hardware-gated, and no external request, runtime error, or horizontal overflow occurred.
- All 39 deployed project files matched source byte for byte; listener state matched the final pre-deployment backup and GL.iNet UI, LuCI, Tailscale, extroot, swap, and protected configuration remained healthy.

## 1.6.0 — 2026-08-09

### Added

- Phase 3B `radio.rtl433_snapshot` ACTION workflow using the already-installed `rtl_433` 20.11-2 and `rtl-sdr` 0.6.0-2 packages.
- Exact `0bda:2832`/`0bda:2838` hardware allowlist, validated server-derived USB serial selection, kernel-driver conflict refusal, and shared `rtl_sdr` job resource.
- Fixed 433.92 MHz, 250 kS/s, 20-second JSON sensor profile with explicit confirmation and hardware-aware disabled controls.
- Separate reviewed-ACTION registry and static guards for receiver/network/raw-output options.
- Dedicated receive/privacy/authorization documentation.

### Safety and current scope

- The backend refuses absent, ambiguous, unsafe-serial, or driver-claimed hardware before creating a job; the worker repeats the gate before opening a tuner.
- The worker loads `/dev/null` as the explicit configuration, saves no raw I/Q, creates no network output, starts no service/listener, and applies independent time/file/final-output limits.
- The existing `rtl_tcp` package configuration is UCI-disabled, remains untouched, and is now part of deployment's protected-configuration hash set.
- No reviewed dongle was attached during development. The no-device path is testable now; live decoding, cancellation, and measured resource acceptance remain deliberately pending hardware.

### Verification

- Production verification passed 29 checks with 0 warnings, including malformed/extra-argument rejection, backend pre-job refusal, independent worker refusal, unchanged `rtl_tcp`, closed port 1234, and absence of every reviewed radio client.
- Authenticated browser verification passed at 320 px, 390 px, and desktop widths with the module visibly `HARDWARE REQUIRED`, ACTION-styled controls disabled, no external request, no runtime error, and no horizontal overflow.
- All 39 deployed project files matched source byte for byte; GL.iNet UI, LuCI authentication, Tailscale, extroot, swap, and all protected configuration remained healthy.

## 1.5.0 — 2026-08-09

### Added

- First Phase 3 field workflow: `capture.lan_metadata_snapshot`.
- Fixed 20-second, 128-packet LAN metadata profile using the already-installed `tcpdump` 4.9.3.
- Explicit capture confirmation and SECURITY-styled controls in Tool Registry and Jobs & Reports.
- Capture-specific singleton, cancellation, interface-flag, output-size, and no-PCAP verification.
- Dedicated packet-capture threat model and operating documentation.

### Safety and privacy

- The browser cannot choose an interface, filter, executable, flag, duration, packet count, snap length, or output path.
- The worker independently requires the native LAN to be up on exactly `br-lan`.
- Capture is non-promiscuous and limited to ARP, ICMP, and IPv4 DHCP metadata with DNS lookup and payload dumping disabled.
- Output is decoded text under the existing mode-restricted `/tmp/ddk/jobs/` retention boundary; no PCAP is created.
- Packet replay, general capture, WAN, cellular, Tailscale, and all configuration mutations remain disabled.

### Verification

- Production verification passed 27 checks with 0 warnings, including fixed-filter compilation, malformed/extra-argument rejection, singleton enforcement, authenticated cancellation, a complete bounded capture, unchanged interface flags, output bounds, no PCAP artifact, and no remaining worker or `tcpdump` process.
- Authenticated browser verification passed at 320 px, 390 px, and desktop widths with both SECURITY controls enabled and styled, every local brand image loaded, no external request, no runtime error, and no horizontal overflow.
- The browser validator now waits for asynchronously inserted local images to finish loading before checking their exact dimensions, eliminating a single-core timing race without relaxing the assertion.
- All 39 deployed project files matched source byte for byte; GL.iNet UI, LuCI, Tailscale, extroot, swap, and protected configuration remained healthy.

## 1.4.0 — 2026-08-09

### Added

- Exact Digital Dropkick kick logo in the persistent console navigation and page header.
- Five page-specific, monochrome WebP scenes derived from existing website imagery.
- Website-aligned black, paper-white, silver, and restrained green design tokens.
- Compact photo-backed headers with top/bottom fades, technical grid texture, stronger hierarchy, and mobile-specific composition.
- Brand-system documentation with asset provenance and explicit size/request budgets.

### Safety and resources

- Every asset is project-owned and served by the existing `/luci-static/` path; there are no external requests, fonts, trackers, scripts, stylesheets, or services.
- The current page loads one scene plus the small logo; other page scenes are not requested.
- No backend action, ACL, listener, package, service, firewall, network, wireless, cellular, Tailscale, GL.iNet UI, extroot, or swap behavior changed.

### Verification

- Local validation, whitespace review, JavaScript syntax, asset budgets, and remote-reference scanning passed.
- Production verification passed 24 checks with 0 warnings after deployment.
- Authenticated Chrome checks passed every branded page at 320 px, 390 px, and desktop widths with local images loaded, 44-pixel mobile touch targets, visible keyboard focus, no external requests, no horizontal document overflow, and no runtime errors.
- The deployed project tree matched the source tree byte for byte; no DDK worker or listener remained active.

## 1.3.0 — 2026-08-09

### Added

- Sysfs-only serial attribution with VID:PID, USB parent, interface number, driver, and ownership state.
- Exact `MODEM RESERVED` classification for all four Quectel EC25-AF serial functions.
- Enabled `serial.inspect` INFO module; serial sessions remain disabled.
- Separate idempotent swap-autostart configurator with exact fstab before/after backups and hash-guarded rollback.
- Compact read-only post-reboot verifier for boot-critical appliance invariants.
- Password-free browser verification wrapper that creates and destroys a five-minute, DDK-only LuCI session.

### Safety

- Serial inspection never opens a port and never infers AT/GNSS/diagnostic roles.
- Unknown adapters remain unreviewed and cannot satisfy the generic serial class.
- Swap tooling never creates, initializes, resizes, stops, or directly activates swap; it adds only the explicitly approved named native fstab entry.
- No listener, daemon, package, firewall, network, wireless, cellular, Tailscale, GL.iNet UI, or extroot change.

### Verification

- Exact swap rollback/re-apply and idempotence proved on the target.
- Native swap boot activation proved after an authorized reboot and attended power cycle.
- Compact post-reboot verification passed 10 checks with 0 warnings; the comprehensive suite passed 22 checks with 0 warnings.
- Authenticated browser regression passed at 320 px, 390 px, and desktop with no runtime errors or document overflow.

## 1.2.1 — 2026-08-09

### Added

- Memorable `http://192.168.8.1/ddk` shortcut to the authenticated dashboard.

### Safety

- The shortcut is a content-free static redirect under `/www/ddk/`; it adds no listener, CGI handler, nginx rule, service reload, or authentication bypass.
- Deployment and rollback own only the exact shortcut file and retain the existing protected-configuration checks.

## 1.2.0 — 2026-08-09

### Added

- Bounded `cellular.snapshot` INFO job for the verified Quectel EC25-AF.
- Fixed read-only operating-mode, data-status, signal-info, and serving-system UQMI profile.
- Whitelisted ASCII snapshot output for modem identity, registration, roaming, PLMN, radio type, RSSI, RSRQ, RSRP, and SNR.
- Cellular action in the Tool Registry and Jobs & Reports page.

### Safety

- No browser-provided modem path, QMI action, flag, or argument.
- No IMEI, IMSI, ICCID, phone number, SIM content, APN/current settings, PIN/PUK, cell location, network scan, reset, raw AT/QMI, or cellular configuration mutation.
- No package, service, listener, network, firewall, GL.iNet UI, Tailscale, extroot, or swap change.

## 1.1.0 — 2026-08-09

### Added

- Reviewed `network.nmap_lan_discovery` SECURITY action with explicit browser confirmation.
- Server-derived `br-lan` scope validation: RFC1918 only and `/24` or smaller.
- Fixed Nmap host-discovery profile with no DNS or port scan, bounded rate/retries/time/output, single-scan concurrency, and DDK-owned cancellation.
- Local validation requires every enabled SECURITY action to appear in a separate exact review allowlist.
- Dependency-free authenticated Chrome verification for desktop and mobile layouts.

### Safety

- The browser cannot supply an Nmap target, interface, executable, flag, filename, or PID.
- No package, network, firewall, listener, service, Tailscale, GL.iNet UI, extroot, or swap change is part of this release.

## 1.0.0 — 2026-08-09

### Added

- Native top-level `Digital Dropkick` LuCI application.
- Authenticated standalone LuCI template compatible with the GL.iNet nginx front end's pre-existing missing `/ubus/` route.
- Mobile-first cyber-industrial dashboard and namespaced visual system.
- Live system, network, Tailscale, storage, memory, package, and hardware status.
- Modular JSON tool registry with hardware-aware states and disabled roadmap actions.
- Searchable/filterable package inventory for all installed packages.
- Nine bounded read-only INFO actions.
- Asynchronous DDK job framework with proof job, stop validation, output bounds, and cleanup.
- Sanitized transient DDK System Report with authenticated view/download workflow.
- Target-identity, backup, atomic install, verification, and rollback scripts.
- Architecture, target, security, hardware detection, module-addition, and roadmap documentation.

### Safety

- No packages installed or upgraded.
- No service activation or restart, listener, firewall rule, network address, Tailscale setting, GL.iNet proprietary UI file, or UCI configuration change; rpcd receives only its native ACL reload signal.
- Deployment is intentionally blocked when the required USB-backed swap file is inactive.
