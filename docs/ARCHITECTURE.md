# Architecture

## Goals

The Field Console is an authenticated, on-demand LuCI application with zero custom idle processes. It turns installed software and currently detected hardware into a coherent appliance view without starting services or modifying operating configuration.

## LuCI integration

The target's installed LuCI 23.119 applications establish the native pattern:

1. `/usr/share/luci/menu.d/ddk-field-console.json` creates `Digital Dropkick` below the authenticated `admin` tree.
2. The menu renders `/usr/lib/lua/luci/view/ddk/shell.htm`, a standalone authenticated template that avoids this firmware's broken nginx `/ubus/` route.
3. Shared dependency-free JavaScript and namespaced CSS live in `/www/luci-static/resources/ddk/`.
4. `/usr/share/rpcd/acl.d/ddk-field-console.json` permits execution only of the fixed DDK helper and read access only to exact DDK artifact-name patterns through the already-installed authenticated LuCI `cgi-io` paths.

Static LuCI assets contain no secrets. All live information and executable behavior remain behind the existing LuCI session boundary. `/www/ddk/gl_home.html` is a content-free static redirect to the authenticated overview, providing the memorable `/ddk` path without a CGI handler, port, nginx rule, uhttpd rule, or firewall rule.

## Presentation layer

The visual system remains a thin native layer: one namespaced stylesheet, one dependency-free client, the existing LuCI template, and optimized files below `/www/luci-static/resources/ddk/brand/`. The header selects a page image from a fixed client-side table; no URL or asset path comes from browser input. Each page requests only its selected scene and the shared logo.

The public website supplied the visual vocabulary and source imagery, not runtime code. The console contains no Astro output, analytics, tracking pixel, external font, CDN URL, media iframe, or website dependency. CSS gradients provide the technical grid and top/bottom image fades without animation or an idle process. See [BRAND-SYSTEM.md](BRAND-SYSTEM.md).

## Backend

`/usr/libexec/ddk-console` is a short-lived Lua 5.1 program. LuCI launches it only in response to an authenticated request. It:

- accepts a small command vocabulary;
- rejects unknown verbs, action IDs, job IDs, report IDs, and extra arguments;
- accepts versioned structured values only for exact Operator Mode action IDs;
- loads `operator-actions.lua`, which validates/normalizes values and constructs literal argv arrays without executing commands;
- reads procfs/sysfs and fixed system commands;
- loads and validates tool manifests;
- loads the fixed `usb-identity.lua` classifier for bounded sysfs-only mobile/programmer attribution;
- returns bounded JSON;
- starts only fixed action-to-worker-to-executable mappings;
- never accepts an executable path or shell fragment from the browser.

Legacy INFO/fixed-profile helpers use source-owned command strings. Operator Mode browser values pass through type, character, range, target, and live-choice validation before an action-specific builder may place them into one literal argv element. No browser value is evaluated as Lua, interpreted as a path, or concatenated into shell syntax. See [OPERATOR-MODE.md](OPERATOR-MODE.md).

## UI pages

- **Overview:** system, network, Tailscale, hardware, safe INFO actions, and capability summary.
- **Tool Registry:** hardware-aware modules, Operator Mode controls, and not-yet-migrated actions.
- **Package Inventory:** all installed packages with search, type filters, and bounded rendering controls.
- **Jobs & Reports:** asynchronous proof, system reports, structured native workflows including Android ADB, existing hardware snapshots, polling, DDK-owned stop, report view/download, and authenticated artifact download.
- **Settings:** security posture, operating limits, and authenticated DDK-controlled input staging. It intentionally changes no appliance configuration.

## Tool registry

Each module is one JSON document below `/usr/share/ddk-field-console/tools/`. The backend validates required fields and treats `status_probe` as a symbolic probe name, never executable code.

Hardware and software are reported separately:

- `software.installed`: at least one named package or expected binary exists.
- `hardware.required`: manifest declares a hardware class.
- `hardware.present`: all declared hardware classes are detected.
- `state`: derived as `UNAVAILABLE`, `HARDWARE REQUIRED`, `READY / NO DEVICE`, `NOT CONFIGURED`, or `READY`.
- `console_enabled`: whether the module has intentionally wired console behavior.

Not-yet-migrated actions remain visible as roadmap entries. The manifest cannot create an executable action by itself; Operator Mode also requires a schema/builder, exact backend mapping, worker, review-list entry, GUI, and tests. Risk class does not make an otherwise reviewed action non-runnable.

## INFO action flow

1. The authenticated template client calls `/usr/libexec/ddk-console info <allowlisted-id>` using the same form-encoded request format as LuCI's `fs.exec_direct()` helper through `cgi-io`.
2. `cgi-io` applies the DDK access group and exact command ACL.
3. The helper checks argument count and performs an exact table lookup.
4. A fixed read-only command runs with a timeout and output limit.
5. The helper returns structured JSON for escaped text rendering.

Base INFO IDs are system refresh, interfaces, routes, USB, serial attribution, Tailscale, storage/mounts, memory/swap, and installed-package count. Version 2 adds three private identity renderers and three static supplemental native-reference renderers. They run synchronously because they only traverse bounded sysfs metadata or server-side constant text; they create no job and invoke no device-management utility. Both serial aliases use one sysfs-only renderer; neither opens a serial device.

## Mobile/programmer identity and fallback

`usb-identity.lua` inspects at most 64 USB devices and 16 interfaces per device. Android requires a reviewed vendor plus protocol/descriptor evidence; Apple requires `05ac` plus a mobile-mode descriptor; programmer identities use a conservative reviewed table. The status API receives counts/reasons only. Full records, including sanitized serial identifiers, are generated only after browser confirmation and exist only in the immediate authenticated response.

The companion `*.operator_guide` actions return static command references plus live `binary_exists()` readiness. Displayed commands are text, never a backend command string. They remain a v2 compatibility/fallback path. Android, Apple, firmware, and storage now have separate structured actions with correlated target selection, sealed inputs, artifacts/workspaces, confirmation, and dedicated workers. See [ANDROID-ADB.md](ANDROID-ADB.md), [APPLE-OPERATOR.md](APPLE-OPERATOR.md), [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md), [DEVICE-IDENTITY.md](DEVICE-IDENTITY.md), [SSH-TOOL-HANDOFFS.md](SSH-TOOL-HANDOFFS.md), and [OPERATOR-MODE.md](OPERATOR-MODE.md).

## Serial ownership model

The backend walks `/sys/class/tty` for `ttyUSB*` and `ttyACM*`, resolves each USB interface and parent, and records VID:PID, manufacturer/product, parent topology, interface number, and driver. Exact Quectel `2c7c:0125` functions using the `option` driver are classified `MODEM RESERVED`. Unknown adapters remain `UNREVIEWED SERIAL`; they do not satisfy the generic `serial` hardware class until a future explicit hardware allowlist approves them.

## Job system

Long work never occupies a LuCI request:

1. For an Operator Mode action, the client first obtains its server-owned schema and submits a versioned options envelope for validation.
2. The backend creates a mode-0700, five-minute, one-time prepared plan containing normalized options, a literal argv array, declared artifacts, locks, wall limit, target summary, and confirmation policy.
3. The client reviews the server-built plan and starts it by prepared ID. Consequential plans require the exact target-bound confirmation phrase.
4. The helper atomically claims the plan, rechecks its exact action/worker/executable mapping, enforces a maximum of two active jobs, and atomically acquires global/action/resource locks.
5. It creates `/tmp/ddk/jobs/<generated-job-id>/` with restrictive permissions, optionally creates the matching DDK extroot artifact directory and exact declared workspaces, resolves only registered fixed artifact/upload/workspace placeholders, and writes one literal argument per line.
6. One exact allowlisted worker (`/usr/libexec/ddk-job-worker`, `/usr/libexec/ddk-apple-worker`, or `/usr/libexec/ddk-phase3-worker`) is detached with stdin, stdout, and stderr disconnected from the LuCI request.
7. The worker independently rechecks its action, metadata, executable and material live target state, then atomically updates status while tracking the native child for cancellation.
8. The browser polls the helper for that generated job ID.

Limits:

- two concurrently active DDK jobs;
- one-time prepared plans with a five-minute lifetime;
- atomic global, per-action, and shared-resource locks with stale-owner recovery;
- 128 KiB stdout and 32 KiB stderr per job;
- 20 retained job directories;
- jobs older than four hours and reports older than 24 hours are eligible for cleanup;
- transient output only under `/tmp/ddk/`;
- only `TERM` may be sent, and only after PID, job directory, and worker command line all match.

The system includes an asynchronous read-only demo, a sanitized system-report task, and structured Nmap 7.91, tcpdump 4.9.3, iperf3 3.11, RTL-433 20.11, fswebcam 20140113, socat 1.7.4.1/stty 9.0, gpsdecode 3.23.1, Android, Apple, firmware-programming, and storage/recovery actions, plus the preserved passive CAN and cellular snapshots. Nmap supports validated targets and practical installed scan/output options without a `/24` clamp. tcpdump supports live interface selection, a validated one-element BPF filter, decoded/PCAP output, interface-state comparison, and PCAP validation. iperf3 supports client and temporary server workflows and revalidates server bind addresses immediately before launch. Firmware/storage use exact live USB/serial/block inventories, server-owned config/part choices, sealed images, and independent worker target/system-media gates. Each has its own wall/output/artifact controls and direct-child cancellation. Older fixed workers remain only for compatibility and regression coverage.

CAN and cellular retain their v2 fixed-profile implementations until migrated. Their current bounds and missing-hardware/runtime gates remain enforced; action classification does not prevent future structured expansion.

## Artifact handling

A completed job may advertise only action-declared, mode-restricted regular files with fixed names in its `/tmp` job directory or matching DDK extroot artifact directory. Extroot storage is mandatory when a declared ceiling exceeds 16 MiB, and start requires the full ceiling plus a 100 MiB free-space reserve. The backend requires completed state and validates each filename, storage class, kind, size, and per-action ceiling; workers additionally validate formats such as image/PCAP/ADB-backup magic or JSON. The browser validates the generated job ID and safe metadata-provided name, derives the exact storage-class path, then requests it from the existing authenticated `/cgi-bin/cgi-download` endpoint. rpcd ACLs match only reviewed job/name patterns; no generic `/tmp`, `/overlay`, or arbitrary file read is granted. Files never enter `/www`, reports, or a new listener. Cleanup removes matching extroot artifacts with job expiry, including orphans after reboot.

Authenticated input uses generated reservations below mode-0700 `/overlay/ddk-field-console/uploads/`. Native `cgi-upload` may write only an exact generated `payload.bin`; finalization atomically seals it under a non-uploadable name, closes the write path, verifies declared size and applicable archive magic, calculates SHA-256, and applies one-hour reservation/24-hour sealed retention with a 10-file ceiling. Consumers select upload IDs and must revalidate the sealed metadata. No browser-provided router path is accepted.

## Report handling

Reports are stored in `/tmp/ddk/reports/`, never `/www`. An authenticated helper call reads a strictly validated report ID; the browser may then view or download the returned text. Reports exclude configuration bodies, passwords, PSKs, private keys, tokens, peer lists, and logs likely to contain application data.

## Deployment files

The installer may create or replace only:

- `/usr/share/luci/menu.d/ddk-field-console.json`
- `/usr/share/rpcd/acl.d/ddk-field-console.json`
- `/www/luci-static/resources/ddk/*`
- `/www/ddk/gl_home.html`
- `/usr/lib/lua/luci/view/ddk/*`
- `/usr/libexec/ddk-console`
- `/usr/libexec/ddk-job-worker`
- `/usr/share/ddk-field-console/*`

It backs up each pre-existing target to `/root/ddk-backups/<timestamp>/`, records new files separately, installs atomically where practical, invalidates only LuCI's exact menu index cache file, and sends rpcd its native ACL reload signal. It does not touch the firmware's Lua module-cache directory or restart nginx, uhttpd, rpcd, or the router.

Persistent swap activation is deliberately separate from application deployment. The opt-in configurator owns only `/etc/config/fstab`, creates before/after checksummed backups, and writes one exact named UCI section. Its rollback refuses to overwrite later fstab changes. The existing `S11fstab`/`block mount` path performs activation on a later authorized boot; DDK adds no init script.

## Deliberate exclusions

- No package installation or upgrade.
- No service activation.
- No ttyd integration, browser shell, arbitrary-command transport, executable selector, or arbitrary native flag list.
- No network, firewall, wireless, cellular, Tailscale, or extroot mutation.
- No swapfile creation, initialization, resize, direct activation, or deactivation. The separately approved fstab entry is the only persistent swap configuration change.
- No generic command runner or PID kill endpoint.
- No arbitrary router filesystem read/write or upload destination; authenticated inputs are confined to generated DDK reservations.
- No Node, npm, Python server, frontend framework, telemetry, or external asset.
