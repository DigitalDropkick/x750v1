# Operator Mode

## Status

Version 2.1 introduces the reusable Operator Mode action contract and currently migrates Nmap, tcpdump, iperf3, RTL-433, UVC still capture, general-purpose serial, GPS/GNSS, Android ADB, and Apple normal/recovery/DFU/restore workflows to it. It also adds an authenticated DDK-controlled input staging boundary consumed by ADB and Apple, plus isolated action-declared extroot workspaces. This source is on the `feature/operator-mode-v2.1` branch and has not been deployed to the production GL-X750. Version 2.0 remains the production-accepted baseline.

Operator Mode does not expose a shell. The browser sends typed values for one exact action ID; the backend validates every value and constructs the native argument vector from server-owned code.

## Request lifecycle

1. The authenticated client calls `ddk-console action describe ACTION_ID`.
2. The backend returns the server-owned schema plus live choices such as interfaces, assigned addresses, or congestion-control algorithms.
3. The browser submits a base64url-encoded UTF-8 JSON envelope with exactly `{"version":1,"options":{...}}` to `action prepare`.
4. The backend rejects unknown envelope keys, unknown option keys, wrong types, malformed targets, unsupported enum values, command/control characters, and values outside action-specific limits.
5. One exact builder in `operator-actions.lua` or the size-isolated `operator-apple.lua` converts the normalized values into a literal argv array, safe metadata, artifact/workspace declarations, locks, wall limit, and any target-bound confirmation requirement.
6. The backend stores that plan below mode-0700 `/tmp/ddk/prepared/` for at most five minutes and returns only the prepared ID, normalized review data, artifacts, and server-built argv preview.
7. The browser shows the exact target and material options. Consequential plans require the operator to type the exact server-generated phrase.
8. `job start PREPARED_ID [CONFIRMATION]` atomically claims the prepared request. It is single-use even when confirmation fails.
9. The backend independently checks the action-to-worker-to-executable mapping, resolves only registered `@JOB@/fixed-name`, `@ARTIFACT@/fixed-name`, `@UPLOAD@/generated-id`, and `@WORK@/declared-name` placeholders, persists a newline-delimited argv file, acquires locks, and starts one exact allowlisted family worker.
10. The worker rechecks its action, executable, metadata, target or interface where applicable, bounds the native process, supports DDK-owned cancellation, validates artifacts, and releases locks through its exit trap.

The browser never sends a native command, executable path, output path, PID, or shell fragment. The backend never evaluates the JSON as Lua and never concatenates it into shell syntax.

## Shared contract

Schemas use reusable field types: `boolean`, `enum`, `target_list`, `integer_list`, `port_expression`, `integer`, `number`, `text`, and `multiline`. Fields can supply defaults, bounds, help, advanced visibility, conditional visibility, and live server-derived choices. A manifest opts into this transport with `"parameter_schema":"operator-v1"`, but that declaration is descriptive only. Execution also requires:

- one exact action schema and builder in a non-executing Operator Mode module;
- one exact `operator_backends` entry in `ddk-console`;
- a fixed worker implementation in `ddk-job-worker` or an exact allowlisted family worker;
- a reviewed enabled-action list entry;
- GUI review and confirmation handling;
- router, browser, negative-input, cancellation, and artifact tests.

Risk class is presentation and review metadata. `ACTION`, `SECURITY`, and `DISRUPTIVE` do not disable an otherwise reviewed action. `scripts/enabled-disruptive-actions.txt` is the explicit review list for enabled disruptive actions.

## Prepared plans and audit metadata

Prepared plans are mode 0600 and expire after five minutes. Claiming uses an atomic directory rename so two requests cannot start the same plan. The confirmation value is compared exactly and is discarded; it is not written to job metadata.

Job metadata records only normalized validated options, a concise target summary, a shell-escaped display preview, declared artifacts, action class, and whether Operator Mode was used. The executable argv is written as one literal argument per line for the worker. Browser input can neither add a newline nor create a second argument through quoting.

## Locks, cancellation, and limits

The backend atomically acquires one of two global job slots and any action singleton or shared hardware/resource lock. Lock directories record the generated DDK job ID, support stale-owner recovery, and are released after setup failure, normal completion, failure, or cancellation.

Cancellation still accepts only a generated job ID. The backend verifies the recorded worker PID and exact worker/job command line before sending `TERM`; the worker terminates only its tracked native child. There is no generic signal endpoint.

The common ceilings remain two active jobs, 20 retained job directories, four-hour job cleanup, 128 KiB displayed stdout, and 32 KiB displayed stderr. Each operator action adds its own wall, child-output, and artifact ceilings.

## Artifact boundary

Native output files use fixed action-owned names. Small artifacts remain below the generated mode-0700 `/tmp` job directory; large Android artifacts use a matching mode-0700 directory below `/overlay/ddk-field-console/artifacts/` so they cannot exhaust RAM-backed `/tmp`. The backend substitutes no arbitrary path, advertises only declared regular files after successful completion, enforces per-type/storage/global size limits and extroot free-space reserve, and exposes downloads only through authenticated `cgi-download` ACL patterns.

The first supported files are:

| Action | Fixed artifacts | Limit |
| --- | --- | --- |
| Nmap | `nmap.nmap`, `nmap.xml`, `nmap.gnmap` | 1 MiB text/grepable, 2 MiB XML |
| tcpdump | `capture.pcap` | 8 MiB and valid PCAP magic |
| iperf3 | `iperf3.json` | 2 MiB and valid JSON |
| RTL-433 | `rtl433.jsonl`, `rtl433.csv`, `rtl433.txt`, `rtl433.cu8` | format-specific bounded decoded or raw receive data |
| UVC still | `snapshot.jpg`, `snapshot.png` | bounded image with native type/magic validation |
| Serial | `serial.bin` | bounded raw received bytes |
| GPS/GNSS | `gnss.raw`, `gnss.decoded` | bounded receiver and decoder output |
| Android ADB | `android-logcat.txt`, `android-bugreport.txt`, `android-pull.bin`, `android-backup.ab` | 8 MiB log, 256 MiB bugreport/pull, 1 GiB validated backup |
| Firmware | `firmware-read.hex`, `firmware-read.bin`, `firmware-dfu-read.bin`, `firmware-serial-read.bin` | 256 MiB action-owned backup ceiling |
| Storage | `storage-badblocks.txt`, `storage-image.raw`, `storage-image.sha256`, `recovered-files.tar` | 1 MiB list, selected image length up to 16 GiB, 8 GiB recovery archive ceiling |
| Apple | `apple-screenshot.tiff`, `apple-syslog.txt`, `apple-restore.log` | 64 MiB TIFF, 32 MiB syslog, 16 MiB restore log |

The browser validates the generated job ID and accepts only metadata-provided fixed names matching its own safe-name grammar. Files up to 16 MiB are fetched and byte-count verified in memory; larger reviewed files use native authenticated POST download streaming so a 121 MiB router page does not buffer them. There is no arbitrary router-file read or write API.

## Authenticated input staging

Workflows that need a local package or image use a separate exact-ID lifecycle rather than a browser or router path:

1. The browser reserves one upload by kind, validated basename/extension, and declared byte size through `ddk-console upload reserve`.
2. The backend creates one mode-0700 directory below `/overlay/ddk-field-console/uploads/` and returns only its exact `payload.bin` path.
3. Native LuCI `cgi-upload` writes that one path under an exact rpcd ACL. The UI enforces the selected kind's size before transmission.
4. `upload finalize` requires a regular file with the exact declared size, atomically renames it to `sealed.bin`, closes the former write path with a directory sentinel, validates ZIP magic for Android/Apple archives, computes SHA-256, and writes mode-0600 metadata.
5. Native actions select the generated upload ID. Their backend and worker must revalidate kind, sealed path, size, hash, lifetime, and target binding before use; they never accept the original filename as an execution path.

Firmware/device, Android package, and Apple recovery inputs are limited to 256 MiB; Android backups are limited to 1 GiB; Apple AP tickets to 1 MiB; IPSW archives to 12 GiB; and storage/recovery images to 16 GiB based on the 28 GiB extroot, extraction workspace, and protected free-space reserve. At most 10 inputs are retained. Reservations expire after one hour and sealed files after 24 hours. Active input locks prevent expiry cleanup while a job owns a file. Listing and deletion accept only generated upload IDs. No file is published below `/www`, and there is no arbitrary router path selector.

The installed `cgi-upload` writes before DDK finalization, so its native transport cannot abort at the declared per-kind ceiling mid-stream. The browser enforces the ceiling before upload and finalization rejects a mismatch. A future custom streaming CGI would be required for a hard server-side byte cutoff during transfer itself.

## Migrated tools

### Nmap 7.91

The exact target binary is `/usr/bin/nmap`. The schema provides validated target/exclude lists, IPv4/IPv6, discovery, SYN/connect/UDP and other installed scan modes, ports/top/fast selection, host-discovery probes, timing, DNS behavior, service/version and OS detection, traceroute, exact reviewed NSE categories, retry/rate/delay/timeout controls, source/fragmentation fields, verbosity, and text/XML/grepable/all artifact output. Up to 64 explicit targets is a request-size/resource bound; CIDR targets are not artificially clamped to `/24`.

Vulnerability-script, fragmentation, and bad-checksum plans require target-bound confirmation. The worker reasserts the exact binary and output paths, applies the independent wall limit, tracks cancellation, and validates every generated artifact.

### tcpdump 4.9.3 / libpcap 1.10.1

The exact target binary is `/usr/sbin/tcpdump`. The interface selector is populated from the live router rather than hard-coded to `br-lan`; `any` is supported because the installed binary reports it. The schema includes one validated BPF expression, duration/count, snap length, promiscuous choice, direction, name resolution, timestamp and payload display, verbosity, immediate mode, buffer size, decoded output, PCAP, or both.

The filter is passed as one argv element and compiled with the exact installed tcpdump before capture. The worker records and compares interface flags, applies time/count/file ceilings, tracks cancellation, validates PCAP magic, and optionally decodes the completed PCAP through a second fixed tcpdump argv. Promiscuous or payload/PCAP capture requires exact target-bound confirmation.

### iperf3 3.11

The exact target binary is `/usr/bin/iperf3`. Client and temporary server modes support host, port, TCP/UDP, duration/bytes/blocks, parallel streams, bitrate, reverse/bidirectional operation, version family, current local bind address/device, interval/omit/buffer/window/MSS, no-delay, zero-copy, don't-fragment, congestion algorithm, TOS, connect timeout, server output, one-off and server bitrate limit, plus JSON output.

Server mode must bind to an address currently assigned to the router and requires target-bound confirmation. The worker revalidates that address immediately before launch, keeps the server inside the requested wall window, defaults to one-off behavior, tracks cancellation, and leaves no idle iperf listener.

### Hardware-bound receive and capture tools

RTL-433 20.11 accepts a live reviewed tuner selection plus frequencies, sample rate, gain, PPM correction, decoder IDs, analyzer/metadata choices, duration, decoded format, and bounded raw I/Q where supported by that exact release. Network outputs and `rtl_tcp` remain excluded because DDK owns local artifacts and creates no radio listener.

fswebcam 20140113 accepts a live reviewed UVC node, JPEG/PNG, bounded native resolution, frames/skip/delay, quality, palette/input/FPS, transforms, and banner choice. The worker revalidates the device immediately before capture and produces only a fixed DDK-owned artifact; camera streaming daemons remain off.

socat 1.7.4.1 with stty 9.0 accepts a reviewed non-EC25 USB serial node, baud/data/parity/stop/flow settings, receive or transmit-and-receive, bounded duration/bytes, and text/hex preview. Transmit input travels as validated private hex, is never job metadata, and is removed after use. The worker independently rejects every Quectel EC25 port and restores the original tty state on completion, failure, or cancellation.

GPS/GNSS uses exact `/bin/dd` receive plus gpsdecode 3.23.1. It accepts a live reviewed non-EC25 receiver node, duration/byte limit, decoder mode/type options, position summary, and raw/decoded artifacts. It starts no gpsd service, changes no serial state, and makes no correction/network request.

### Android ADB 1.0.32

The backend correlates live `adb -P 5038 devices -l` transports with the conservative USB ADB identity inventory. It exposes state/serial/devpath, fixed `getprop` and package-list commands, logcat, bugreport, pull, backup, push, APK install, uninstall, restore, reboot, root, remount, USB mode, and TCP mode through exact structured builders. It never accepts arbitrary `adb shell` text.

Every ADB discovery/job acquires the same ADB resource lock, uses a temporary server on DDK-reserved localhost port 5038, refuses an occupied port, never uses `-a`, and kills/verifies the server on completion, failure, or cancellation. Device-changing actions require an exact target/material confirmation. File-input actions acquire the sealed-upload lock and revalidate path, kind, mode, size, and SHA-256 in both backend and worker. See [ANDROID-ADB.md](ANDROID-ADB.md).

### Apple mobile, recovery, and restore

The exact target suite is libimobiledevice 1.3.0, usbmuxd 1.1.1, irecovery 1.0.0, and idevicerestore 1.0.0. Five structured actions cover normal-mode information/diagnostics, screenshot/syslog artifacts, pairing/settings/power/location/recovery transitions, read-only and device-changing recovery/DFU operations, and IPSW update/erase/no-action with the advanced flags advertised by the installed restore help.

Normal-mode jobs start a DDK-owned foreground usbmuxd only on demand, require an exact fresh `idevice_id -l` UDID match, and terminate only the helper PID they own. Recovery/DFU jobs require a sysfs-derived ECID and successful exact `irecovery -i ECID -q` preflight. Restore uses an isolated mode-0700 extroot cache workspace, checks the 100 MiB free-space reserve throughout the job, and removes cache/helper/locks on every exit. See [APPLE-OPERATOR.md](APPLE-OPERATOR.md).

### Firmware programming and storage recovery

Four firmware actions cover exact installed OpenOCD, AVRDUDE, dfu-util/dfu-programmer, STM32Flash, BOSSA, and LPC21ISP functionality. They select only reviewed live USB or non-EC25 serial targets, use server-selected installed configs/part lists, bind sealed image IDs and hashes, produce fixed backup artifacts, and require exact confirmation for program/write/erase/reset/boot/security operations. OpenOCD's command file is generated server-side and disables its three listener ports.

Five storage actions cover SMART/read-only filesystem/media inspection, confirmed repair/non-destructive media testing, byte-range raw imaging, confirmed raw restore with optional comparison, and file-only SquashFS stat/list/recovery. The inventory and worker both exclude system, extroot, swap, non-USB, wrong-size, or impermissibly mounted media. See [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md).

## Compatibility and remaining migrations

The existing fixed Nmap, tcpdump, RTL-433, camera, and GPS workers remain for backward compatibility and regression tests, but the v2.1 UI uses the structured workflows. Existing CAN, cellular, identity, report, deployment, rollback, GL.iNet, LuCI, Tailscale, extroot, and swap behavior remains preserved until each family is deliberately migrated.

The v2 SSH handoff documents are retained as historical/fallback references. They no longer define the product boundary. CAN, Modbus/industrial, Bluetooth, smartcard, monitoring, automation, and other remaining families still require their exact installed-help audit, schemas, builders, workers, target checks, artifacts, and tests. Some installed Apple and firmware subtools still need additional target-specific archive/secret/PTY/config protocols documented in [APPLE-OPERATOR.md](APPLE-OPERATOR.md) and [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md). Missing hardware or executable payloads remain honest blockers; the action class by itself is not one.
