# GPS / GNSS Position Snapshot

Version 1.8 adds one hardware-gated, receive-only `gps.snapshot` ACTION workflow. It does not start `gpsd`, use NTRIP, change a serial setting, send a receiver command, or make a network request.

## Hardware gate

The backend and detached worker independently require:

1. exactly one USB device with a GNSS-identifying descriptor or the reviewed u-blox vendor ID `1546`;
2. exactly one attributed `/dev/ttyUSBN` or `/dev/ttyACMN` node;
3. one reviewed USB serial driver: `cdc_acm`, `ftdi_sio`, `cp210x`, `pl2303`, `ch341`, or `usbserial`;
4. no process with the selected node open; and
5. the already-installed `/usr/bin/gpsdecode`.

The Quectel EC25-AF (`2c7c:0125`) is explicitly excluded. Its four `option`-driver serial functions remain `MODEM RESERVED`; the console never guesses that one is a GNSS port.

Multiple receivers or multiple attributed nodes fail closed as ambiguous. A serial node without a reviewed USB GNSS identity never satisfies the gate.

## Fixed receive profile

The worker derives the device from sysfs and accepts no browser arguments. It performs one read-only open through `/bin/dd`, bounded by:

- 15 seconds;
- 32 KiB raw input;
- one active GPS job and one shared GPS resource; and
- 32 KiB final text output.

`gpsdecode -d` filters the input to checksum-valid NMEA. The console then renders only position, receiver time/date, fix quality, satellite count, HDOP, altitude, speed, and course. Raw NMEA and decoder scratch files are deleted before completion, failure, or authenticated cancellation.

## Privacy boundary

The UI requires an explicit confirmation because precise location may identify a customer, vehicle, work site, or operator. Position output exists only in the transient job directory and is eligible for cleanup after four hours. DDK system reports do not include coordinates or raw GNSS data.

## Deliberately excluded

- automatic or on-demand `gpsd` service activation;
- listening on TCP 2947 or any new port;
- serial baud, parity, flow-control, or protocol changes;
- receiver initialization or binary-protocol commands;
- NTRIP, RTK correction streams, uploads, or external lookups;
- browser-selected devices, durations, baud rates, commands, or output paths; and
- use of the cellular modem's reserved serial ports.

Live fix and cancellation acceptance remain pending an approved external USB GNSS receiver. With no reviewed receiver attached, the UI reports `HARDWARE REQUIRED`, the backend refuses before job creation, and the worker independently fails closed.
