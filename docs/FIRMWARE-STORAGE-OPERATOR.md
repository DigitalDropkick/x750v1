# Firmware and Storage Operator Mode

Phase 3 of Field Console 2.1 replaces the firmware SSH-only handoff and storage placeholder with nine exact structured actions. The browser submits typed values; `operator-phase3.lua` rejects unknown or invalid fields and returns a literal argv plan; `ddk-console` seals that plan to a one-time request; and `ddk-phase3-worker` independently revalidates the selected hardware, native version, sealed inputs, output paths, resource ownership, and cancellation state immediately before execution.

No action accepts a command string, executable path, OpenOCD Tcl, arbitrary config file, or router filesystem path.

## Exact target software

The implementation was built from help/version output on the GL-X750, not current upstream assumptions:

| Family | Exact installed runtime |
| --- | --- |
| JTAG/SWD | OpenOCD `0.11.0-v0.11.0-1-OpenWrt` |
| AVR | AVRDUDE `6.3` |
| USB DFU | dfu-util `0.11`; dfu-programmer `0.7.2` |
| Serial programming | STM32Flash package `0.6`; BOSSA `1.9.1`; LPC21ISP `1.97` |
| Drive health/filesystem | smartctl `7.2`; e2fsprogs `1.46.5` |
| Imaging/recovery | BusyBox `1.35.0` dd/tar/cmp; unsquashfs `4.5` |

The package database contains `flashrom-usb 1.2-2`, but no executable is installed. DDK reports flashrom unavailable and does not install a substitute. `ftdi_eeprom` is installed, but its reviewed help does not define a safe complete config grammar and its config can contain paths. Exposing it requires a future action-owned config serializer; arbitrary config upload is not accepted.

## Firmware actions

### `firmware.openocd`

The form selects one live reviewed debug adapter, one installed OpenOCD board config or installed interface/target pair, adapter speed, probe/program, sealed image, optional load address, verify, reset, and wall timeout. Browser input cannot name a config path. The server lists only files below the installed OpenOCD script tree.

The worker generates its own command file, disables GDB/Tcl/Telnet ports, binds OpenOCD to the exact USB topology with the installed `adapter usb location` command, and generates only probe output or `program` with optional address/verify/reset. Program requires a target- and upload-bound confirmation. Generic OpenOCD readback is not exposed because its flash-bank/address/length commands are target-specific; a future target-family schema is required for reliable readback.

### `firmware.avrdude`

The form uses the programmer and part identifiers parsed from this installation's `-c '?'` and `-p '?'` output. It supports probe, flash/EEPROM read, verify, write, and chip erase, plus serial baud, bit clock, formats, auto-erase/verification/signature behavior, verbosity, and timeout. Read creates a fixed HEX or binary backup artifact. Verify/write accepts one sealed firmware image. USB programmers use their stable serial descriptor when available; an ambiguous multi-programmer USB inventory without stable serials is rejected.

### `firmware.dfu`

The form selects a live USB device that currently exposes a DFU interface. dfu-util supports upload/read, download/write, and detach with VID:PID, topology, optional serial, alternate setting, DfuSe address/size, transfer size, reset, and timeout controls. dfu-programmer uses its exact installed target list and supports read, flash, erase, launch, and information fields with bus/address targeting. Writes, erase, detach, and launch require exact target confirmation; reads produce a fixed authenticated binary artifact.

### `firmware.serial`

Only live reviewed non-EC25 `/dev/ttyUSB*` or `/dev/ttyACM*` nodes are selectable. STM32Flash exposes info, bounded read, write/verify, erase, CRC, and go. BOSSA exposes info, bounded read, write, verify, erase, reset, security, and boot-source controls. LPC21ISP exposes its installed program/verify/wipe/control behavior; that binary has no readback operation. Consequential operations require target/material confirmation. The worker independently rejects all Quectel EC25 ports and rechecks the exact USB topology and VID:PID attribution.

## Storage actions

The backend derives block targets from sysfs. Only USB-attributed `sdX` disks/partitions are considered. Any disk backing `/`, `/rom`, `/overlay`, `/mnt/extroot`, or active swap is excluded. The worker repeats the block type, USB ancestry, mount, swap, size, and exact-argv target checks immediately before execution.

### `storage.inspect`

Whole non-system disks support SMART identity, health, attributes, extended data, short/long test start, and test abort with an explicit transport selector. Unmounted ext2/3/4 partitions support read-only e2fsck. Unmounted targets support read-only badblocks with block-size, stop-count, timeout, and fixed list artifact controls. Ordinary inspection does not require confirmation.

### `storage.repair`

Unmounted ext2/3/4 targets support e2fsck preen or assume-yes repair. Unmounted media supports badblocks non-destructive read/write testing with bounded passes. Both change target state and require confirmation containing the exact device, operation, and observed size.

### `storage.image` and `storage.restore`

Imaging uses BusyBox dd byte-count flags with operator-selected source offset, length, block size, error continuation, direct input choice, timeout, and optional SHA-256 companion artifact. It writes only `storage-image.raw` in the job's DDK extroot artifact directory. The reviewed family ceiling is 16 GiB, and the selected range must fit the exact source size.

Restore consumes one sealed `storage_image`, validates its size and SHA-256 again in the worker, supports destination offset/block size/direct output, and writes only to the selected unmounted non-system block target. Confirmation binds destination, observed size, upload ID, and SHA-256. Optional byte comparison is available for offset zero. The worker flushes through native dd behavior, monitors cancellation/free space, and reports compare mismatch as failure.

### `storage.squashfs`

File-only stat, numeric long listing, and extraction use one sealed `.squashfs`, `.sqfs`, or other accepted storage-image input. Extraction accepts only relative, non-traversing exact paths, one processor, bounded queues, a DDK-owned workspace, and an operator-selected 1 MiB–8 GiB output ceiling. Recovered content is packaged as a fixed authenticated tar artifact, then the workspace is deleted on success, failure, or cancellation.

## Resource and artifact behavior

- Firmware actions share the `firmware` resource lock; storage operations lock the physical disk; SquashFS recovery has its own singleton resource.
- At most two DDK jobs run concurrently, subject to action/resource singletons.
- Sealed inputs use generated IDs, mode `0600`, fixed DDK paths, declared kind/size, SHA-256 binding, retention, and per-upload locks.
- Artifacts use only registered names below the matching `/overlay/ddk-field-console/artifacts/job-*` or `/tmp/ddk/jobs/job-*` directory and exact rpcd download ACLs.
- Workers track their native PID, respond to authenticated cancellation, remove partial artifacts/workspaces, and release only locks they own.
- Native runs enforce the plan's declared artifact/workspace ceiling while output is being produced and stop before violating the 100 MiB extroot reserve. No helper daemon, boot service, firewall rule, or persistent listener is created.

## Acceptance boundary

The planner suite uses synthetic inventories to test all nine schemas, literal argv, confirmations, input/artifact/workspace bindings, range checks, unknown fields, system-target rejection, and traversal rejection. Target verification safely exercises schemas, exact versions, the active-extroot exclusion, and an independent no-device worker failure/cleanup path. Live read/write/erase acceptance remains pending an approved attached programmer/target or non-system customer media; production verification must not mutate unattached or unapproved hardware.
