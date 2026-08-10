# Digital Dropkick Field Console Engineering Rules

## Project purpose

This repository builds the Digital Dropkick Field Console for the GL.iNet
GL-X750 (Spitz).

The Field Console is an authenticated professional field-service appliance
operated by an authorized technician.

Its purpose is to expose the useful capabilities of the software installed
on the appliance through a practical GUI while preserving the stability of
the router and preventing accidental damage to the appliance itself.

The GUI is not intended to be an artificially limited demonstration of the
installed tools. Whenever technically practical, it should provide useful
native tool functionality through structured controls.

## Target

- Device: GL.iNet GL-X750 (Spitz).
- OpenWrt 22.03.4.
- Target: `ath79/nand`, `mips_24kc`.
- Hardware budget: one QCA9533-class CPU core and about 121 MB RAM.
- Root filesystem uses extroot on `/dev/sda1`.
- Persistent swap is `/overlay/ddk-install.swap`.
- GL.iNet UI, LuCI authentication, networking, and Tailscale are operational
  infrastructure and must remain functional.
- The appliance has limited CPU and RAM. Prefer short-lived jobs and zero
  unnecessary idle resource use.

## Preserve the known-good appliance

Do not damage, replace, upgrade, or casually reconfigure the underlying
router merely to implement a Field Console feature.

Unless a task explicitly requires one of these changes:

- Never run `opkg upgrade`.
- Never use `--force-depends`.
- Never use `--force-overwrite`.
- Never replace GL.iNet/OpenWrt core libraries.
- Never replace SSL/libustream libraries.
- Never install mismatched kernel modules.
- Never factory reset the router.
- Never repartition or format extroot.
- Never delete or resize `/overlay/ddk-install.swap`.
- Never alter LAN, WAN, cellular, Wi-Fi, firewall, Tailscale, extroot, or swap
  configuration as a side effect of implementing an unrelated tool.
- Never modify GL.iNet proprietary UI files for this application.
- Never expose a new service to WAN merely to support the dashboard.
- Never enable ttyd or another general shell listener on WAN.
- Never reboot the router merely because an application change was deployed.

An operator-facing feature whose explicit purpose is to modify a network,
device, firmware image, attached target, interface, service, or configuration
may perform that operation after appropriate validation and operator
confirmation. That is different from silently changing the appliance as an
implementation side effect.

## Operator functionality policy

The Digital Dropkick Field Console is not restricted to read-only diagnostics.

Installed tools should expose their materially useful native functionality
through the GUI whenever technically practical.

Do not intentionally reduce a tool to a read-only, discovery-only,
metadata-only, fixed-profile, or SSH-handoff subset solely because the native
tool is capable of:

- changing a device;
- generating network traffic;
- scanning systems;
- capturing traffic;
- interacting with radios;
- opening a serial or hardware interface;
- debugging hardware;
- programming firmware;
- reading or writing storage;
- restoring or repairing a device;
- performing security testing;
- starting a temporary local helper process;
- or otherwise performing an ACTION, SECURITY, or DISRUPTIVE operation.

Classification communicates operational impact. It does not automatically
disable functionality.

Do not force the operator to leave the GUI and use SSH merely because an
operation is powerful.

Where practical, provide structured GUI controls for the real operation.

Examples include:

- target selection;
- interface selection;
- port or protocol selection;
- scan profile;
- timeout;
- packet count;
- capture format;
- baud rate;
- frequency;
- gain;
- sample rate;
- device mode;
- programmer;
- MCU/target type;
- read/write/verify operation;
- firmware or data-file selection;
- output format;
- and other legitimate native tool parameters.

The goal is:

**full useful operator functionality with controlled execution, not safety by
removing functionality.**

## Browser-to-backend security boundary

Preserve the existing authenticated LuCI architecture.

Every executable browser operation must map to a defined server-side action.

Structured browser parameters are allowed and encouraged.

The browser may provide legitimate operator selections such as:

- IP address;
- CIDR;
- hostname;
- interface;
- port;
- protocol;
- device identifier;
- serial device;
- baud rate;
- frequency;
- gain;
- timeout;
- count;
- mode;
- programmer;
- target family;
- filename or uploaded project-owned artifact;
- and other values required by the selected tool.

However:

- Never accept an unrestricted browser-supplied shell command.
- Never provide a generic browser shell.
- Never accept arbitrary shell fragments.
- Never concatenate unvalidated browser input into a shell command.
- Never use `eval` on browser input.
- Never treat a manifest string as executable shell syntax.
- Never allow a browser to select an arbitrary executable path.

Validate every supplied parameter server-side.

Validation should be appropriate to the value rather than artificially
restrictive.

Examples:

- IP/CIDR values should parse as IP/CIDR.
- Ports should be valid port numbers or validated port expressions.
- Interfaces should exist and match the expected interface class.
- Device nodes should exist and belong to the detected hardware.
- Enumerated modes should come from an explicit server-side set.
- Numeric values should have appropriate ranges.
- Paths should remain inside explicitly permitted project/job locations when
  the operation requires a file.
- Hardware-specific operations should verify that the selected hardware is
  actually attached.

Prefer constructing an argument vector from validated values.

Do not construct arbitrary shell text when direct argument execution can be
used.

If shell invocation is unavoidable on this OpenWrt target, every variable
component must first pass strict validation and be safely quoted. No raw
browser value may become executable syntax.

## Tool capability policy

Do not use a global rule that keeps all ACTION, SECURITY, or DISRUPTIVE
operations disabled.

Each tool should expose the functionality that is useful for legitimate field
work and that can be represented safely by the architecture.

A tool manifest may describe:

- INFO operations;
- ACTION operations;
- SECURITY operations;
- DISRUPTIVE operations;
- hardware requirements;
- supported options;
- confirmation requirements;
- concurrency/resource requirements;
- expected outputs;
- and UI controls.

An action being powerful is not sufficient reason to omit it.

If a native operation can be represented through validated structured
parameters and controlled execution, implement the operation rather than
replacing it with an SSH instruction.

SSH handoffs remain acceptable when:

- the native application is fundamentally interactive in a way the current
  GUI cannot reasonably represent;
- terminal behavior is essential;
- the operation depends on an external workflow that cannot safely be
  modeled yet;
- or implementation is explicitly deferred.

SSH should be the exception, not the default answer for advanced
functionality.

## Destructive and disruptive operations

Destructive functionality may be exposed when it is a legitimate capability
of the installed tool.

Examples include firmware write/erase, restore, device reboot, filesystem
write, interface reconfiguration, or similarly consequential operations.

For such actions:

- Clearly label the operational impact.
- Require explicit operator confirmation.
- Display the selected target before execution.
- Display important parameters before execution.
- Require hardware validation where relevant.
- Preserve backup/readback opportunities where the native workflow supports
  them.
- Surface native command output and errors.
- Do not silently substitute a different target or operation.
- Do not disable the entire feature merely because confirmation is required.

Do not invent excessive confirmations for ordinary read-only operations.

## Hardware operations

Hardware-aware modules should distinguish:

- software installed;
- hardware detected;
- hardware ready;
- hardware busy;
- unsupported or ambiguous hardware;
- and no hardware attached.

Hardware detection should prevent accidental operation on the wrong device,
not prevent legitimate use of supported hardware.

When multiple devices are present and the native tool supports selecting one,
provide an operator selection mechanism rather than globally disabling the
tool.

Do not assume that the first `/dev/ttyUSB*`, `/dev/video*`, USB device, CAN
interface, programmer, storage device, or radio is necessarily the intended
target.

Preserve the router's own EC25 modem and other appliance hardware from
accidental use by unrelated modules.

## Jobs

Continue using the existing `/tmp/ddk/` transient job architecture where it
fits the operation.

Jobs should normally have:

- an action ID;
- validated arguments;
- status;
- PID/worker identity;
- stdout;
- stderr;
- creation time;
- bounded or intentionally configured retention;
- cancellation where meaningful;
- and hardware/resource ownership where appropriate.

Keep protection against stopping arbitrary system PIDs.

A stop action must only stop a process that belongs to the corresponding DDK
job or its validated child process tree.

Concurrency limits should prevent resource exhaustion or hardware conflicts,
not arbitrarily prevent valid workflows.

Tool-specific jobs may have different sensible timeouts and output limits.
Do not force every native tool into one tiny fixed profile.

## Files and artifacts

Tool workflows may legitimately need input or output files.

When adding file functionality:

- Keep project-managed temporary artifacts in a controlled DDK location.
- Validate filenames and paths.
- Prevent directory traversal.
- Do not permit arbitrary reads of router files through the browser.
- Do not permit arbitrary writes to router filesystem locations.
- Preserve appropriate file permissions.
- Use authenticated download/upload paths.
- Make retention policy clear.
- Allow useful operator downloads when the underlying tool produces a useful
  artifact such as PCAP, firmware backup, report, image, log, or capture.

Do not eliminate native tool output formats solely because they create a file.

## Services and daemons

The appliance should remain quiet when idle.

Avoid adding permanent daemons merely for dashboard convenience.

Specialized tools that only need to run during an operator workflow should be
started on demand and stopped afterward.

Existing intentionally disabled optional services should not be re-enabled at
boot merely because their package is present.

If a native tool requires a temporary helper service, it may be started for
the job when appropriate and shut down afterward.

Do not expose temporary listeners to WAN unless the operator explicitly
requests a workflow whose purpose requires that exposure and the change has
been deliberately designed.

## Resource usage

This is a small single-core router.

Prefer:

- native LuCI;
- Lua 5.1;
- shell;
- rpcd;
- ubus;
- dependency-free or small JavaScript;
- short-lived processes;
- streamed or bounded output;
- and on-demand execution.

Avoid:

- Node/npm runtime on the router;
- external CDNs;
- databases;
- heavy frameworks;
- permanent polling daemons;
- unnecessary background services;
- and unnecessary package installation.

Idle Field Console CPU usage should remain effectively zero.

Persistent memory overhead should remain minimal.

High CPU during an intentionally active scan, capture, decode, compression,
programming, or analysis job is acceptable if it reflects the requested
operation and returns to normal afterward.

## GUI policy

Preserve the existing Digital Dropkick visual identity and responsive layout.

The GUI should favor technician usability.

For each tool, expose controls that correspond to the actual native
capabilities that are useful in field work.

Prefer meaningful controls over a collection of fixed one-click demos.

Where useful, include:

- presets for common operations;
- advanced options;
- live detected hardware;
- target selection;
- command/operation summary before execution;
- job progress;
- stdout/stderr;
- artifacts/downloads;
- cancellation;
- and concise contextual help.

Do not hide useful functionality merely to keep the interface visually simple.

Progressive disclosure is preferred: common controls first, advanced controls
available when needed.

## Native command visibility

It is acceptable and often useful to show the operator the equivalent native
command that the backend intends to execute.

Displayed command text is informational.

The server remains responsible for validating values and constructing the
actual invocation.

Do not execute arbitrary text copied from a browser command preview.

## Existing functionality

Do not regress existing working v2 functionality while expanding tool
capabilities.

Preserve unless deliberately changing the relevant feature:

- `/ddk`;
- LuCI authentication;
- GL.iNet UI;
- extroot;
- active swap;
- Tailscale;
- package inventory;
- hardware detection;
- USB identity logic;
- jobs;
- reports;
- camera artifacts;
- responsive UI;
- rollback;
- deployment validation;
- and existing tested actions.

Refactor shared infrastructure when doing so clearly improves the ability to
support many real tool operations, but avoid unnecessary unrelated rewrites.

## Implementation approach

When adding or expanding a tool:

1. Inspect the exact installed binary and version on the target when needed.
2. Inspect its native help/output rather than assuming upstream syntax.
3. Determine which operations are useful for field work.
4. Model those operations using structured controls.
5. Define server-side validation for every parameter.
6. Implement an exact backend action.
7. Implement worker behavior if asynchronous execution is appropriate.
8. Add hardware/resource validation if needed.
9. Add confirmation for genuinely destructive/disruptive actions.
10. Preserve meaningful native output.
11. Add cancellation where meaningful.
12. Add relevant verification.
13. Test that idle state returns to normal after the operation.
14. Document only real limitations that remain.

Do not begin with the assumption that advanced functionality must remain
disabled.

## Testing

Maintain strong testing and rollback discipline.

Before edits:

- inspect `git status`;
- preserve unrelated work;
- identify the current known-good version.

After edits, run applicable:

- shell syntax validation;
- Lua syntax validation;
- JavaScript syntax validation;
- JSON validation;
- backend action validation;
- input rejection tests;
- traversal/injection tests;
- job identity tests;
- hardware detection tests;
- responsive browser tests;
- router deployment verification;
- resource cleanup tests;
- rollback verification.

Tests should validate safety boundaries without encoding unnecessary
functional restrictions.

A validation test should not fail merely because an ACTION, SECURITY, or
DISRUPTIVE operation has been intentionally implemented.

Update old tests when their only purpose was to enforce the previous
"disabled in GUI / use SSH instead" policy.

## Deployment and rollback

Back up every existing target file before replacement.

Maintain tested rollback tooling.

Deployment must continue to validate the expected target before modifying
router files.

Do not perform unrelated package upgrades or router configuration changes
during deployment.

Do not reboot unless the change truly requires it or the operator explicitly
requests a reboot.

Review the final diff before deployment.

After deployment report:

- what changed;
- what was tested;
- current limitations;
- operational impact;
- and rollback path.

## Git discipline

Inspect `git status` before edits.

Preserve unrelated work.

Make coherent commits.

Do not push, merge, tag, or release unless explicitly instructed.

Do not rewrite unrelated history.

Do not silently overwrite operator changes.

## Guiding principle

Protect the appliance through authentication, validation, target selection,
resource control, confirmations, isolation, rollback, and careful engineering.

Do not protect the operator from legitimate capabilities by removing those
capabilities from the GUI.

The Field Console should make the installed professional toolset more usable,
not less capable.
