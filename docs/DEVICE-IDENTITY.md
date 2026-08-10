# Mobile Device and Programmer Identity

> Version 2.0 identity behavior remains valid and is preserved in 2.1. Its SSH-only handoff is now a fallback, not the final product boundary; see [Operator Mode](OPERATOR-MODE.md).

Version 2.0 adds three immediate authenticated INFO actions:

- `android.identify`
- `apple.identify`
- `firmware.identify`

They answer “what is attached?” without starting a device-management tool. Each action reads only `/sys/bus/usb/devices`, sanitizes every displayed string, and returns a bounded response directly to the authenticated browser. It creates no DDK job, temporary file, report field, log entry, daemon, listener, pairing record, or persistent identifier cache.

## Information shown

When a reviewed identity is present, the response may show:

- USB VID:PID;
- sanitized manufacturer and product descriptors;
- USB serial identifier;
- physical USB topology;
- negotiated link speed;
- interface number, class/subclass/protocol signature, and claimed kernel driver;
- conservative DDK classification.

USB serials and topology can identify a customer device. The UI requires an explicit privacy confirmation before an identity action. Output exists only in the current browser document and disappears when the result is replaced, the page is refreshed, or the operator navigates away.

The status and capability APIs expose only match counts and readiness reasons. They never include USB serials or the identity records themselves. DDK System Reports explicitly exclude the identity output.

## Android classification

An Android match requires both:

1. a known Android/mobile USB vendor; and
2. at least one reviewed signal:
   - ADB interface `ff:42:01`;
   - fastboot interface `ff:42:03`;
   - MTP interface `06:01:01`; or
   - an Android/mobile descriptor token.

This rejects a vendor match alone. The classifier does not run `adb devices`, because that can start the ADB server on port 5037. It does not open an ADB transport, request trust, pair, shell, pull, push, install, reboot, or enter a recovery mode.

## Apple mobile classification

An Apple mobile match requires vendor `05ac` plus an iPhone, iPad, iPod, Apple Mobile Device, DFU-mode, or recovery-mode descriptor. Apple-branded non-mobile devices do not match merely because the vendor ID is `05ac`.

The classifier does not start `usbmuxd` or run `idevice*`, `irecovery`, or `idevicerestore`. It creates no pairing record and sends no recovery or restore command.

## Programmer classification

Programmer/debugger identity uses a conservative reviewed table for common SEGGER, ST-LINK, CMSIS-DAP/DAPLink, Atmel/Microchip, Olimex, Altera USB-Blaster, Bus Pirate, Black Magic Probe, and Raspberry Pi Debug Probe identities, plus specific descriptive tokens.

Generic FTDI, USB-serial, hub, storage, modem, and Apple Bluetooth identities are not accepted simply because their vendor could also manufacture development hardware. The classifier never invokes OpenOCD, AVRDUDE, DFU utilities, flashrom, BOSSA, STM32Flash, LPC ISP, or FTDI EEPROM tooling.

## Bounded behavior

- At most 64 USB devices are inspected.
- At most 16 interfaces are retained per device.
- At most eight matching devices are rendered per response.
- Manufacturer/product fields are capped at 96 bytes.
- Serial identifiers are capped at 128 bytes.
- Control characters and non-allowlisted descriptor characters are replaced.
- The sysfs root is a source-code constant; the browser cannot submit a path.
- Missing or changing devices fail as unavailable metadata rather than becoming an execution target.

The module state is `READY / NO DEVICE` when the software is installed but no reviewed hardware is attached. Identity and fallback-reference actions remain usable so the operator can inspect the empty state and prepare before connecting hardware. Hardware-dependent ADB and firmware Operator actions remain disabled until the exact reviewed target class is present, then perform fresh live transport/topology correlation.

## Full tool access

DDK does not patch, replace, or weaken the installed CLI utilities. The companion `*.operator_guide` actions show executable readiness and supplemental copyable references, but execute none of them. Android, Apple, and firmware now have separate structured workflows documented in [ANDROID-ADB.md](ANDROID-ADB.md), [APPLE-OPERATOR.md](APPLE-OPERATOR.md), and [FIRMWARE-STORAGE-OPERATOR.md](FIRMWARE-STORAGE-OPERATOR.md); the guides remain fallbacks for native workflows that require a future PTY, archive, secret-input, target-specific config, or other unmodeled protocol. Live programming acceptance remains pending approved hardware.

## Acceptance model

Production verification includes:

- positive synthetic Android ADB, Apple recovery, and SEGGER programmer fixtures;
- deliberate Apple Bluetooth and generic FTDI false-positive fixtures;
- live no-device state on the target;
- malformed action and extra-argument rejection;
- unchanged ADB/mobile listener state;
- unchanged device-management process state;
- unchanged DDK job count;
- absence of identity fields from the DDK System Report;
- authenticated desktop and mobile UI checks.

Live customer-device and programmer acceptance remains hardware-specific. Before relying on a newly encountered model, compare the displayed descriptors and interfaces with the physical device and its service documentation.
