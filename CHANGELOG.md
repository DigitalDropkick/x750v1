# Changelog

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
