# Adding a Tool Module or Operator Action

Tool manifests are data, not executable plugins. A manifest may render a card and declare an action, but it cannot select a program or make that action runnable. Operator Mode execution requires a separate exact schema, validator/argv builder, backend mapping, worker, GUI path, review-list entry, and tests.

## 1. Audit the exact target software

Before designing controls:

1. Confirm the package record and exact executable path on the GL-X750.
2. Record the installed version.
3. Inspect that binary's actual help and relevant runtime-discovery output.
4. Record hardware, device-node, service, port, memory, disk, and kernel dependencies.
5. Do not install a substitute merely because a payload is missing.
6. Separate real technical constraints from the old v2 fixed-profile policy.

The implementation must match what exists on OpenWrt 22.03.4/mips_24kc, not current upstream documentation.

## 2. Create or update one manifest

Add a lowercase JSON file below:

```text
files/usr/share/ddk-field-console/tools/
```

A migrated action resembles:

```json
{
  "id": "throughput",
  "name": "Throughput & Live Traffic",
  "category": "Network Diagnostics",
  "description": "On-demand native iperf3 client tests and temporary bounded servers.",
  "package_names": ["iperf3"],
  "expected_binaries": ["iperf3"],
  "required_hardware": [],
  "status_probe": "software",
  "risk_level": "ACTION",
  "enabled": true,
  "actions": [
    {
      "id": "throughput.iperf3",
      "class": "ACTION",
      "execution": "job",
      "parameter_schema": "operator-v1",
      "enabled": true
    }
  ],
  "help_text": "The backend validates structured options and constructs the exact native argv."
}
```

| Field | Rule |
| --- | --- |
| `id` | Unique lowercase module identifier. |
| `name` | Concise operator-facing label. |
| `category` | Existing taxonomy unless a deliberate product change adds one. |
| `description` | Material installed capability, not a placeholder promise. |
| `package_names` | Exact opkg names; any match establishes package presence. |
| `expected_binaries` | Exact binary names or paths; any match also establishes software presence. |
| `required_hardware` | Symbolic hardware classes only; empty means no special hardware. |
| `status_probe` | Symbolic allowlisted probe ID, never a command. |
| `risk_level` | `INFO`, `ACTION`, `SECURITY`, or `DISRUPTIVE`; classification does not itself disable execution. |
| `enabled` | Whether console behavior is deliberately wired. |
| `actions` | Exact descriptive IDs plus class and enabled state. |
| `actions[].execution` | `job` for asynchronous native work. |
| `actions[].parameter_schema` | `operator-v1` for the shared structured transport. |
| `help_text` | Honest current behavior, technical limits, and hardware state. |

Supported hardware symbols are `usb`, `serial`, `cellular_modem`, `video`, `rtl_sdr`, `can`, `bluetooth`, `i2c`, `spi`, `gps`, `android`, `apple_mobile`, `smartcard`, `programmer`, and `usb_storage`.

## 3. Add the schema and pure builder

Add the exact action to `files/usr/share/ddk-field-console/operator-actions.lua`. It must:

- describe reusable `boolean`, `enum`, `target_list`, `integer`, or `text` fields;
- populate device/interface/address choices from a bounded server context when target state matters;
- reject every unknown option;
- enforce types, character grammars, lengths, numeric ranges, cross-field rules, and installed-version combinations;
- normalize values into safe metadata;
- construct an argv array beginning with one exact absolute executable;
- declare a fixed worker, singleton/resource lock, wall limit, target summary, artifacts, and confirmation policy;
- use only registered `@JOB@/fixed-name` placeholders for output files;
- never call `io.popen`, `os.execute`, `load*`, a shell, or another executable.

Native capability should be represented faithfully where practical. Limits need a concrete appliance, hardware, artifact, lifecycle, or safety reason.

## 4. Wire one exact backend and worker

Add the action to `operator_backends` in `ddk-console`, mapping it to one fixed worker and executable. Then add that worker task to `ddk-job-worker`.

The worker must independently assert the expected action, `operator_mode`, executable, argv/artifact path shape, and material live target/hardware state. It must track its direct child, honor DDK cancellation, bound time/output/files, validate produced artifacts, clean partial state, and release locks on every exit.

Do not pass the options envelope to the worker as command text. The backend persists one validated argv element per line after resolving only declared job-local artifacts.

## 5. Choose confirmation deliberately

Read-only inventory and ordinary diagnostics should normally start after review without a typed confirmation. Require an exact target-bound phrase for consequential operations such as erase, restore, firmware write, destructive filesystem write, device-mode change, interface configuration, material CAN transmission, promiscuous/payload capture, or a temporary server listener.

The phrase must identify the target and important parameters. It is consumed during the one-time prepared-action claim and must not be stored in job metadata.

## 6. Add artifact and input boundaries

Output files require:

- a fixed action-owned basename;
- one declared type and maximum size;
- creation below the generated job directory, or the matching DDK extroot artifact directory when a concrete output ceiling would be unsafe for RAM-backed `/tmp`;
- worker validation of regular-file status and native format;
- an exact authenticated rpcd read ACL pattern;
- browser job-ID/name/size validation;
- cancellation/failure cleanup tests.

Never accept an output path from the browser. If the action consumes firmware, images, scripts, or recovery media, first implement and test a DDK-owned authenticated upload store with fixed IDs, path isolation, size/type/hash checks, expiry, single-purpose target binding, and cleanup. Do not reinterpret an arbitrary router path as an upload.

## 7. Update review lists and GUI

List enabled actions in exactly one class file:

- `scripts/enabled-info-actions.txt`
- `scripts/enabled-action-ids.txt`
- `scripts/enabled-security-actions.txt`
- `scripts/enabled-disruptive-actions.txt`

Use the reusable schema renderer and prepared review panel in `console-app.js`. Add one control in the appropriate pages, ensure absent hardware disables only actions that truly require it, display native errors/artifacts, and verify mobile/desktop layouts.

## 8. Test the complete boundary

At minimum cover:

- malformed base64url and JSON;
- envelope version/unknown-field rejection;
- every option type/range/enum/character grammar;
- unknown option and incompatible-combination rejection;
- missing binary/hardware/target drift;
- exact argv and artifact placeholder resolution;
- target-bound confirmation success/failure;
- one-time prepared request reuse;
- singleton/global/shared-resource contention and stale cleanup;
- success, native failure, timeout, cancellation, and no residual process/listener;
- artifact type/size/path/symlink/traversal rejection;
- GUI controls, review, errors, downloads, and responsive layout;
- regression coverage for LuCI authentication, GL.iNet UI, Tailscale, extroot, swap, reports, rollback, and protected configuration.

Run:

```sh
jq -e . files/usr/share/ddk-field-console/tools/example.json
./scripts/validate-local.sh
```

Router-safe tests may follow only after deployment is explicitly approved. Hardware-changing acceptance requires the exact approved target and authorization; missing hardware must be reported honestly rather than bypassed.

## State semantics

- Package/binary absent: `UNAVAILABLE`.
- Required hardware absent: `HARDWARE REQUIRED`.
- Device-oriented identity tooling with no device: `READY / NO DEVICE`.
- Installed but not yet wired: `NOT CONFIGURED`.
- Fully wired and currently runnable: `READY`.

See [OPERATOR-MODE.md](OPERATOR-MODE.md) for the complete request, lock, metadata, cancellation, and artifact contract.
