# Security Model

## Trust boundary

The Field Console is mounted below LuCI's authenticated `admin` tree. Live data calls, artifact downloads, and bounded input uploads use the existing `cgi-io` session boundary. There is no unauthenticated DDK CGI, API port, or reverse-proxy rule. The public `/ddk` web-root file is a content-free redirect only.

LuCI static JavaScript, CSS, and non-secret module descriptions may be web-readable like other LuCI assets. They contain no credentials and cannot execute actions without an authenticated `cgi-io` call.

## Action allowlisting

The browser invokes one executable only:

```text
/usr/libexec/ddk-console
```

The first argument is a fixed verb. Subsequent arguments must match an exact action table, versioned structured-envelope position, or strict generated-ID grammar. Unknown verbs, extra arguments, shell syntax, arbitrary paths, and numeric PIDs are rejected.

The browser cannot submit:

- an executable path;
- a shell command or fragment;
- an arbitrary/raw flag list;
- an action output path;
- a generic PID;
- a report filesystem path.
- an arbitrary Android/Apple/programmer device path, tool, option, image path, script, or SSH command.

Legacy backend `capture()` calls receive only source-code constants. Operator Mode accepts typed values only for an exact action schema. `operator-actions.lua` rejects unknown fields and normalizes each value before an action-specific builder may add it as one literal argv element. The backend then enforces an exact action-to-worker-to-executable mapping. It never evaluates request JSON, accepts an executable, or constructs shell syntax from browser text.

Artifact download is separate from execution: the client accepts only a generated job ID plus a server-advertised fixed safe name, derives the DDK job path, and native `cgi-download` independently enforces exact rpcd file ACL patterns.

## Registry isolation

Manifest `actions` and `status_probe` values are descriptive. The backend validates symbolic probe IDs and ignores unknown probes. A manifest cannot create a runnable backend action.

## Argument validation

The current source accepts exact INFO/action IDs, generated job/report IDs, generated one-time prepared IDs, and a base64url UTF-8 JSON action envelope capped at 24 KiB. The envelope must contain exactly version `1` and one options object. Unknown envelope and option keys, duplicate transport positions, malformed encoding/JSON, wrong types, control characters, and action-specific range or enum violations fail before a job or native process exists.

`network.nmap_lan_discovery` validates target/exclude lists as IPv4, IPv6, CIDR, hostname, or supported IPv4 octet-range syntax; port/probe expressions use narrow grammars; interface and congestion choices come from live server state; scan/output/NSE values use exact enums; and every numeric field is bounded. The builder—not the browser—selects `/usr/bin/nmap` and maps values to the exact installed 7.91 arguments. CIDRs are not restricted to private `/24` scope, but the request/wall/output/concurrency ceilings protect the router.

`capture.lan_metadata_snapshot` accepts only a live interface choice, one bounded printable BPF string, and typed capture/display options. The BPF remains one argv element and the worker compiles it with the exact installed `/usr/sbin/tcpdump` before capturing. Artifact paths are fixed. Promiscuous, payload, and PCAP modes are target-confirmed, resource-bounded, and cancellation-aware.

`throughput.iperf3` accepts typed client/server options for the exact installed `/usr/bin/iperf3`. Server bind addresses must be selected from currently assigned local addresses and are revalidated by the worker just before launch. The temporary listener is target-bound, wall-bounded, normally one-off, cancellation-aware, and absent after the job.

Radio, camera, serial/GNSS, Android, Apple, firmware/storage, monitoring, wireless/USB, forensics/replay, automation, industrial, Bluetooth, and token actions accept action-specific typed options populated from live reviewed state and are independently revalidated by their workers. Phase 4 secrets are named one-time private inputs and sealed files are re-hashed before use. Apple normal mode requires a fresh exact UDID match through a DDK-owned temporary usbmuxd; recovery/DFU requires a sysfs-derived ECID and exact irecovery preflight. Firmware binds USB topology/serial or reviewed non-EC25 serial nodes, installed OpenOCD configs/native part lists, and sealed input hashes. Storage excludes every disk backing root/rom/overlay/extroot/swap and repeats USB ancestry, block type, mount, size, and argv-target checks in the worker. CAN and cellular retain bounded target-derived profiles where runtime/rollback prerequisites remain absent. Android, Apple, and programmer INFO identity actions still pass only one source-code identity kind to a bounded sysfs classifier; their operator-guide text is constant and non-executable.

For `android.identify`, `apple.identify`, and `firmware.identify`, the backend passes one source-code identity kind to a bounded Lua classifier whose sysfs root is also a source-code constant. The browser supplies neither. The matching `*.operator_guide` responses are server-side constant text plus live executable-presence booleans; displaying a command cannot execute it.

## Authenticated input boundary

The browser cannot submit an upload destination. It reserves an exact kind/name/size tuple and receives one generated `/overlay/ddk-field-console/uploads/upload-<digits>-<digits>-<digits>/payload.bin` path. rpcd permits native LuCI upload only to that pattern. Finalization requires the exact declared regular-file size, atomically renames it to `sealed.bin`, replaces the former writable name with a directory sentinel, validates ZIP signatures for Android/Apple archives, computes SHA-256, and persists only bounded metadata at mode 0600. Native action builders and workers must consume a generated upload ID and revalidate kind, sealed path, hash, expiry, and target; original names never become argv paths.

At most 10 inputs are retained. Reservations expire after one hour and sealed files after 24 hours. An input lock prevents expiry cleanup and deletion while an active job owns it. Delete and list APIs accept only generated IDs; cleanup removes only known filenames below a validated DDK upload directory. The existing native `cgi-upload` cannot enforce a DDK byte ceiling while streaming, so the browser rejects oversized selections before transfer and finalization rejects size mismatches after transfer. This limitation is explicit; a hard mid-stream cutoff would require a dedicated authenticated streaming CGI.

## Job controls

- The helper generates the job ID and worker task name.
- Prepared IDs are generated server-side, mode-restricted, expire after five minutes, and are atomically single-use.
- The plan must match one exact action, worker, and executable before job creation.
- Detached workers receive stdin from `/dev/null`; browser or caller input cannot reach an interactive child.
- At most two jobs may be active.
- Global, action-singleton, and shared-resource locks use atomic directories, generated owner IDs, and stale-owner recovery.
- At most one Nmap, tcpdump, or iperf3 workflow of its respective action may be active.
- At most one RTL-433 workflow and one shared `rtl_sdr` resource may be active.
- At most one camera workflow and one shared `camera` resource may be active.
- At most one GPS/GNSS workflow and one shared `gps` resource may be active.
- At most one ADB workflow and one shared `adb` resource may be active; file-consuming jobs also lock each sealed input.
- At most one Apple workflow and one shared `apple_mobile` resource may be active; recovery/restore inputs are separately locked.
- At most one firmware workflow and one shared `firmware` resource may be active; each sealed image is separately locked.
- Storage jobs lock their physical disk, while file-only SquashFS recovery uses a separate singleton; sealed inputs and extroot capacity are reserved before start.
- At most one passive CAN workflow and one shared `can` resource may be active.
- At most one cellular snapshot may be active.
- A stop request supplies a generated job ID, not a PID.
- Before `TERM`, the helper reads its own PID file and confirms `/proc/<pid>/cmdline` contains both the DDK worker path and exact job ID.
- No other signal or generic kill endpoint exists.
- stdout is limited to 128 KiB and stderr to 32 KiB.
- Cleanup traverses only validated DDK-owned `/tmp/ddk/jobs/job-*`, matching `/overlay/ddk-field-console/artifacts/job-*`, upload, and report names; symlinks are unlinked rather than followed.
- Operator Nmap tracks its direct child, enforces the independent plan wall limit, and validates any fixed-name native artifacts.
- Operator tcpdump compiles the BPF first, tracks capture/decode children, terminates them on authenticated stop, checks selected-interface flags, and validates PCAP magic/size.
- Operator iperf3 revalidates server binding, tracks its child, bounds server lifetime, and validates JSON output.
- The RTL-433 worker tracks its direct receiver child, applies a 20-second client limit, a 25-second independent wall limit, 56 KiB child-file limits, and a 64 KiB final-output limit.
- The camera worker tracks its direct `fswebcam` child, applies a 20-second independent wall limit, a 256 KiB file limit, and removes partial/failed/stopped artifacts.
- The GPS/GNSS worker tracks its byte-read and decoder children, applies 15-second/32-KiB raw and 32-KiB final limits, and deletes raw/decoded scratch files on completion, failure, or stop.
- The ADB worker tracks its native child, revalidates target and any sealed input, applies operation/file ceilings, kills the temporary localhost server, and removes partial artifacts on completion, failure, or stop.
- The Apple worker tracks its native child, revalidates UDID/ECID and sealed inputs, refuses ownership when usbmuxd is already live, kills only its temporary helper, validates artifacts, protects the extroot reserve, and removes its restore workspace on every exit.
- The Phase 3 worker revalidates exact tool version, literal argv shape/target binding, programmer/DFU/serial/block identity, sealed input hash, artifact ceiling, and extroot reserve; it disables OpenOCD listeners and removes partial firmware/storage artifacts and SquashFS workspaces on every unsuccessful exit.
- The Phase 4 worker revalidates exact action/executable mapping, argv/path shape, interfaces and hardware, sealed-input size/SHA, private-input names, generated Modbus configuration, temporary helper ownership, output ceilings, wall limits, artifacts, and resource locks; it removes helpers, private material, partial artifacts, and locks on every unsuccessful exit.
- The CAN worker tracks its direct `candump` child, applies 128-frame/20-second capture limits, a 25-second independent wall limit, 56-KiB child and 64-KiB final limits, and verifies interface flags remain unchanged.
- Each cellular query has a five-second client timeout, a seven-second worker wall limit, and direct-child cancellation.

The mobile/programmer identity and operator-guide calls are not jobs: they run no external device tool, create no `/tmp/ddk` directory, and persist no output. Android, Apple, firmware, and storage Operator actions are jobs and use the normal target/artifact/lock/cancellation controls.

## Mobile device and programmer privacy boundary

USB serial identifiers, descriptors, interface signatures, and physical topology may identify customer equipment. Identity actions therefore require explicit UI confirmation. Every displayed field is sanitized and length-bounded. Full identity records exist only in the authenticated response and browser DOM; status/capability APIs expose counts and reasons only.

The backend and worker contain exact ADB 1.0.32 execution paths for two structured actions. They correlate selectable transports with reviewed USB ADB identities, use one temporary localhost server on port 5038, revalidate the selected device immediately before execution, and clean the server on every exit. Fixed `shell getprop` and `shell pm list packages` token sequences are supported; arbitrary shell text is not.

Apple has five exact structured actions for libimobiledevice 1.3.0, irecovery 1.0.0, and idevicerestore 1.0.0. Device-changing plans require target-bound confirmation; read-only diagnostics/query do not. Recovery protocol commands are one bounded literal irecovery argument, never router shell syntax. IPSWs, recovery inputs, and AP tickets use sealed uploads; restore cache uses one declared isolated workspace and is not downloadable. The worker surfaces native output, bounds artifacts, cancels only tracked children, and leaves no idle usbmuxd or port 27015 listener. Interactive recovery shell, encrypted backup, developer-image, and debugger protocols remain explicitly deferred as documented in [APPLE-OPERATOR.md](APPLE-OPERATOR.md).

The installed ADB documents `-a` as listening on all interfaces. DDK never invokes it. DDK uses `-P 5038`, verifies a localhost listener, refuses an occupied port, and kills the server after discovery or work. Network ADB targets are not selectable because the current authorization model requires USB/sysfs correlation. See [ANDROID-ADB.md](ANDROID-ADB.md), [APPLE-OPERATOR.md](APPLE-OPERATOR.md), [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md), [DEVICE-IDENTITY.md](DEVICE-IDENTITY.md), and [SSH-TOOL-HANDOFFS.md](SSH-TOOL-HANDOFFS.md).

## Packet-capture privacy boundary

The v2.1 tcpdump workflow is a professional capture frontend, not an arbitrary command runner. The operator may select a live interface (including installed `any` support), one validated BPF expression, capture bounds, decoded display options, and PCAP output. Interface names come from the server schema; the filter is compiled before capture; output paths and filenames are fixed by DDK.

Captures can expose credentials, payloads, identities, and third-party traffic. The review displays the interface, filter, duration/count, snap length, and output. Promiscuous, payload-display, or PCAP plans require exact target-bound confirmation. PCAPs are limited to 8 MiB under a mode-0700 transient job and downloaded only through the authenticated fixed artifact ACL. Packet replay is a separate exact `tcpreplay` action that accepts only a sealed capture ID, current interface, and typed rate/count/time controls; it verifies PCAP readability and requires exact transmission confirmation. No arbitrary injection text, monitor-mode transition, persistent ring buffer, router path, or network export exists. See [PACKET-CAPTURE.md](PACKET-CAPTURE.md) and [PHASE4-OPERATOR.md](PHASE4-OPERATOR.md).

## Radio receive boundary

The enabled radio action accepts only reviewed live tuner choices and typed receive options supported by rtl_433 20.11. It may create bounded decoded or raw I/Q artifacts under the job directory. It loads no default or user config and never invokes `rtl_tcp`, MQTT, InfluxDB, syslog, a remote input, a transmitter, a driver detach, or a module operation.

Decoded nearby transmissions can expose sensor identifiers and measurements. The UI requires explicit confirmation and states this privacy boundary. Operators must use it only on owned or authorized radio traffic. See [RTL433-RECEIVE.md](RTL433-RECEIVE.md).

## Cellular privacy boundary

The snapshot permits only operating mode, data-session state, radio signal, and serving-system queries. Output is rebuilt from an explicit field whitelist and never returns raw modem JSON. IMEI, IMSI, ICCID, MSISDN, SIM contents, APN/current settings, credentials, PIN/PUK state, cell location, operator-description bytes, network scans, registration changes, resets, and raw AT/QMI input are excluded.

## GPS/GNSS privacy boundary

The position snapshot can expose precise location, time, altitude, speed, and course. The UI therefore requires explicit operator confirmation. The worker opens only an operator-selected value from the server-derived live external USB GNSS inventory, never the reserved EC25-AF ports. It starts no service, changes no serial setting, sends no receiver command, and makes no network request.

Raw receiver bytes and decoded output are capped by the chosen bounded profile and passed through exact gpsdecode 3.23.1. The operator may retain fixed-name raw/decoded job artifacts; they remain mode-restricted, authenticated, transient, and excluded from DDK system reports. Only whitelisted fields reach the optional position summary. See [GPS-GNSS-SNAPSHOT.md](GPS-GNSS-SNAPSHOT.md).

## CAN authorization and receive-only boundary

CAN frames can expose vehicle, industrial equipment, sensor, access-control, medical-device, or automation state. The UI requires explicit owned/authorized-bus confirmation. The worker uses only one server-derived physical `canN` that is already up; it never configures bitrate/link state, creates a virtual interface, attaches a serial line discipline, restarts a service, or runs a transmit/replay utility.

The fixed candump profile emits transient decoded frame text only. Frame count, timeouts, child/final output, concurrency, and retention are bounded. See [CAN-PASSIVE-CAPTURE.md](CAN-PASSIVE-CAPTURE.md).

## Camera privacy and file boundary

Camera actions require explicit consent/authorization because a frame or stream can contain people, customer property, documents, screens, or location details. Stills are not copied into reports, persistent directories, website paths, streams, network destinations, or logs. The separate stream action binds only an exact current IPv4 address and non-privileged port, requires one-time credentials plus exact confirmation, and terminates at its wall limit or cancellation without enabling a boot service or firewall rule.

The worker writes a mode-0600 temporary file below its mode-0700 DDK job, validates size/type/JPEG magic, and atomically renames only a successful result. The backend exposes metadata only for that completed fixed file. Native authenticated `cgi-download` has read permission only for `/tmp/ddk/jobs/job-[0-9]*-[0-9]*/snapshot.jpg`. The browser checks the job grammar, derives that path rather than accepting text input, checks the returned byte length, and creates an in-memory object URL only on operator request. See [CAMERA-SNAPSHOT.md](CAMERA-SNAPSHOT.md).

## Reports and sensitive information

The system report intentionally excludes:

- UCI configuration bodies;
- Wi-Fi PSKs;
- passwords or password hashes;
- private keys and certificates;
- API or Tailscale auth keys;
- Tailscale peer lists;
- application logs and customer payloads.

It includes read-only system identity, resource state, interface/address/route information, Tailscale self version/IP, USB/device presence, package names, and hashes—not contents—of protected configuration files. It does not include GPS/GNSS coordinates, raw receiver data, Android/Apple/programmer USB serials, identity snapshot fields, or operator-guide content.

Reports live outside `/www` under mode-restricted `/tmp/ddk/reports/`. Authenticated helper calls return report content for view/download.

## WAN and service posture

The project creates no persistent or idle listener and makes no firewall, nginx, uhttpd, ttyd, network, wireless, cellular, or Tailscale configuration change. An explicitly confirmed iperf3 server or authenticated UVC stream may create one temporary listener only on an exact address currently assigned to the router and a validated selected port; each is wall-bounded, owned by its job, cancelled with the job, and checked absent afterward. MQTT and NTRIP make only operator-specified bounded outbound connections and retain no service. Optional device daemons remain disabled at boot and are not enabled merely because their packages exist; PC/SC starts on demand only when the job owns and later stops it.

An unavailable action is not hidden and cannot be disabled merely by risk classification. Its manifest must carry a bounded `unavailable_reason` naming the concrete runtime, topology, lifecycle, or rollback blocker; Phase 5 validates the exact six-action inventory and the GUI renders each reason beside its disabled control. See [PHASE5-ACCEPTANCE.md](PHASE5-ACCEPTANCE.md).

The separately approved swap configurator changes only `/etc/config/fstab`, after an exact backup, and is not web-exposed or invoked by normal dashboard deployment. The public `/ddk` resource contains only a same-origin redirect and fallback link to the authenticated LuCI overview; it exposes no status, action, identifier, session, or report data. Verification checks the exact redirect target, searches for unexpected residual DDK/tool listeners, and checks protected configuration hashes.

The swap configurator accepts no browser input and no remote path, file, section, option, or value. Its target, section, and UCI values are constants. Rollback accepts only a strict timestamped backup-name grammar, checks before/after hashes, and refuses to overwrite an fstab that changed after configuration.

Existing listeners found during discovery are out of scope; this project neither endorses nor changes them.

## CSRF and session assumptions

The template client uses LuCI's existing authenticated `cgi-io` request format (the same format as `fs.exec_direct()`), which carries the dispatcher-provided session identifier and enforces exact command ACLs. No custom cookie, token, or authentication store exists. The application never reads or exports the user's session cookie.

## Security tests

Local validation checks enabled-action consistency, reviewed disruptive IDs, fixed operator mappings, schemas/builders/workers, artifact ACLs, and forbidden mutation patterns. Router verification actively attempts:

- shell metacharacters inside an action ID;
- malformed base64url/JSON, unknown option keys, and invalid target/filter values;
- starting an Operator Mode action without a prepared request;
- reusing a claimed prepared request;
- a generic numeric PID stop;
- report path traversal.

The target-safe v2.1 suite prepares and runs Nmap only against loopback, validates its native XML artifact, captures loopback traffic to a bounded PCAP, proves invalid BPF rejection, and exercises iperf3 through temporary loopback-only server/client flows with cleanup checks. Existing hardware workflows retain singleton/refusal/cancellation tests where hardware is available. Authenticated browser verification exercises reusable fields/review, downloads allowlisted transient artifacts, and proves an outside path is denied.

These v2.1 tests ran against the deployed production tree. Comprehensive target verification passed 48 checks with no warnings, and authenticated browser acceptance covered structured controls, sealed-input upload/hash/delete, artifact ACL isolation, desktop/mobile layouts, and external-request/runtime-error rejection. Injection tests require rejection and confirm that their marker is never created.
