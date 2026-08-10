# Architecture

## Goals

The Field Console is an authenticated, on-demand LuCI application with zero custom idle processes. It turns installed software and currently detected hardware into a coherent appliance view without starting services or modifying operating configuration.

## LuCI integration

The target's installed LuCI 23.119 applications establish the native pattern:

1. `/usr/share/luci/menu.d/ddk-field-console.json` creates `Digital Dropkick` below the authenticated `admin` tree.
2. The menu renders `/usr/lib/lua/luci/view/ddk/shell.htm`, a standalone authenticated template that avoids this firmware's broken nginx `/ubus/` route.
3. Shared dependency-free JavaScript and namespaced CSS live in `/www/luci-static/resources/ddk/`.
4. `/usr/share/rpcd/acl.d/ddk-field-console.json` permits execution only of the fixed DDK helper and read access only to validated camera artifacts through the already-installed authenticated LuCI `cgi-io` paths.

Static LuCI assets contain no secrets. All live information and executable behavior remain behind the existing LuCI session boundary. `/www/ddk/gl_home.html` is a content-free static redirect to the authenticated overview, providing the memorable `/ddk` path without a CGI handler, port, nginx rule, uhttpd rule, or firewall rule.

## Presentation layer

The visual system remains a thin native layer: one namespaced stylesheet, one dependency-free client, the existing LuCI template, and optimized files below `/www/luci-static/resources/ddk/brand/`. The header selects a page image from a fixed client-side table; no URL or asset path comes from browser input. Each page requests only its selected scene and the shared logo.

The public website supplied the visual vocabulary and source imagery, not runtime code. The console contains no Astro output, analytics, tracking pixel, external font, CDN URL, media iframe, or website dependency. CSS gradients provide the technical grid and top/bottom image fades without animation or an idle process. See [BRAND-SYSTEM.md](BRAND-SYSTEM.md).

## Backend

`/usr/libexec/ddk-console` is a short-lived Lua 5.1 program. LuCI launches it only in response to an authenticated request. It:

- accepts a small command vocabulary;
- rejects unknown verbs, action IDs, job IDs, report IDs, and extra arguments;
- reads procfs/sysfs and fixed system commands;
- loads and validates tool manifests;
- returns bounded JSON;
- starts only allowlisted DDK workers;
- never accepts an executable path or shell fragment from the browser.

The helper uses fixed command strings from server-side tables. Browser values can select a table entry but can never become a command.

## UI pages

- **Overview:** system, network, Tailscale, hardware, safe INFO actions, and capability summary.
- **Tool Registry:** hardware-aware modules and disabled future actions.
- **Package Inventory:** all installed packages with search, type filters, and bounded rendering controls.
- **Jobs & Reports:** asynchronous proof, system report, bounded Nmap discovery, cellular/radio/camera snapshots, polling, DDK-owned stop, report view/download, and authenticated camera-artifact view/download.
- **Settings:** read-only security posture and operating limits. It intentionally changes no configuration.

## Tool registry

Each module is one JSON document below `/usr/share/ddk-field-console/tools/`. The backend validates required fields and treats `status_probe` as a symbolic probe name, never executable code.

Hardware and software are reported separately:

- `software.installed`: at least one named package or expected binary exists.
- `hardware.required`: manifest declares a hardware class.
- `hardware.present`: all declared hardware classes are detected.
- `state`: derived as `UNAVAILABLE`, `HARDWARE REQUIRED`, `READY / NO DEVICE`, `NOT CONFIGURED`, or `READY`.
- `console_enabled`: whether the module has intentionally wired console behavior.

Disabled actions remain visible as roadmap placeholders. The manifest cannot create an executable action by itself; the backend allowlist must also implement the ID.

## INFO action flow

1. The authenticated template client calls `/usr/libexec/ddk-console info <allowlisted-id>` using the same form-encoded request format as LuCI's `fs.exec_direct()` helper through `cgi-io`.
2. `cgi-io` applies the DDK access group and exact command ACL.
3. The helper checks argument count and performs an exact table lookup.
4. A fixed read-only command runs with a timeout and output limit.
5. The helper returns structured JSON for escaped text rendering.

Phase-one INFO IDs are system refresh, interfaces, routes, USB, serial attribution, Tailscale, storage/mounts, memory/swap, and installed-package count. Both the overview alias and registry action use one sysfs-only renderer; neither opens a serial device.

## Serial ownership model

The backend walks `/sys/class/tty` for `ttyUSB*` and `ttyACM*`, resolves each USB interface and parent, and records VID:PID, manufacturer/product, parent topology, interface number, and driver. Exact Quectel `2c7c:0125` functions using the `option` driver are classified `MODEM RESERVED`. Unknown adapters remain `UNREVIEWED SERIAL`; they do not satisfy the generic `serial` hardware class until a future explicit hardware allowlist approves them.

## Job system

Long work never occupies a LuCI request:

1. The helper validates a job action and enforces a maximum of two active jobs.
2. It creates `/tmp/ddk/jobs/<generated-job-id>/` with restrictive permissions.
3. A fixed `/usr/libexec/ddk-job-worker` task is detached with stdin, stdout, and stderr disconnected from the LuCI request.
4. The worker atomically updates `status`, `pid`, `metadata.json`, `stdout`, and `stderr`.
5. The browser polls the helper for that generated job ID.

Limits:

- two concurrently active DDK jobs;
- 128 KiB stdout and 32 KiB stderr per job;
- 20 retained job directories;
- jobs older than four hours and reports older than 24 hours are eligible for cleanup;
- transient output only under `/tmp/ddk/`;
- only `TERM` may be sent, and only after PID, job directory, and worker command line all match.

The system includes an asynchronous read-only demo, a sanitized system-report task, bounded Nmap discovery, a non-promiscuous LAN metadata snapshot, hardware-gated RTL-433, UVC-camera, and GPS/GNSS snapshots, and a cellular snapshot. The Nmap task accepts no browser target or flags, permits one active scan, and tracks its child process for safe cancellation. The packet task accepts no browser arguments, requires server-derived `br-lan`, uses one fixed BPF profile, permits one active capture, compares interface flags before/after, emits only decoded text, and tracks its child for cancellation. The RTL-433 task requires exactly one reviewed VID:PID and safe sysfs serial, selects that serial directly, refuses a claimed driver or existing receiver, holds the shared `rtl_sdr` resource, and uses fixed receive/time/file/output controls. The camera task requires exactly one sysfs-attributed USB UVC camera and primary node, refuses an open device or enabled/running camera service, confirms V4L2 capture capability, holds the shared `camera` resource, and creates one bounded validated JPEG. The GPS task requires exactly one external USB GNSS identity and one exclusive reviewed serial node, excludes the EC25-AF, reads only a fixed byte/window ceiling, checksum-filters NMEA, and deletes raw input while holding the shared `gps` resource. The cellular task is fixed to the verified EC25-AF management node and four read-only UQMI actions; it parses only approved identity, registration, and signal fields into output.

## Camera artifact handling

A completed camera job may contain one mode-0600 `snapshot.jpg` below its mode-0700 job directory. The backend advertises the artifact only when the action ID, completed state, regular-file type, JPEG magic, and 256 KiB limit all match. The browser validates the generated job ID, derives the fixed path, and requests it from the existing authenticated `/cgi-bin/cgi-download` endpoint. The rpcd ACL matches only `/tmp/ddk/jobs/job-[0-9]*-[0-9]*/snapshot.jpg`; no generic `/tmp` or arbitrary file read is granted. The file never enters `/www`, JSON, a report, or a network listener. See [CAMERA-SNAPSHOT.md](CAMERA-SNAPSHOT.md).

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
- No ttyd integration.
- No network, firewall, wireless, cellular, Tailscale, or extroot mutation.
- No swapfile creation, initialization, resize, direct activation, or deactivation. The separately approved fstab entry is the only persistent swap configuration change.
- No generic command runner or PID kill endpoint.
- No Node, npm, Python server, frontend framework, telemetry, or external asset.
