# Android ADB Operator Mode

## Status and exact target

Version 2.1 adds two structured actions for the installed `/usr/bin/adb` 1.0.32:

- `android.adb_diagnostics` (`ACTION`)
- `android.adb_manage` (`DISRUPTIVE`)

The exact target `adb help` and `adb version` output were inspected on the GL-X750, and the structured workflow is deployed in production. No reviewed Android device was attached during development or production acceptance, so live device operation, consent prompts, transfer performance, and cancellation remain hardware-acceptance items.

## Target selection and server lifecycle

The ordinary identity action remains a bounded sysfs-only privacy view. Opening an ADB Operator form separately performs live transport discovery and correlates each transport with a reviewed USB device exposing ADB interface signature `ff:42:01`. A vendor match alone and uncorrelated TCP/emulator transports are not selectable.

DDK never uses ADB's `-a` flag. Each discovery or job:

1. acquires the shared ADB resource lock and refuses DDK-reserved port 5038 if already occupied;
2. starts ADB with `-P 5038`, which the inspected target binds to `127.0.0.1`;
3. selects one exact correlated serial with `-s`;
4. tracks the native child and applies the reviewed wall/file limits;
5. runs `adb -P 5038 kill-server` on completion, failure, or cancellation;
6. rejects the job if a listener remains.

No ADB daemon is enabled at boot and no idle DDK process or listener is added.

## Diagnostics and artifacts

The diagnostics action exposes:

- `get-state`, `get-serialno`, and `get-devpath`;
- fixed `shell getprop [VALIDATED_PROPERTY]`;
- fixed `shell pm list packages` with reviewed scope/path/filter values;
- bounded logcat with installed format/filter/count syntax;
- bugreport;
- one validated absolute Android path pulled to fixed `android-pull.bin`;
- ADB backup selection for APK/OBB/shared/all/system/package options.

These ordinary diagnostic/read workflows do not require a nuisance confirmation. The target and normalized native invocation are still shown before start. ADB backup may require device-side confirmation depending on the attached Android release.

Fixed authenticated artifacts live below `/overlay/ddk-field-console/artifacts/<job-id>/`, not RAM-backed `/tmp`:

| File | Ceiling and validation |
| --- | --- |
| `android-logcat.txt` | 8 MiB regular non-symlink file |
| `android-bugreport.txt` | 256 MiB regular non-symlink file |
| `android-pull.bin` | 256 MiB regular non-symlink file; directory pulls are rejected |
| `android-backup.ab` | 1 GiB, non-empty, `ANDROID BACKUP` header |

Files larger than 16 MiB use native authenticated LuCI download streaming instead of being buffered as a browser JavaScript blob.

## Device-changing operations

The management action exposes:

- push one sealed DDK input to one validated absolute Android path;
- install one sealed `.apk` with replace/test/downgrade/external flags supported by ADB 1.0.32;
- uninstall one validated package ID with optional data retention;
- restore one sealed `.ab` backup;
- reboot to normal, bootloader, or recovery;
- root, remount, USB mode, and TCP mode with a validated port.

Every management plan requires the operator to type a server-generated phrase containing the exact serial, operation, and material target. The worker rechecks the selected serial in `device` state immediately before execution.

Push, install, and restore accept only generated sealed-upload IDs. The browser never supplies a router path. The backend locks and revalidates the upload at job start, resolves one exact `@UPLOAD@` placeholder, and writes private input metadata at mode 0600. The worker checks the DDK directory, kind, closed upload sentinel, regular-file mode/size, exact argv reference, and SHA-256 again before ADB can read it.

## Deliberately unavailable native families

These omissions have concrete representation or lifecycle reasons rather than a risk-class ban:

- Arbitrary `adb shell` and emulator-console text would be a generic remote web shell. Only the fixed `getprop` and package-list token sequences are built.
- `adb sync` expects an Android product-output tree and can write system/vendor/data partitions; the sealed single-file input model cannot faithfully represent that tree.
- `install-multiple` requires a reusable ordered multi-upload selector and one atomic multi-file binding. The current schema supports one sealed APK and must not pretend an `.apks` archive is accepted by native `adb install`.
- Forward/reverse socket changes need a separate endpoint-spec validator, conflict inventory, and cleanup/reversal contract so DDK does not leave device or router forwarding state behind.
- `adb connect`/`disconnect` would operate on non-USB network targets, while the current authorization model deliberately requires live USB/sysfs correlation and kills the temporary server after each workflow. A future authorized-target registry plus bounded connection session is required.
- ADB 1.0.32's inspected help does not advertise `sideload`; DDK does not assume newer upstream syntax.
- `adb ppp` needs tty, network-route, process, and rollback controls beyond this action family.
- Fastboot is genuinely absent from the target and no substitute is installed.

The fallback SSH reference remains available for native families that are not yet representable, but it is no longer the primary Android interface.

## Validation evidence

Local validation covers manifest/review-list consistency, exact backend and worker mappings, unknown-field and package/path rejection, fixed argv construction, artifact ACLs, sealed inputs, confirmation, and browser hardware gating. Target-safe source tests on the router's Lua 5.1 stack proved diagnostic/install/backup argv construction, upload and extroot binding, traversal and trailing-dot package rejection, and arbitrary-shell rejection. The staged worker accepted the exact backup plan through its independent validator, rejected a nonexistent target, rejected forged shell/traversal argv before execution, and removed its listener/server and failed extroot artifacts before exit.

No production file was changed during those tests.
