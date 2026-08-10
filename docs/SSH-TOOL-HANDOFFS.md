# Full Native Tool Use over SSH

> v2 compatibility/fallback reference: this document describes the production-accepted 2.0 SSH workflows. It no longer defines the desired GUI boundary. Under [Operator Mode](OPERATOR-MODE.md), practical native functionality should move into exact structured actions when its targets, parameters, lifecycle, artifacts, and recovery behavior can be represented safely. The GUI will still never become a generic shell.

The currently deployed v2 Field Console is a safe authenticated preflight and handoff layer. The local v2.1 feature branch adds structured Android ADB and Apple normal/recovery/DFU/restore workflows; firmware and native subflows that require a future PTY/archive/secret protocol still use this fallback reference.

- browser-safe identification and readiness;
- full operator-controlled CLI use through SSH.

The console does not modify or reduce any installed program’s native functionality. It displays commands as escaped text and never sends them to a shell. Connect from the workstation with:

```sh
ssh root@192.168.8.1
```

Use one attached customer device or target at a time whenever a tool’s own selection semantics are ambiguous.

## Current executable matrix

This matrix was read from the target before v2 deployment:

| Tool | Target path/state |
| --- | --- |
| ADB | `/usr/bin/adb` |
| fastboot | unavailable |
| idevice_id | `/usr/bin/idevice_id` |
| ideviceinfo | `/usr/bin/ideviceinfo` |
| idevicepair | `/usr/bin/idevicepair` |
| irecovery | `/usr/bin/irecovery` |
| idevicerestore | `/usr/bin/idevicerestore` |
| usbmuxd | `/usr/sbin/usbmuxd` |
| OpenOCD | `/usr/bin/openocd` |
| AVRDUDE | `/usr/bin/avrdude` |
| dfu-util | `/usr/bin/dfu-util` |
| dfu-programmer | `/usr/bin/dfu-programmer` |
| STM32Flash | `/usr/bin/stm32flash` |
| BOSSA | `/usr/bin/bossac` |
| LPC21ISP | `/usr/sbin/lpc21isp` |
| FTDI EEPROM | `/usr/bin/ftdi_eeprom` |
| flashrom | package record exists, executable unavailable |

The UI generates this readiness list live and may therefore differ after an intentional future package repair.

## Android / ADB

The installed ADB is version 1.0.32. Its exact help output confirms these command families:

```sh
adb devices -l
adb shell
adb pull REMOTE_PATH LOCAL_PATH
adb push LOCAL_PATH REMOTE_PATH
adb install LOCAL_APK
adb reboot bootloader
adb help
adb kill-server
```

The inspected 1.0.32 help does not advertise `sideload`, so the v2.1 GUI does not assume that newer syntax.

The first transport command may start ADB’s local server on port 5037. Do not use `adb -a`: the installed version documents that option as listening on all interfaces, which conflicts with the appliance’s no-WAN-exposure policy. Run `adb kill-server` when the session is finished and confirm no listener remains.

Shell, push, install, reboot, backup, restore, port-forwarding, and TCP-device connections can alter or expose customer data. Confirm the exact device selection, screen authorization/trust state, backup plan, and written scope before use. Prefer the structured v2.1 actions for the represented operations; see [ANDROID-ADB.md](ANDROID-ADB.md).

Fastboot is not currently installed. DDK does not install or substitute it.

## Apple normal, recovery, and DFU modes

Normal-mode inventory and pairing:

```sh
idevice_id -l
ideviceinfo -u DEVICE_UDID
idevicepair -u DEVICE_UDID validate
idevicepair -u DEVICE_UDID pair
```

Pair only after the customer has authorized the host and accepted the trust prompt. Pairing records and UDIDs are private service data.

Recovery/DFU inspection and full references:

```sh
irecovery -q
irecovery --help
idevicerestore --help
usbmuxd -f -v
```

`irecovery` can send files, commands, scripts, exploit payloads, resets, and mode changes. `idevicerestore` can update or fully erase a device; its installed help explicitly warns that `--erase` destroys user data and `--no-input` disables protective prompts. Do not run restore commands until model, ECID/UDID, device mode, signed IPSW, baseband implications, backup state, stable power, recovery path, and written authorization are all established.

`usbmuxd -f -v` is a foreground diagnostic process, not a boot-time recommendation. Stop it with Ctrl-C after the operator session. Do not enable a new daemon or listener merely to improve a dashboard status.

## Firmware and embedded targets

Always record before connecting:

- exact programmer and target part number;
- target voltage and whether the tool or target supplies power;
- pinout, ground, reset, and boot-strap state;
- interface and clock/baud assumptions;
- flash geometry, protection/fuse/lock state;
- image source and cryptographic hash;
- known-good backup/readback location;
- write verification and recovery procedure.

The exact installed help references are:

```sh
openocd --help
avrdude -?
dfu-util -l
dfu-util --help
dfu-programmer --help
stm32flash -h
bossac --help
lpc21isp
ftdi_eeprom --help
```

Typical native operation families—shown for planning, not executed by DDK—include:

```sh
# OpenOCD: requires exact interface and target configuration.
openocd -f interface/REVIEWED_ADAPTER.cfg -f target/REVIEWED_TARGET.cfg

# AVRDUDE: read/verify/write are selected by the -U operation.
avrdude -c PROGRAMMER -p PART -P PORT -U flash:r:backup.hex:i
avrdude -c PROGRAMMER -p PART -P PORT -U flash:v:image.hex:i
avrdude -c PROGRAMMER -p PART -P PORT -U flash:w:image.hex:i

# USB DFU: list first; upload/download semantics depend on target firmware.
dfu-util -l
dfu-util --help

# STM32 UART bootloader: read before any erase/write.
stm32flash -r backup.bin SERIAL_DEVICE
stm32flash -w image.bin -v SERIAL_DEVICE

# BOSSA: read or erase/write/verify after selecting the exact port/target.
bossac --help

# FTDI EEPROM: requires a reviewed config file and exact device selector.
ftdi_eeprom --help
```

Do not copy a generic write example directly into a customer job. Tool syntax alone cannot establish voltage safety, correct device selection, flash layout, option-byte/fuse consequences, or recovery feasibility.

## Relationship to the browser

Production v2 can request only six exact mobile/programmer INFO IDs: three identity snapshots and three static/full-CLI handoffs. The local v2.1 source preserves those INFO actions and adds exact structured controls; it still cannot submit a command string, executable path, router path, PID, or script.

The remaining disabled v2 GUI placeholders record unimplemented work:

- `apple.restore`
- `firmware.write`

`android.shell` was removed rather than exposed as arbitrary command text; represented Android work now uses `android.adb_diagnostics` and `android.adb_manage`. Apple’s former disabled restore placeholder is now backed by five real structured actions; its fallback remains relevant only for the explicitly unrepresented PTY/archive/secret workflows in [APPLE-OPERATOR.md](APPLE-OPERATOR.md). Firmware placeholders do not restrict SSH and must not be enabled cosmetically: each needs structured target controls, an exact validator/argv builder, a fixed worker, on-demand helper cleanup, authenticated file input where relevant, consequential confirmation, artifacts, cancellation, and tests. Until that implementation exists, SSH remains the firmware fallback.
