# Changelog

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
