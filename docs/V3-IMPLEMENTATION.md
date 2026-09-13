# Field Console v3 implementation and acceptance

## Release scope

The September review baseline was clean `main` at
`c5182a3c6010d35adaef5604220a01161176c85d` (v2.1.0). Work was isolated on
`feature/field-console-v3`. Version 3.0.0 contains 24 modules, 92 enabled actions,
78 structured workflows and no statically disabled manifest actions. These are
registry counts, not a claim of complete native CLI or peripheral compatibility.

The implementation covers every family in the September functionality review.
The main changes are:

- **Results and retention:** stopping or failing preserves registered partial
  artifacts, marked incomplete. Saved cases retain metadata across reboots, can
  be named/exported/deleted, and supply reusable inputs. Settings controls job
  age/count and input expiry, including zero to disable automatic cleanup.
  Retained inputs no longer encounter a fixed file-count ceiling.
- **Readiness and identity:** forms remain accessible when an unrelated utility
  or peripheral is absent. Preparation checks the selected operation. Android
  detection uses its ADB interface signature instead of a fixed vendor list.
  Camera/serial/radio locks follow the selected device; existing PC/SC and
  usbmuxd services are reused and only owned helpers are stopped. Programmers
  can be explicitly identified; native RTL identities and exact serial/index
  resolution replace two hard-coded tuner IDs.
- **Discovery and Android:** Nmap exposes installed NSE scripts/categories,
  private arguments and presets; ARP, DNS and repeated latency/loss have forms.
  Android adds network ADB, properties/packages/dumpsys/logcat, directories,
  split APKs and application/device management through a private ADB server.
- **Capture and sessions:** extroot captures, rotation, configurable output
  budgets, continuous sessions, stop/save/reuse, concurrent monitor interfaces,
  file analysis, serial text/hex transmission, MQTT subscription, camera video,
  radio streaming/recording and resource/bandwidth observation.
- **Device tools:** cellular diagnostics/control/AT/GNSS/profile workflows;
  Bluetooth services/pairing/connections; GNSS configuration/gpsd/RTK/NTRIP;
  CAN setup/filter/capture/transmit/replay; Modbus FC 1/2/3/4/5/6/15/16;
  USB topology-aware power and native VHCI-compatible USB/IP attachment.
- **Repair and analysis:** OpenOCD readback/debug/target controls, AVR memories
  and fuses, FTDI backup/configuration/write, native flashrom-usb, resumable
  ddrescue, offset-aware comparison, direct external disk-to-disk recovery,
  forensic hex/trace/GDB, and OTP/stoken. Existing Apple workflows remain.
- **Large inputs:** data upload ceilings follow the general 8 TiB supported
  file range and actual extroot space instead of old 256 MiB APK/firmware or
  1 GiB backup caps. Small structured ticket/config limits remain where used
  by parsers. Hashing runs independently of the HTTP request, reports progress,
  preserves failed inputs for inspection/deletion and extends expiry on finish.
- **Release tooling:** local validation executes Lua behavior tests and native
  adapter protocol/recovery fixtures. Counts come from the registry. Installation
  checks current infrastructure and current configuration hashes, preserves
  optional service state, backs up project files and supports automatic rollback.

Authentication, literal argv, exact target confirmation, job-owned cancellation,
private inputs, infrastructure topology and measured resource controls remain.
There is no generic browser shell, new permanent dashboard daemon, core-library
upgrade, network restart, or firmware reset in this release.

## Verified before publication

- Local shell, Lua, JavaScript and JSON validation; existing Apple/Phase 3/Phase 4
  planners; Nmap and 40 new/expanded workflow definitions; USB identity/topology,
  resource/artifact policy, private-output streaming redaction, offset comparison,
  asynchronous input hashing, five USB/IP loopback protocol fixtures, ten device
  selection/recovery fixtures and actual rollback script fixtures.
- The complete candidate backend runs in `/tmp/ddk-v3-full` on the real MIPS
  router with all job/input/case/artifact paths isolated. All 78 schemas open.
  Native prepare/start/results, stop, incomplete artifact save, case labels,
  reuse, simulated transient-state loss/reboot recovery, archive export, delete
  and retention validation pass.
- Eleven native worker fixtures cover loopback, deadlines, continuous stop,
  partial output, a public RFC 4226 OTP vector, executable rejection, serial
  pipes, file quotas, Nmap NSE argument files, isolated ADB cleanup, absent
  monitor hardware and owned GDB attach/stop/target resume.
- Native libmodbus passes all eight supported function codes against a loopback
  fixture, including fragmented replies, protocol errors and write/readback.
- Native gpsd/gpspipe reads synthetic advancing NMEA over an owned PTY. RTKLIB
  starts and cleans up with a pseudo-receiver. flashrom-usb reads the expected
  128 KiB contents of its dummy emulated flash chip.
- A real monitor interface on the current 2.4 GHz channel starts and is removed
  afterward. Its filter excludes ordinary client frames. A separate loopback
  ring test sends 6,000 public synthetic datagrams and produces three rotating
  PCAPs with zero reported kernel drops. Protected network hashes are unchanged.
- Native CAN userspace payloads were downloaded, checked against exact hashes,
  inspected for architecture/dependencies and run from isolated staging. A
  public CAN log replays to stdout without transmitting CAN traffic.
- Authenticated browser tests exercise representative forms across the expanded
  families and a real loopback run/stop/save/download/reuse flow, retention
  settings and file ACL rejection. An actual 8 MiB upload throttled to 100 KB/s
  (over 80 seconds) completes and seals successfully.
- All 15 dashboard pages pass responsive checks at 1440, 390 and 320 pixels;
  desktop Jobs and mobile Settings screenshots were visually inspected.

## Native compatibility fixes found during validation

- flashrom is `/usr/sbin/flashrom-usb` v1.2 on this image; the absent unversioned
  name was not evidence of a missing package. Bus Pirate serial speed uses the
  compiled native syntax.
- RTKLIB serial streams prepend `/dev/`; pass `ttyUSBn` internally. Its PTY
  console must become ready before `start`, and early exit is failure.
- MIPS SIGCONT is `nixio.const.SIGCONT` (25), not an assumed x86 signal number.
- `nixio.fs.readfile` returns more than one value. Numeric conversion and string
  helper boundaries must explicitly keep one return value. This repaired real
  Tools-page JSON failures that simpler static checks missed.
- `nixio.open` uses `r+`, not `rw`; the native asynchronous hasher startup was
  tested after correcting this.
- Stock RTL tools interpret numeric selectors as indices before serial numbers.
  The adapter enumerates through installed librtlsdr and requires one complete
  serial match. Duplicate/disconnected identities fail before execution.
- Bluetooth selection of an already-default controller has no acknowledgment.
  The adapter issues `show` and verifies the actual controller before any device
  operation. Wrong-controller and already-selected cases are covered by fixtures.
- CAN can be configured for the first time while down without historical timing.
  Failure restores prior timing/state when available. Cellular profile changes
  use the native independent UCI rollback timer and explicit keep confirmation.
- Kernel file quotas above 4 GiB become unlimited on this 32-bit build. The
  worker also checks registered output budgets and 100 MiB free space every
  200 ms. Small final-write overshoots remain downloadable as incomplete output.
- Private-output redaction now streams the entire artifact with cross-chunk
  matching, instead of replacing full output with the UI's 64 KiB preview.

## Remaining physical acceptance and constraints

No actual customer device/data was used. Real Android/Apple phones, Bluetooth
peripherals, GNSS positioning, CAN/Modbus adapters, firmware programmers, tuners,
cameras, remote USB imports and recovery disks still need attached-device
acceptance. Positive parser/startup/synthetic tests do not prove physical writes,
radio reception, an RTK fix, phone authorization or restore compatibility.

The installed ADB lacks modern TLS wireless pairing; network ADB needs an enabled
TCP endpoint. Fastboot and ideviceinstaller were absent in native discovery.
Existing Apple restore support depends on installed libraries and device support.

The router has about 121 MiB RAM and one CPU core. Two simultaneous tool jobs and
selected-device ownership remain justified constraints. Image files need extroot
capacity; disk-to-disk recovery avoids that by writing directly to an external
block target. Alternative mounted filesystem destinations are not implemented.
Monitor sessions share the current channel when a radio carries live interfaces.
Protected extroot/swap/modem hub ports cannot be power-cycled by unrelated tools.

## Publication and deployment evidence

The release was published to GitHub `main`, `feature/field-console-v3` and the
annotated `v3.0.0` tag at `6dd6e56db7979ba396f4a87c9351d7c72efef9c2` before
installation. The final documentation commit advances main without changing
any application files. The repository contains no GitHub Actions workflow;
validation ran locally and on the actual router.

The three CAN userspace packages (`canutils-candump`, `canutils-cansend`,
`canutils-canplayer`, each 2021.08.0-2/mips_24kc) were installed from the inspected
native feed after all checksums passed. No kernel or core library was replaced.

Application installation completed on September 13, 2026. The fresh rollback
snapshot is `/root/ddk-backups/20260913T224532Z-field-console-v3`. rpcd ACLs were
reloaded; there was no reboot or network/service restart. All nine protected
configuration files matched the pre-installation hashes. All 57 deployed files
matched the published source by SHA-256. GL.iNet, LuCI, the /ddk shortcut,
Tailscale, extroot and active swap passed post-installation checks.

The installed `router-verify.sh` passed all 78 schemas, malformed target/PID
rejection, native finite and continuous loopback jobs, stop/preserved artifacts,
case save, exact test-job deletion, web endpoints and configuration preservation.
Both isolated staging trees and their transfer archive were removed after native
validation; the deployment staging tree and rollback snapshot were retained.

The installed authenticated browser pass completed successfully: all 15 pages at
1440/390/320 pixels, the 17 representative expanded forms, Android TCP transport,
actual loopback start/stop/save/download/reuse, a real sealed upload, retention
settings, file ACL rejection and the /ddk shortcut. The transient authentication
session was destroyed. All 39 TCP/UDP listener entries matched the installation
snapshot. The public browser proof job and its two inputs were removed using exact
job identity, artifact inode and known fixture content, preserving operator data.
The final audit again confirmed all 57 source hashes, protected configuration,
management interfaces, Tailscale, extroot and swap, with zero active application
workers or helpers.

To restore the previous application, run from this checkout with the private
router SSH connection open:

```sh
DDK_TARGET=root@100.122.115.85 \
DDK_SSH_CONTROL_PATH=/run/user/1000/ddk-router-1000/control \
./rollback.sh /root/ddk-backups/20260913T224532Z-field-console-v3
```

Application rollback retains saved cases/inputs and the separately installed CAN
utilities. Those utilities add no boot services. The snapshot restores the previous
application files, removes helpers introduced by v3 and reloads rpcd ACLs.
The earlier deployment history is in `V2-DEPLOYMENT-HISTORY.md`.
