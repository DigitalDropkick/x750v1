# Digital Dropkick Field Console

Production-oriented LuCI control dashboard for the GL.iNet GL-X750 field appliance. Version 2.1 introduces Operator Mode: authenticated, structured native-tool workflows whose values are validated server-side and converted to literal argv arrays by exact action-specific builders. It does not expose a shell, executable selector, arbitrary router path, generic PID, or raw command endpoint.

The v2.1 migration currently provides practical Nmap 7.91, tcpdump 4.9.3, iperf3 3.11, RTL-433, UVC still, non-EC25 serial, GPS/GNSS, ADB 1.0.32, Apple normal/recovery/restore, firmware programming, and storage/recovery controls. These use validated target/interface/device selection, native options, cancellation, resource locking, review/confirmation where consequential, authenticated artifacts, and sealed file inputs. Existing v2.0 behavior remains intact while the remaining tool families are migrated incrementally.

## Safety status

The source is designed for the exact discovered target documented in [docs/TARGET-ENVIRONMENT.md](docs/TARGET-ENVIRONMENT.md). Deployment refuses a model, architecture, OpenWrt, extroot, free-space, swap, LuCI, or UI preflight mismatch before changing router files.

At initial discovery on 2026-08-09, `/proc/swaps` reported no active swap. After extroot media migration, the swapfile was confirmed active; `deploy.sh` still refuses deployment whenever `/overlay/ddk-install.swap` is not active. The separate, explicitly approved `configure-swap-autostart.sh` adds only a native fstab boot entry. It does not create, initialize, resize, stop, or directly activate the swapfile. See [docs/SWAP-AUTOSTART.md](docs/SWAP-AUTOSTART.md).

Boot persistence was proven on the target on 2026-08-09: the compact post-reboot profile passed 10 checks with no warnings. Burn One version 1.9 passed 35 comprehensive production checks with no warnings plus authenticated artifact and browser checks at 320 px, 390 px, and desktop widths. Burn Two version 2.0 passed 37 comprehensive production checks with no warnings and authenticated browser acceptance at 320 px, 390 px, and desktop widths. Positive/negative identity fixtures, no-device behavior, customer-identifier/report separation, full-CLI handoffs, source parity for all 40 deployed files, unchanged protected configuration/listener state, and zero residual device-tool processes were all proven. The router remained dark after the earlier software reboot and required an attended physical power cycle; after startup, extroot and the configured swapfile activated normally. Neither Burn One nor Burn Two requires a reboot.

Version 2.1 was deployed to the production GL-X750 on 2026-08-10 after the accepted v2.0 baseline was backed up. Comprehensive target verification passed 48 checks with no warnings; authenticated browser acceptance passed at 320 px, 390 px, and desktop widths; all 45 deployed files matched source byte for byte; protected configurations remained unchanged; and no DDK worker, operator-tool listener, or browser-proof upload remained. The full v2.0 rollback snapshot is `/root/ddk-backups/20260810T183331Z-field-console-v1`; the later UI-fix preinstall snapshot is `/root/ddk-backups/20260810T190440Z-field-console-v1`.

## Architecture

- Native LuCI menu JSON, authenticated server template, and dependency-free JavaScript.
- Existing nginx/LuCI authentication and `cgi-io` execution/download boundary.
- Short-lived Lua 5.1 helper with exact action-to-builder-to-worker-to-executable mappings.
- Versioned structured action envelopes, strict schemas, one-time prepared plans, and server-built literal argv arrays.
- JSON tool modules with separate software and hardware state.
- Dedicated conservative Lua USB-identity classifier with bounded sanitized fields.
- `/tmp/ddk/` prepared-action, lock, job, artifact, and report framework with concurrency, size, age, and identity limits.
- Local, optimized brand assets only; no website runtime, tracker, external font, CDN, or network request.
- No package install, service, port, firewall rule, database, or router-side Node/Python runtime.

See [docs/OPERATOR-MODE.md](docs/OPERATOR-MODE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/SECURITY.md](docs/SECURITY.md), [docs/ANDROID-ADB.md](docs/ANDROID-ADB.md), [docs/APPLE-OPERATOR.md](docs/APPLE-OPERATOR.md), [docs/FIRMWARE-STORAGE-OPERATOR.md](docs/FIRMWARE-STORAGE-OPERATOR.md), [docs/DEVICE-IDENTITY.md](docs/DEVICE-IDENTITY.md), [docs/SSH-TOOL-HANDOFFS.md](docs/SSH-TOOL-HANDOFFS.md), [docs/BRAND-SYSTEM.md](docs/BRAND-SYSTEM.md), [docs/PACKET-CAPTURE.md](docs/PACKET-CAPTURE.md), [docs/RTL433-RECEIVE.md](docs/RTL433-RECEIVE.md), [docs/CAMERA-SNAPSHOT.md](docs/CAMERA-SNAPSHOT.md), [docs/GPS-GNSS-SNAPSHOT.md](docs/GPS-GNSS-SNAPSHOT.md), and [docs/CAN-PASSIVE-CAPTURE.md](docs/CAN-PASSIVE-CAPTURE.md).

## Repository layout

```text
files/                 Exact project-owned router filesystem tree
scripts/               Local validation and remote install/verify/rollback logic
docs/                  Target, architecture, security, registry, and roadmap docs
deploy.sh              Validated one-connection deployment
verify.sh              Local checks plus remote production verification
rollback.sh            Restore a timestamped pre-deployment backup
configure-swap-autostart.sh  Add the exact approved native swap boot entry
rollback-swap-autostart.sh   Restore the exact pre-change fstab safely
post-reboot-verify.sh        Compact read-only boot validation
```

## Local validation

Requirements on the workstation: Bash, Git, Node (syntax only), jq, tar, and SSH.

```sh
./scripts/validate-local.sh
```

The validator checks shell and JavaScript syntax, JSON, action/manifests review lists, Operator Mode schemas/builders/workers, fixed executable mappings, parameter and artifact boundaries, identity-classifier limits, private-output declarations, forbidden package/config mutations, exact brand assets and budgets, absence of remote presentation references, general asset limits, and whitespace errors.

Lua 5.1 with the target's `nixio` and `luci.jsonc` modules is validated again on the router before the installer writes anything.

## Deployment

The target is intentionally fixed to `root@192.168.8.1`. Run from the repository root:

```sh
./deploy.sh
```

The script prompts for the router password through SSH. Do not place the password in an environment variable or command line.

Deployment performs:

1. local validation;
2. remote target and safety preflight;
3. staged router-side syntax/JSON validation;
4. timestamped backup to `/root/ddk-backups/<timestamp>-field-console-v1/`;
5. atomic installation of only allowlisted project files;
6. exact LuCI cache-file removal;
7. direct status/capability smoke tests.

The installer sends rpcd its native reload signal so it recognizes the new ACL. No service is restarted and the router is not rebooted.

## Dashboard

After deployment and normal LuCI login:

```text
http://192.168.8.1/ddk
```

The content-free shortcut immediately redirects to `/cgi-bin/luci/admin/ddk/overview`. Authentication remains entirely within LuCI; the shortcut exposes no dashboard data.

The top-level LuCI entry is **Digital Dropkick**.

## Verification

```sh
./verify.sh
```

Verification covers identity, extroot, swap, installed-file parity, locally served brand assets, Lua/shell/JSON syntax, live APIs, INFO actions, USB identity fixtures, private-data separation, injection/generic-PID/traversal rejection, asynchronous jobs, structured-envelope rejection, one-time prepared requests, Nmap loopback execution/artifacts, tcpdump loopback PCAP and invalid-BPF behavior, iperf3 temporary server/client cleanup, ADB schema/target/server-lifecycle rejection, legacy workflows, hardware/runtime gates, authenticated artifact ACL isolation, system-report exclusions, GL.iNet UI, LuCI, Tailscale, protected configuration hashes, listener/worker absence, memory, disk, and recent errors.

The authenticated visual page and mobile layout should also be opened after deployment. `scripts/verify-browser-authenticated.sh` creates a five-minute LuCI session with only the DDK access group, runs the dependency-free Chrome DevTools checks, and destroys that session on exit. It verifies every page-specific image, both logo placements, the exact local-only request boundary, 320 px and 390 px mobile layouts, desktop layouts, overflow, and runtime errors. It requires the same already-authenticated SSH control socket as deployment and never accepts, prints, or stores a password or persistent browser session. The lower-level `scripts/verify-browser.mjs` still accepts a transient session through `DDK_BROWSER_SESSION` for manual test orchestration.

After an explicitly authorized controlled reboot, run `./post-reboot-verify.sh`. It is intentionally much shorter than the full destructive-proof suite and checks only the boot-critical appliance invariants.

## Rollback

Use the latest successful deployment backup:

```sh
./rollback.sh
```

Or select the exact path printed by deployment:

```sh
./rollback.sh /root/ddk-backups/20260809T170000Z-field-console-v1
```

Rollback restores every pre-existing target file, removes only files recorded as newly created by this project, removes empty project directories, invalidates LuCI's exact menu index cache, and reloads rpcd ACLs. It does not factory reset, restart services, or touch UCI/network configuration.

Swap boot configuration has a separate hash-guarded rollback because it owns one production-sensitive file:

```sh
./rollback-swap-autostart.sh
```

## Adding tools

See [docs/ADDING-A-TOOL.md](docs/ADDING-A-TOOL.md). Adding a manifest cannot enable execution by itself.

## Known limits

- Operator Mode currently covers Nmap, tcpdump, iperf3, RTL-433, UVC still capture, non-EC25 serial, GPS/GNSS, Android ADB, Apple normal/recovery/DFU/restore, OpenOCD, AVRDUDE, USB DFU, serial bootloaders, SMART/e2fsck/badblocks, raw imaging/restore, and SquashFS recovery. Remaining manifests retain their v2 fixed/identity behavior until each exact installed tool is audited and migrated; `ACTION`, `SECURITY`, or `DISRUPTIVE` classification is not itself a reason to keep one disabled.
- The common request/resource limits—24 KiB structured envelopes, 64 explicit Nmap targets, two active jobs, five-minute one-time prepared plans, fixed artifact names, action-specific wall limits, and artifact ceilings—protect the 121 MiB single-core appliance. They do not clamp CIDR targets to `/24`, force one interface, or remove supported native output formats.
- Authenticated input staging reserves one DDK-owned extroot path, validates name/type/size/free-space, atomically seals the result, computes SHA-256, and applies one-hour reservation/24-hour sealed retention. ADB, Apple, firmware, raw restore, and SquashFS consumers bind and revalidate sealed IDs; storage images are bounded at 16 GiB by the extroot/resource model.
- RTL-433 now exposes reviewed tuner selection, receive frequency/sample/gain/PPM, decoder/analyzer/metadata choices, duration, decoded formats, and bounded raw I/Q artifacts supported by exact 20.11. Live RF acceptance remains pending an attached reviewed dongle.
- Camera still capture now exposes reviewed UVC-node selection and bounded native still parameters for exact fswebcam 20140113 with JPEG/PNG artifacts. Streaming, Motion, RTSP, audio, and network outputs remain disabled; live image/cancellation acceptance remains pending approved attached hardware and privacy consent.
- GPS/GNSS now exposes a reviewed non-EC25 receiver selector, bounded duration/bytes, gpsdecode mode/type options, position summary, and raw/decoded artifacts. `gpsd`, NTRIP, RTK corrections, receiver commands, and network access remain disabled; live fix/cancellation acceptance remains pending approved receiver hardware and privacy consent.
- Passive CAN accepts no browser interface, bitrate, filter, duration, frame count, command, flag, or output path. It requires exactly one already-up physical `canN` plus `/usr/bin/candump`, receives at most 128 frames in a fixed bounded profile, and verifies interface flags remain unchanged. Transmit, replay, interface setup, persistent logs, and package repair remain disabled. This router currently has no CAN interface and no `candump` payload, so live capture/cancellation acceptance remains pending approved hardware and runtime availability.
- Cellular snapshot accepts no device, action, or argument. It is fixed to the verified EC25-AF on `/dev/cdc-wdm0`, uses four read-only UQMI queries, and excludes subscriber identifiers, phone number, SIM contents, APN, location, scans, and raw commands.
- Serial Operator Mode exposes receive and confirmed transmit/receive settings only for reviewed general-purpose USB serial adapters. All four EC25 `ttyUSB` functions remain `MODEM RESERVED` and are independently rejected by backend and worker; no eligible adapter is currently attached.
- Android ADB 1.0.32 now exposes structured state/identity/property/package/logcat diagnostics, bugreport, pull, backup, push, APK install, uninstall, restore, reboot, root, remount, USB, and TCP-mode controls where represented by the reviewed action set. It uses only correlated USB ADB transports and a temporary localhost server on port 5038. Live device execution/cancellation remains pending an approved attached Android device.
- Apple Operator Mode uses libimobiledevice 1.3.0, usbmuxd 1.1.1, irecovery 1.0.0, and idevicerestore 1.0.0 for structured diagnostics, pairing/settings/power/location, screenshot/syslog, recovery/DFU, and IPSW update/erase/no-action workflows. Normal mode requires an exact freshly rediscovered UDID; recovery/DFU requires ECID; temporary usbmuxd and restore-cache workspaces are always cleaned up. See [docs/APPLE-OPERATOR.md](docs/APPLE-OPERATOR.md). Live device acceptance remains pending approved hardware.
- Firmware Operator Mode uses exact OpenOCD 0.11, AVRDUDE 6.3, dfu-util/dfu-programmer, STM32Flash, BOSSA, and LPC21ISP schemas with live reviewed target selection, installed config/part lists, backups, verification, writes/erase/boot controls, strong confirmation, and cleanup. Storage Operator Mode excludes system/extroot/swap media and provides SMART/read-only checks, confirmed repair, 16 GiB bounded imaging/restore, and isolated SquashFS recovery. See [docs/FIRMWARE-STORAGE-OPERATOR.md](docs/FIRMWARE-STORAGE-OPERATOR.md). Live hardware-changing acceptance remains pending an approved target.
- Android detection requires a reviewed mobile vendor plus ADB, fastboot, MTP, or mobile descriptor evidence. Apple detection requires `05ac` plus a mobile/recovery/DFU descriptor. Programmer detection uses a conservative exact/token table; new hardware may require a classifier addition.
- The installed fastboot and flashrom executables are unavailable despite the broader package inventory. The console reports live readiness and does not install substitutes.
- Tool hardware detection is conservative and documents ambiguity.
- Reports are transient across reboot and have a 24-hour cleanup horizon.
- The browser polls only active jobs; there is no router-side polling process.
