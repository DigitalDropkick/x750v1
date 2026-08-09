# Swap Autostart

## Scope

The approved Phase 2A change adds one native UCI section to `/etc/config/fstab`:

```text
config swap 'ddk_install_swap'
	option device '/overlay/ddk-install.swap'
	option enabled '1'
```

It does not create, resize, initialize, stop, or immediately activate swap. It does not run `block mount`, reload fstab, restart a service, alter extroot, or reboot. The already-active swap remains untouched while the boot configuration is written.

No priority is configured. The exact installed fstools parser represents priority as an unsigned value, while the kernel already reports the intended default priority of `-2` when the file is activated without an explicit preference.

## Why this is native to the target

The router's `/etc/init.d/fstab` is enabled as `S11fstab` and its `boot()` method runs `/sbin/block mount`. Inspection of the exact installed fstools commit `93369be040612c906bcbb1631f44a92fa4122d24` confirmed that:

- a `config swap` section accepts `enabled`, `device`, and `priority` fields;
- an absolute `device` value is retained as the swap target;
- a regular target whose probed type is `swap` is passed to `swapon()` during `block mount`.

This uses the firmware's existing boot mechanism and introduces no DDK init script or daemon.

## Configure

From the repository root:

```sh
./configure-swap-autostart.sh
```

The target is fixed to `root@192.168.8.1`. Before writing, the router script verifies the GL-X750 identity, OpenWrt version, extroot mount, active swap entry, exact file size/mode/owner/allocation/type, protected configuration hashes, and absence of a conflicting swap section.

It then backs up `/etc/config/fstab` under:

```text
/root/ddk-backups/<UTC timestamp>-swap-autostart/
```

The backup includes exact before/after copies, SHA-256 checksums, and metadata. Re-running the configurator is idempotent when the named section matches exactly.

## Rollback

Use the most recent swap backup:

```sh
./rollback-swap-autostart.sh
```

Or provide the exact backup printed by configuration:

```sh
./rollback-swap-autostart.sh /root/ddk-backups/20260809T170000Z-swap-autostart
```

Rollback first requires the live fstab hash to match the recorded post-change copy. This prevents an older backup from overwriting later operator changes. It then atomically restores the exact pre-change file and verifies UCI parsing, extroot, and the still-active swap. It never disables the currently active swap.

## Reboot proof

A reboot is intentionally outside the configuration script. After separately authorizing and performing a controlled reboot, run:

```sh
./post-reboot-verify.sh
```

The compact verifier proves that the named UCI entry is present and the swapfile was activated during boot, then checks version, `/ddk`, LuCI authentication, the GL.iNet UI, extroot, Tailscale, protected hashes, listeners, idle workers, memory, storage, logs, and EC25 serial attribution.

## Target validation record

Validation completed on 2026-08-09:

- configuration, exact rollback, re-application, and idempotence all passed while swap and extroot remained active;
- the software reboot passed its preflight and `sync`, but the router remained dark and required an attended physical power cycle;
- after startup, the named fstab entry was intact and `/overlay/ddk-install.swap` was automatically active at 262,140 KiB with priority `-2`;
- the compact post-reboot verifier passed 10 checks with 0 warnings;
- the comprehensive verifier passed 22 checks with 0 warnings;
- authenticated 320 px, 390 px, and desktop browser regression checks passed with no runtime errors or document overflow.
