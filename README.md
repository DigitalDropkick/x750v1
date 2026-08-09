# Digital Dropkick Field Console

Production-oriented LuCI control dashboard for the GL.iNet GL-X750 field appliance. Version 1.5.0 adds the first Phase 3 field workflow: an authenticated, non-promiscuous, fixed-profile LAN metadata snapshot using the already-installed `tcpdump`. Live health, inventory, branded responsive UI, bounded Nmap discovery, cellular and serial attribution, swap persistence, and the memorable `/ddk` shortcut remain intact—without adding a daemon or listener.

## Safety status

The source is designed for the exact discovered target documented in [docs/TARGET-ENVIRONMENT.md](docs/TARGET-ENVIRONMENT.md). Deployment refuses a model, architecture, OpenWrt, extroot, free-space, swap, LuCI, or UI preflight mismatch before changing router files.

At initial discovery on 2026-08-09, `/proc/swaps` reported no active swap. After extroot media migration, the swapfile was confirmed active; `deploy.sh` still refuses deployment whenever `/overlay/ddk-install.swap` is not active. The separate, explicitly approved `configure-swap-autostart.sh` adds only a native fstab boot entry. It does not create, initialize, resize, stop, or directly activate the swapfile. See [docs/SWAP-AUTOSTART.md](docs/SWAP-AUTOSTART.md).

Boot persistence was proven on the target on 2026-08-09: the compact post-reboot profile passed 10 checks with no warnings. Version 1.5 then passed 27 comprehensive production checks with no warnings plus authenticated browser checks at 320 px, 390 px, and desktop widths. The router remained dark after the earlier software reboot and required an attended physical power cycle; after startup, extroot and the configured swapfile activated normally.

## Architecture

- Native LuCI menu JSON, authenticated server template, and dependency-free JavaScript.
- Existing nginx/LuCI authentication and `cgi-io` execution boundary.
- Short-lived Lua 5.1 helper with an exact action allowlist.
- JSON tool modules with separate software and hardware state.
- `/tmp/ddk/` job/report framework with concurrency, size, age, and identity limits.
- Local, optimized brand assets only; no website runtime, tracker, external font, CDN, or network request.
- No package install, service, port, firewall rule, database, or router-side Node/Python runtime.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/BRAND-SYSTEM.md](docs/BRAND-SYSTEM.md), [docs/PACKET-CAPTURE.md](docs/PACKET-CAPTURE.md), and [docs/SECURITY.md](docs/SECURITY.md).

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

The validator checks shell syntax, JavaScript syntax, JSON, enabled-action allowlisting, forbidden package/config mutations, exact brand assets and budgets, absence of remote presentation references, general asset limits, and whitespace errors.

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

Verification covers identity, extroot, swap, installed files, locally served brand assets, Lua/shell/JSON syntax, live APIs, all INFO actions, injection rejection, generic-PID rejection, traversal rejection, asynchronous jobs, Nmap proofs, non-promiscuous LAN metadata capture and cancellation, the cellular privacy/read-only snapshot, system reports, GL.iNet UI, LuCI, dashboard route, Tailscale, protected configuration hashes, listener/worker absence, memory, disk, and recent errors.

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

- DISRUPTIVE actions and every SECURITY action except the separately reviewed, bounded `network.nmap_lan_discovery` and `capture.lan_metadata_snapshot` profiles are placeholders only.
- Nmap discovery accepts no browser target or flags. It is limited to host discovery on the server-derived private `br-lan` `/24`-or-smaller subnet, one active scan, and a 75-second wall limit.
- LAN metadata capture accepts no browser interface, filter, duration, filename, or flag. It observes only ARP, ICMP, and IPv4 DHCP metadata on server-derived `br-lan`, in non-promiscuous mode, for 20 seconds or 128 packets. It creates decoded text only and may expose transient local IP/MAC metadata to the authenticated operator.
- Cellular snapshot accepts no device, action, or argument. It is fixed to the verified EC25-AF on `/dev/cdc-wdm0`, uses four read-only UQMI queries, and excludes subscriber identifiers, phone number, SIM contents, APN, location, scans, and raw commands.
- Serial inspection reads sysfs metadata only. All four EC25 `ttyUSB` functions are `MODEM RESERVED`; no port is opened and no functional role is guessed.
- Tool hardware detection is conservative and documents ambiguity.
- Reports are transient across reboot and have a 24-hour cleanup horizon.
- The browser polls only active jobs; there is no router-side polling process.
