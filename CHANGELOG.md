# Changelog

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

- Local shell, JavaScript, JSON, action-registry, mutation, CAN transmit/configuration prohibition, asset, and size validation passes.
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
