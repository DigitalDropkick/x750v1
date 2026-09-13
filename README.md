# Digital Dropkick Field Console v3

An authenticated LuCI dashboard for the GL.iNet GL-X750 field appliance. Version 3 expands the installed native tools through structured forms, persistent cases, reusable inputs, and configurable capture/session budgets. The registry contains 24 modules and 92 enabled actions, including 78 structured workflows. These counts describe controls, not attached-hardware compatibility.

Open **http://192.168.8.1/ddk** from the router LAN, or **http://100.122.115.85/ddk** through the configured Tailscale connection. Sign in with LuCI. The GL.iNet administration interface remains at the address root.

## Using v3

1. Open **Jobs** for Network Discovery, ARP Discovery, Android Tools, Packet Capture, Loss and Latency, Serial Console, Cellular Diagnostics, or Recovery Imaging. **Tools** provides the full registry.
2. Select the target and native operation. Common controls appear first; advanced parameters and browser presets are expandable. Missing hardware or one missing utility does not prevent opening the form. Execution checks the selected operation.
3. Choose **Validate & Review**, inspect the exact target and command preview, and start the job. Consequential operations request the displayed target phrase.
4. **Stop and Keep Results** preserves available output. **Save Across Reboots** creates a persistent case; **Name Case**, **Export Case**, and artifact reuse support subsequent work. Incomplete artifacts remain labelled.
5. **Settings** manages retention and uploaded inputs. Zero disables the selected cleanup limit. Saved cases remain until explicitly deleted. Input hashing runs outside the HTTP request and reports progress.

## Expanded capabilities

| Family | v3 controls |
| --- | --- |
| Network | Installed Nmap NSE scripts and private script arguments, presets, ARP discovery, IPv4/IPv6 loss/latency sessions, DNS queries and zone transfers |
| Android | USB interface recognition independent of vendor, network ADB, properties/packages/dumpsys/logcat, files and directories, split APK installation, application/device management |
| Capture and wireless | Larger extroot PCAPs, rotating captures, partial-result reuse/replay, concurrent monitor interfaces on the current channel, saved-file wireless analysis/decryption |
| Cellular | Modem diagnostics, connection/mode controls, EC25 AT/GNSS operations, APN/profile changes with timed UCI rollback and explicit keep confirmation |
| Serial and automation | Continuous device-specific serial console, text/hex transmission, file transfer, MQTT subscribe/publish/retained-message controls |
| Bluetooth and GNSS | Adapter/service/GATT controls, pairing and connections, receiver configuration, temporary gpsd and RTKLIB sessions, NTRIP corrections |
| CAN and Modbus | CAN bitrate/link setup, filtered capture, transmit and replay; Modbus TCP/RTU FC 1/2/3/4/5/6/15/16 with polling and optional write/readback |
| Firmware | OpenOCD readback/debug/target control, AVR memories/fuses, native DFU/serial programmers, FTDI EEPROM backup/build/write, installed flashrom-usb workflows |
| Storage | Partial/resumable ddrescue images, offset-aware verification, recovery directly between two selected external drives, existing SMART/filesystem/SquashFS tools |
| Radio and camera | Native-supported tuner catalogue and exact serial/index resolution, SDR benchmark/IQ stream, longer receive sessions, per-camera ownership, controls and video recording |
| Other tools | Persistent forensic input reuse, hex inspection, selected-process tracing/GDB, bandwidth/resource sessions, OTP/stoken, topology-aware USB power and native-compatible USB/IP client |

Existing Apple normal/recovery/restore controls remain available. Newer phones still depend on the capabilities of the installed native libraries. Unfamiliar USB programmers can be explicitly identified in the advanced form; selected devices are revalidated before execution.

## Architecture and constraints

The application uses Lua 5.1, LuCI/nixio, small JavaScript, existing native executables, and small Python adapters. There is no permanent dashboard daemon or additional web framework. Inputs are validated server-side and passed as literal arguments. LuCI authentication, target identity, job-owned cancellation, private inputs and protected-router topology remain part of execution.

The router has about 121 MiB RAM and one CPU core. Two tool jobs may run concurrently; conflicting device operations lock their selected resource. Sessions offer explicit budgets and durations; newer continuous workflows accept duration zero. Artifact writes retain at least 100 MiB free space. The 32-bit kernel does not enforce large file quotas above 4 GiB, so a 200 ms watchdog also checks registered output sizes and storage; a small final-write overshoot is retained as incomplete output.

Image files require adequate extroot capacity. Disk-to-disk recovery writes directly to a second external block device and stores only its recovery map/log on the router. This release does not mount external filesystems as alternative image-file destinations. Long transfers depend on available storage, power and a stable connection.

The native ADB build lacks modern wireless-pairing support; network ADB requires an already enabled TCP debugging endpoint. Fastboot and ideviceinstaller were absent during September discovery. No library/core firmware upgrades are part of v3. Actual Android/Apple phones, CAN/Modbus adapters, Bluetooth peripherals, programmers, tuners, cameras and external recovery disks require attached-device acceptance; synthetic/native startup tests do not establish physical-device compatibility.

Monitor capture shares the current channel on a radio carrying active interfaces. A different channel requires an unused radio. The USB hub port carrying extroot, active swap, or the modem cannot be power-cycled through an unrelated tool operation. Targeted cellular settings use the router's independent rollback timer.

## Validate, deploy and roll back

```sh
./scripts/validate-local.sh
```

This runs shell/JavaScript/JSON checks, Lua planner and policy tests, USB identity/topology fixtures, input hashing, offset comparison, USB/IP protocol tests, recovery failures and rollback fixtures. Native staged and browser evidence is recorded in [V3-IMPLEMENTATION.md](docs/V3-IMPLEMENTATION.md).

The authenticated connection helper keeps credentials out of files:

```sh
./scripts/connect-router.sh
```

With that connection open, authorized deployment and verification use:

```sh
export DDK_TARGET=root@100.122.115.85
export DDK_SSH_CONTROL_PATH=/run/user/1000/ddk-router-1000/control
./deploy.sh
./verify.sh
./scripts/verify-browser-authenticated.sh
```

The installer validates this exact appliance, backs up every replaced file, installs only project paths and reloads rpcd ACLs. It compares current protected configuration hashes before/after; it does not require historical configuration values or optional services to remain disabled. No reboot or network restart is required. The narrowly scoped `scripts/install-can-tools.sh` installs the three matching CAN userspace payloads with verified checksums; it performs no bulk upgrades.

Use the fresh backup path printed by deployment with `./rollback.sh /root/ddk-backups/<timestamp>-field-console-v3`. Rollback restores application files, removes newly introduced helpers and reloads ACLs. Saved case/input data remain on extroot. Earlier release evidence is retained in [V2-DEPLOYMENT-HISTORY.md](docs/V2-DEPLOYMENT-HISTORY.md) and the Phase acceptance documents.
