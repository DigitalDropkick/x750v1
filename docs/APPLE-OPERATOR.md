# Apple Operator Mode

Version 2.1 replaces Apple identity plus SSH handoff as the primary browser workflow with five exact structured actions. This source remains undeployed; production stays on the accepted v2.0 baseline until Addam explicitly approves deployment.

## Reviewed target software

The GL-X750 was queried directly before implementation. No package was installed or changed.

| Native component | Exact target version | Role |
| --- | --- | --- |
| libimobiledevice utilities | 1.3.0 | Normal-mode identity, pairing, diagnostics, management, screenshot, and syslog |
| usbmuxd | 1.1.1 | Temporary normal-mode transport helper |
| libirecovery / `irecovery` | 1.0.0 | Recovery/DFU query and control |
| `idevicerestore` | 1.0.0 | IPSW update, erase, no-action, and reviewed advanced flags |

The builders follow the installed `--help` output, including the installed `idevicepair systembuid` spelling and the precise advanced flags advertised by `idevicerestore` 1.0.0.

## Target selection

Apple hardware must first pass the conservative USB classifier: vendor `05ac` plus an Apple mobile, recovery, or DFU descriptor.

- Normal-mode choices use a bounded sysfs serial identifier as the UDID. Immediately before execution, the worker starts its own temporary `usbmuxd`, runs `idevice_id -l`, and requires an exact line match.
- Recovery/DFU choices require a parseable ECID in the reviewed sysfs identity. The worker then requires `irecovery -i ECID -q` to succeed before executing the requested operation.
- Restore choices retain the selector type. Normal mode is passed as `-u UDID`; recovery/DFU is passed as `-i ECID`. The worker repeats the corresponding live preflight.

The GUI never guesses the first Apple device and never silently changes selectors. Normal, recovery, and DFU counts are reported separately so controls are enabled only for a compatible live mode.

## Structured actions

### `apple.mobile_diagnostics`

This action exposes ordinary native information workflows without an extra confirmation:

- `ideviceinfo`, including every domain listed by the installed help, optional key, simple mode, and XML plist output;
- current device name and device date;
- pairing validation, host ID, and system BUID;
- `idevicediagnostics diagnostics` with All, WiFi, GasGauge, or NAND;
- bounded lists of MobileGestalt keys;
- IORegistry planes and entries.

Unknown fields, absent UDIDs, unsupported enum values, control characters, and unbounded keys are rejected before a job is prepared.

### `apple.mobile_capture`

- `idevicescreenshot` produces an authenticated TIFF artifact up to 64 MiB. The worker requires a regular file and validates either big- or little-endian TIFF magic.
- `idevicesyslog` supports duration, message match, start/stop triggers, process include/exclude filters, quiet mode, and kernel/no-kernel selection from the installed 1.3.0 help. The text artifact is capped at 32 MiB.

Screenshot may truthfully fail when the connected device lacks the developer disk image required by Apple’s screenshot service. The console does not fake an image or auto-mount an unselected developer image.

### `apple.mobile_manage`

Target-bound confirmation is required for:

- pair and unpair;
- device rename;
- explicit or router-current time setting;
- shutdown, restart, and sleep;
- transition into recovery;
- simulated-location set and reset.

The review screen shows the exact UDID, operation, important values, and server-built invocation. Pairing records created by an authorized `pair` request are intentional device state; temporary helper processes are not persistent.

### `apple.recovery`

Read-only query and mode operations do not require nuisance confirmation. Command, file, limera1n payload, script, reset, and normal-mode transition do require an ECID-bound phrase.

Recovery commands are bounded literal arguments to the device protocol. They are never passed to a router shell. Files, payloads, and scripts must be authenticated sealed `apple_recovery_input` uploads and resolve to one exact DDK-owned path.

### `apple.restore`

The exact 1.0.0 executable supports:

- a sealed IPSW or its `--latest` signed-firmware workflow;
- update, full erase, or `--no-action` mode;
- plain progress and communication debug;
- custom firmware, Cydia signature service, baseband exclusion, TSS/SHSH fetch, ramdisk-only, personalized-component retention, pwned DFU, Restore-mode allowance, and an optional sealed AP ticket.

The backend always supplies `--no-input` only after the operator has completed the stronger DDK target-bound review. Every restore mode still requires confirmation because update can fail destructively and latest/no-action can consume substantial network and extroot resources.

IPSW uploads are limited to 12 GiB because the appliance has a roughly 28 GiB extroot, must retain a 100 MiB appliance reserve, and may need a second extraction/cache footprint. Uploaded IPSWs reserve the larger of 2 GiB or twice their actual sealed size, capped at 12 GiB; latest-firmware mode reserves 12 GiB. Free space is checked before upload, before job creation, and every five seconds during restore.

`idevicerestore` receives a fresh mode-0700 per-job extroot cache workspace. The cache is removed on completion, error, cancellation, or worker termination. A bounded authenticated `apple-restore.log` remains as the useful artifact when the job completes.

## Helper lifecycle and cancellation

Normal-mode jobs refuse to start if any live `usbmuxd` already exists. The Apple worker starts `/usr/sbin/usbmuxd -f -p` on demand, records only its own PID, and stops only that PID on every exit path. It does not enable a boot service. Recovery-only jobs do not start `usbmuxd`.

All Apple actions share the `apple_mobile` resource lock. Authenticated cancellation signals only a PID whose command line is one of the two exact DDK worker executables and contains the matching generated job ID. The Apple worker then terminates its native child, helper, workspace, and lock.

## Files and privacy

Uploads, screenshots, syslogs, restore logs, and workspaces stay below `/overlay/ddk-field-console` in generated paths. Browser values cannot provide a router path. rpcd download ACLs name only the three Apple artifact filenames below generated job directories.

Normalized job metadata contains the selected UDID/ECID and options because those are required for an auditable technician job. It does not contain firmware bytes, AP-ticket bytes, arbitrary filesystem paths, a pairing-record dump, or command output. Jobs and sealed inputs follow the common four-hour and 24-hour retention rules.

## Remaining native workflows

The following installed capabilities are not disguised as implemented:

- `irecovery --shell` needs an authenticated bidirectional PTY/session protocol, resize/input handling, idle timeout, and disconnect cleanup. A one-shot form/job cannot faithfully represent it.
- `idevicebackup2` backup/restore needs an isolated directory-to-archive format plus a secret input channel so encryption passwords never enter persisted options or command previews.
- crash-report collection needs directory packaging and an explicit policy for the tool’s default move/delete behavior.
- developer-image mounting needs two related sealed inputs (image and signature) plus compatibility validation; provisioning needs profile-specific artifact validation.
- `idevicedebug` requires a mounted compatible developer image and a controlled long-running application/debug session.

These workflows remain available through the authenticated SSH fallback, with their exact architectural requirements documented here. They are deferred for concrete transport/artifact reasons, not because they are powerful.

## Test status

Completed without an attached customer device:

- exact target versions and help inspected;
- Lua 5.1 planner tests for every action family, target rejection, unknown fields, confirmation, uploads, and workspaces;
- backend describe/executable integration from `/tmp`;
- temporary `usbmuxd` no-device failure and cleanup proof;
- no remaining Apple process, DDK resource lock, or port 27015 listener after testing.

Live normal-mode, recovery/DFU, screenshot, pairing, device-changing, restore, cancellation-under-load, and measured CPU/RAM acceptance remain pending approved Apple hardware, a non-customer test device or explicit authorization, and deployment approval.
