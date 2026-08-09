# Hardware Detection

Hardware probes are read-only, on-demand, and conservative. They never start a daemon or open a device.

## Probe sources

| Class | Current probe |
| --- | --- |
| USB | Parsed `lsusb` lines. |
| Serial detected | Existing `/dev/ttyUSB[0-9]+` and `/dev/ttyACM[0-9]+` nodes, attributed through sysfs. |
| Generic serial | True only for a future explicitly reviewed adapter identity; modem-reserved and unreviewed nodes do not satisfy this class. |
| Cellular modem | Capability state uses Quectel/`2c7c` USB presence. The enabled snapshot additionally requires exact `2c7c:0125`, `/dev/cdc-wdm0`, `qmi_wwan`, and attributed `wwan0`. |
| Video / UVC camera | Ready only when exactly one USB video device resolves through sysfs to `uvcvideo`, USB interface class `0e`, a valid VID:PID, and exactly one primary node with sysfs index `0`. The action separately confirms `Video Capture` with bounded `v4l2-ctl`. |
| RTL-SDR | Ready only when sysfs contains exactly one reviewed `0bda:2832` or `0bda:2838` device, its USB serial passes the strict character/length policy, and no interface driver is attached. |
| CAN | `ip -o link show type can` returns an interface. |
| Bluetooth | `/sys/class/bluetooth/hci[0-9]+` exists. |
| I2C | Existing `/dev/i2c-*` nodes. |
| SPI | Existing `/dev/spidev*` nodes. |
| GPS/GNSS | USB descriptor contains GPS, GNSS, or u-blox. |
| Android | USB descriptor contains Android, Google, or Samsung. |
| Apple mobile | USB descriptor contains Apple or vendor ID `05ac`. |
| Smart card/token | USB descriptor contains smart-card, CCID, Yubico, or YubiKey indicators. |
| Programmer/debugger | USB descriptor contains known J-Link, CMSIS-DAP, FTDI, STMicroelectronics, or Atmel indicators. |
| USB storage | `/sys/block/sda` exists. |

## Important limitations

- A serial node proves a serial-class device, not that it is safe or appropriate for a given industrial tool. The current Quectel modem exposes four nodes, all classified `MODEM RESERVED`, and none satisfies the generic serial hardware class.
- The attribution probe reads sysfs only and never opens `/dev/ttyUSB*` or `/dev/ttyACM*`. It records interface numbers but deliberately does not infer AT, GNSS, diagnostic, or modem roles without reviewed vendor evidence.
- A non-EC25 serial node is `UNREVIEWED SERIAL`, not automatically general-purpose. This prevents a newly attached device from becoming an executable target merely because a node appeared.
- Most general USB classes still use conservative descriptor matching and may have false positives or negatives. RTL-SDR uses an exact reviewed VID:PID list and additional serial/driver readiness checks. Camera uses driver/interface/topology validation rather than accepting an arbitrary video node.
- A compatible-looking RTL-SDR with a different VID:PID remains unreviewed and cannot enable the receiver. Multiple approved dongles are deliberately ambiguous and also remain unavailable until a future explicit selection model exists.
- A UVC device with several nodes is accepted only when exactly one node reports sysfs index `0`. Multiple physical UVC devices or multiple primary nodes are deliberately ambiguous. The worker then confirms V4L2 capture capability and refuses a node already open by another process.
- Hardware presence is not service health. The console does not start gpsd, Bluetooth, camera, SDR, CAN, or serial services to improve a status color.
- Installed kernel support is not equivalent to attached hardware.
- Android detection does not run `adb devices`, because doing so may start the ADB server.
- GPS detection does not infer GNSS from an arbitrary serial port.
- Cellular capability presence alone cannot authorize a query; the snapshot independently validates the exact EC25-AF management topology before opening the device.

## Extending detection

Add a symbolic class to the backend's hardware snapshot and the probe-ID allowlist. The manifest may reference only that symbolic value. Never place a shell command in `status_probe`.

New detection must be:

- read-only;
- bounded and fast;
- safe when a device disappears mid-probe;
- independent of starting a service;
- documented with false-positive and false-negative behavior.
