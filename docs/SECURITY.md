# Security Model

## Trust boundary

The Field Console is mounted below LuCI's authenticated `admin` tree. Live data calls and transient camera downloads use the existing `cgi-io` session boundary. There is no unauthenticated DDK CGI, API port, or reverse-proxy rule. The public `/ddk` web-root file is a content-free redirect only.

LuCI static JavaScript, CSS, and non-secret module descriptions may be web-readable like other LuCI assets. They contain no credentials and cannot execute actions without an authenticated `cgi-io` call.

## Action allowlisting

The browser invokes one executable only:

```text
/usr/libexec/ddk-console
```

The first argument is a fixed verb. Subsequent arguments must match an exact action table or strict generated-ID grammar. Unknown verbs, extra arguments, shell syntax, paths, and numeric PIDs are rejected.

The browser cannot submit:

- an executable path;
- a shell command or fragment;
- arbitrary flags;
- an action output path;
- a generic PID;
- a report filesystem path.
- an Android/Apple/programmer device, serial, USB path, tool, option, image, script, or SSH command.

The backend's `capture()` receives only source-code constants. A request value selects a table record but is never concatenated into a command. Serial, radio, camera, and GNSS attribution read fixed procfs/sysfs locations. Camera artifact download is separate from execution: the client accepts only a generated job ID, derives one fixed path, and native `cgi-download` independently enforces the exact rpcd file ACL.

## Registry isolation

Manifest `actions` and `status_probe` values are descriptive. The backend validates symbolic probe IDs and ignores unknown probes. A manifest cannot create a runnable backend action.

## Argument validation

The current release accepts:

- exact INFO action IDs;
- exact job action IDs;
- job IDs matching `job-<digits>-<digits>`;
- report IDs matching `report-<digits>-<digits>`.

There are no browser-provided network targets, interfaces, filters, action-output filenames, device nodes, PIDs, package names, durations, camera/radio/GNSS/CAN parameters, mobile/programmer identifiers, tool arguments, output protocols, or flags. For `network.nmap_lan_discovery`, the worker independently requires the native LAN device to equal `br-lan`, reads its IPv4 CIDR from the kernel, validates RFC1918 scope and a `/24`-or-smaller prefix, and then invokes one fixed host-discovery profile. For `capture.lan_metadata_snapshot`, the worker independently requires an up native LAN on exactly `br-lan` and invokes one fixed non-promiscuous ARP/ICMP/DHCP metadata profile. For `radio.rtl433_snapshot`, the backend and worker require one exact reviewed tuner and a safe sysfs serial; frequency, sample rate, gain, decoders, configuration, duration, and output are fixed. For `camera.still_snapshot`, both layers require one sysfs-attributed UVC camera and primary node; resolution, frame count, warm-up, quality, banner, duration, artifact name, and destination are fixed. For `gps.snapshot`, both layers require one external USB GNSS identity and one exclusive reviewed serial node; the EC25-AF is excluded, while duration, byte ceiling, decoder, fields, and scratch paths are fixed. For `can.capture`, both layers require one already-up physical `canN` and `candump`; interface, count, timeouts, formatting, and output paths are fixed. For `cellular.snapshot`, the worker requires the exact EC25-AF VID:PID, `qmi_wwan`, `/dev/cdc-wdm0`, and its attributed `wwan0`; browser input cannot select a modem or QMI action.

For `android.identify`, `apple.identify`, and `firmware.identify`, the backend passes one source-code identity kind to a bounded Lua classifier whose sysfs root is also a source-code constant. The browser supplies neither. The matching `*.operator_guide` responses are server-side constant text plus live executable-presence booleans; displaying a command cannot execute it.

## Job controls

- The helper generates the job ID and worker task name.
- Detached workers receive stdin from `/dev/null`; browser or caller input cannot reach an interactive child.
- At most two jobs may be active.
- At most one Nmap LAN discovery job may be active.
- At most one LAN metadata capture may be active.
- At most one RTL-433 workflow and one shared `rtl_sdr` resource may be active.
- At most one camera workflow and one shared `camera` resource may be active.
- At most one GPS/GNSS workflow and one shared `gps` resource may be active.
- At most one passive CAN workflow and one shared `can` resource may be active.
- At most one cellular snapshot may be active.
- A stop request supplies a generated job ID, not a PID.
- Before `TERM`, the helper reads its own PID file and confirms `/proc/<pid>/cmdline` contains both the DDK worker path and exact job ID.
- No other signal or generic kill endpoint exists.
- stdout is limited to 128 KiB and stderr to 32 KiB.
- Cleanup traverses only validated DDK-owned `/tmp/ddk/jobs/job-*` directories and report names.
- The Nmap worker tracks its direct child and terminates that child when an authenticated stop request terminates the worker.
- The capture worker tracks its direct `tcpdump` child, terminates it on authenticated stop, and checks that `br-lan` flags are unchanged after normal completion.
- The RTL-433 worker tracks its direct receiver child, applies a 20-second client limit, a 25-second independent wall limit, 56 KiB child-file limits, and a 64 KiB final-output limit.
- The camera worker tracks its direct `fswebcam` child, applies a 20-second independent wall limit, a 256 KiB file limit, and removes partial/failed/stopped artifacts.
- The GPS/GNSS worker tracks its byte-read and decoder children, applies 15-second/32-KiB raw and 32-KiB final limits, and deletes raw/decoded scratch files on completion, failure, or stop.
- The CAN worker tracks its direct `candump` child, applies 128-frame/20-second capture limits, a 25-second independent wall limit, 56-KiB child and 64-KiB final limits, and verifies interface flags remain unchanged.
- Each cellular query has a five-second client timeout, a seven-second worker wall limit, and direct-child cancellation.

Mobile/programmer identity and operator-guide calls are deliberately not jobs: they run no external device tool, create no `/tmp/ddk` directory, and persist no output.

## Mobile device and programmer privacy boundary

USB serial identifiers, descriptors, interface signatures, and physical topology may identify customer equipment. Identity actions therefore require explicit UI confirmation. Every displayed field is sanitized and length-bounded. Full identity records exist only in the authenticated response and browser DOM; status/capability APIs expose counts and reasons only.

The DDK backend and worker contain no ADB, fastboot, usbmuxd, libimobiledevice, recovery, restore, debugger, DFU, or programmer execution path. The operator-guide actions make full native functionality discoverable through SSH without accepting or executing browser text. Direct SSH use remains operator-controlled and unmodified.

The installed ADB documents `-a` as listening on all interfaces. DDK neither invokes nor recommends that flag. Full CLI handoff documentation requires local-server cleanup and preserves the appliance no-WAN-exposure policy. See [DEVICE-IDENTITY.md](DEVICE-IDENTITY.md) and [SSH-TOOL-HANDOFFS.md](SSH-TOOL-HANDOFFS.md).

## Packet-capture privacy boundary

The enabled capture is not a general sniffer. It uses `-i br-lan -p -n -q -e -l -tttt -s 96 -c 128` and one literal BPF expression for ARP, ICMP, and IPv4 DHCP. It runs for at most 20 seconds, writes decoded text only, and caps that text at 64 KiB. No PCAP, payload hex/ASCII dump, DNS lookup, TCP/application session, WAN interface, all-interface mode, monitor mode, replay, or persistent capture is available.

An authenticated operator may see timestamps, local MAC addresses, local IP addresses, and brief DHCP/ICMP metadata. The UI discloses this before confirmation. Output uses the existing mode-0700 transient job directory, four-hour age cleanup, and 20-job retention ceiling. See [PACKET-CAPTURE.md](PACKET-CAPTURE.md).

## Radio receive boundary

The enabled radio action is one fixed 433.92 MHz sensor-decoding profile. It loads no default or user config, uses no custom analyzer/decoder, saves no I/Q or signal files, and emits JSON only to its bounded local job output. It never invokes `rtl_tcp`, MQTT, InfluxDB, syslog, a remote input, a transmitter, a driver detach, or a module operation.

Decoded nearby transmissions can expose sensor identifiers and measurements. The UI requires explicit confirmation and states this privacy boundary. Operators must use it only on owned or authorized radio traffic. See [RTL433-RECEIVE.md](RTL433-RECEIVE.md).

## Cellular privacy boundary

The snapshot permits only operating mode, data-session state, radio signal, and serving-system queries. Output is rebuilt from an explicit field whitelist and never returns raw modem JSON. IMEI, IMSI, ICCID, MSISDN, SIM contents, APN/current settings, credentials, PIN/PUK state, cell location, operator-description bytes, network scans, registration changes, resets, and raw AT/QMI input are excluded.

## GPS/GNSS privacy boundary

The position snapshot can expose precise location, time, altitude, speed, and course. The UI therefore requires explicit operator confirmation. The worker opens only a server-derived, exclusive external USB GNSS serial node for reading, never the reserved EC25-AF ports. It starts no service, changes no serial setting, sends no receiver command, and makes no network request.

Raw receiver bytes are capped at 32 KiB, passed through `gpsdecode` for NMEA checksum validation, and deleted along with decoded scratch data before the job ends. Only whitelisted position fields reach the job output. Coordinates are transient and excluded from DDK system reports. See [GPS-GNSS-SNAPSHOT.md](GPS-GNSS-SNAPSHOT.md).

## CAN authorization and receive-only boundary

CAN frames can expose vehicle, industrial equipment, sensor, access-control, medical-device, or automation state. The UI requires explicit owned/authorized-bus confirmation. The worker uses only one server-derived physical `canN` that is already up; it never configures bitrate/link state, creates a virtual interface, attaches a serial line discipline, restarts a service, or runs a transmit/replay utility.

The fixed candump profile emits transient decoded frame text only. Frame count, timeouts, child/final output, concurrency, and retention are bounded. See [CAN-PASSIVE-CAPTURE.md](CAN-PASSIVE-CAPTURE.md).

## Camera privacy and file boundary

The camera action creates one local still only after an explicit consent/authorization warning. A frame can contain people, customer property, documents, screens, or location details. It is not copied into a report, persistent directory, website path, stream, network destination, or log.

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

The project creates no listener and makes no firewall, nginx, uhttpd, ttyd, network, wireless, cellular, or Tailscale configuration change. The separately approved swap configurator changes only `/etc/config/fstab`, after an exact backup, and is not web-exposed or invoked by normal dashboard deployment. The public `/ddk` resource contains only a same-origin redirect and fallback link to the authenticated LuCI overview; it exposes no status, action, identifier, session, or report data. Verification checks the exact redirect target, searches for any DDK listener, and checks protected configuration hashes.

The swap configurator accepts no browser input and no remote path, file, section, option, or value. Its target, section, and UCI values are constants. Rollback accepts only a strict timestamped backup-name grammar, checks before/after hashes, and refuses to overwrite an fstab that changed after configuration.

Existing listeners found during discovery are out of scope; this project neither endorses nor changes them.

## CSRF and session assumptions

The template client uses LuCI's existing authenticated `cgi-io` request format (the same format as `fs.exec_direct()`), which carries the dispatcher-provided session identifier and enforces exact command ACLs. No custom cookie, token, or authentication store exists. The application never reads or exports the user's session cookie.

## Security tests

Local validation checks enabled-action consistency and forbidden mutation patterns. Router verification actively attempts:

- shell metacharacters inside an action ID;
- a generic numeric PID stop;
- report path traversal.

The production suite also attempts malformed operation IDs and extra browser-supplied interface/device/parameter values, proves singleton enforcement and DDK-owned cancellation where hardware is available, checks `br-lan` flags before/during/after, compiles the fixed BPF expression, enforces output ceilings, rejects PCAP/failed-camera artifacts, and requires no bounded-operation process to remain. Version 2 adds positive and negative identity fixtures, no-job/no-process/no-listener proofs, report exclusion, and full-CLI-text/non-execution assertions. Authenticated browser verification downloads an allowlisted transient artifact and proves an outside path is denied.

It requires rejection and confirms the injection marker was not created.
