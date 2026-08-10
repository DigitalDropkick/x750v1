# Target Environment

Snapshot recorded by a read-only SSH discovery on 2026-08-09 and revalidated after extroot media migration the same day. Values below are confirmed unless explicitly marked as an inference.

## Identity

| Item | Confirmed value |
| --- | --- |
| Model | GL.iNet GL-X750 |
| Hostname | `GL-X750` |
| Board | `glinet,gl-x750-nor` |
| SoC | Qualcomm Atheros QCA9533 rev 2 |
| OpenWrt | 22.03.4, `r20123-38ccc47687` |
| GL.iNet firmware | 4.3.28 |
| Target / architecture | `ath79/nand` / `mips_24kc` |
| Kernel | 5.10.176 |
| LuCI base | `git-23.119.80898-65ef406` |
| Lua | 5.1.5 |
| ucode | 2022-12-02 build |
| Installed packages | 884 |

The board name contains `nor`, while the firmware release reports the `ath79/nand` target. Deployment verifies both the GL-X750 model and `mips_24kc` architecture instead of inferring storage layout from the board-name suffix.

## Storage, memory, and swap

- `/dev/sda1` is ext4 and is mounted at `/overlay` and `/mnt/extroot`.
- After migration, the replacement `/dev/sda1` provided 28.5 GiB total with 26.4 GiB available (2% used).
- `/tmp` had 57.4 MiB available of 59.2 MiB.
- Physical memory: 121,188 KiB total; 37,276 KiB was available during post-migration validation.
- Load averages were 1.36 / 1.65 / 1.91 roughly 19 minutes after the replacement card booted.
- Initial discovery found no active swap. Post-migration validation confirmed `/overlay/ddk-install.swap` active with 262,140 KiB total and 776 KiB used.
- A later reboot left the valid mode-0600 swapfile intact but inactive, confirming that boot activation was not configured. It was reactivated as a separate operator maintenance step before the 1.2.1 deployment.
- Phase 2A inspection found no existing swap UCI section. The exact installed fstools commit supports an absolute regular swapfile target through `config swap`, and the enabled `S11fstab` boot script invokes `/sbin/block mount`. Version 1.3.0 therefore uses one named `ddk_install_swap` entry plus a separate hash-guarded rollback; no DDK init script is added.

Deployment treats inactive swap as a failed safety preflight. The project never deletes, recreates, formats, resizes, stops, or silently activates the swap file. Persistence was proven on 2026-08-09: after an authorized reboot and attended power cycle, `/dev/sda1` returned as extroot and the native fstab path automatically activated `/overlay/ddk-install.swap` with 262,140 KiB total and default priority `-2`.

Operational note: the normal software reboot completed its preflight and `sync`, and the router went down, but it remained dark instead of restarting. A physical power cycle was required. Plan future maintenance reboots as attended operations until that device-specific behavior is separately diagnosed.

## Web and authentication topology

- nginx 1.17.7 is the active public HTTP/HTTPS server on ports 80 and 443.
- Its document root is `/www`, directory index is `gl_home.html`, and directory canonicalization allows a project-owned `/ddk` shortcut without changing nginx configuration.
- `http://192.168.8.1/` and `https://192.168.8.1/` returned the GL.iNet UI with HTTP 200.
- Unauthenticated `http://192.168.8.1/cgi-bin/luci/` returned HTTP 403 with `X-LuCI-Login-Required: yes`.
- The LuCI dispatcher, Lua templates, modern JavaScript views, menu JSON, and rpcd ACL directories are present.
- `uhttpd` is configured for LuCI on 8080/8443, but the only observed active uhttpd listener was the existing Prometheus exporter on `127.0.0.1:9100`. The public UI is therefore treated as nginx-fronted; no web-server configuration is changed.
- The nginx front end returned 404 for LuCI's `/ubus/` JSON-RPC route, with matching failures predating this project in the existing nginx error log. The console therefore uses LuCI's working authenticated `/cgi-bin/cgi-exec` (`fs.exec_direct`) path and does not alter nginx.
- LuCI session authentication uses `sysauth_http` / `sysauth_https`; the rpcd root login has wildcard read/write ACLs. Password material was redacted during discovery.

### Version 1.4 live acceptance

The Digital Dropkick brand-alignment release was deployed on 2026-08-09 with pre-change backup `/root/ddk-backups/20260809T222112Z-field-console-v1`. The production suite passed 24 checks with no warnings, and the authenticated browser suite passed every branded page at 320 px, 390 px, and desktop widths with no external requests, runtime errors, or horizontal document overflow. Source-to-router SHA-256 comparison found exact parity for every project file.

The final snapshot reported 45,620 KiB available RAM, load averages 1.68 / 1.35 / 1.24, 27,696,828 KiB free on extroot, the 262,140 KiB swapfile active at priority `-2`, Tailscale running, and zero DDK listeners or workers. Protected configuration hashes remained unchanged. These resource values are point-in-time verification evidence, not permanent operating expectations.

### Version 1.5 live acceptance

The bounded LAN metadata release was deployed on 2026-08-09 with pre-change backup `/root/ddk-backups/20260809T224048Z-field-console-v1`. The production suite passed 27 checks with no warnings, including capture cancellation and complete-window proofs. Authenticated browser validation passed at 320 px, 390 px, and desktop widths with all local brand assets loaded, both SECURITY workflows available, and no external requests, runtime errors, or horizontal document overflow. SHA-256 comparison found exact source-to-router parity for all 39 project files.

The final snapshot reported 45,336 KiB available RAM, load averages 1.32 / 1.28 / 1.19, 27,696,352 KiB free on extroot, and the 262,140 KiB swapfile active with 3,104 KiB used. Tailscale remained running; GL.iNet UI returned HTTP 200; LuCI retained its unauthenticated HTTP 403 boundary; and no DDK listener, DDK worker, or bounded-operation client remained. Protected configuration hashes remained unchanged. These resource values are point-in-time verification evidence, not permanent operating expectations.

### Version 1.6 live acceptance

The hardware-gated RTL-433 release was deployed on 2026-08-09 with pre-change backup `/root/ddk-backups/20260809T231004Z-field-console-v1`. With no reviewed tuner attached, the production suite passed 29 checks with no warnings: the backend refused before job creation, the worker independently failed closed, no receiver process ran, port 1234 remained closed, and the pre-existing UCI-disabled `rtl_tcp` configuration remained byte-identical. Authenticated browser validation passed at 320 px, 390 px, and desktop widths with `HARDWARE REQUIRED` shown and the ACTION controls disabled. All 39 project files matched source.

The acceptance snapshot reported 44,468 KiB available RAM, load averages 1.66 / 1.41 / 1.26, 27,695,868 KiB free on extroot, and the 262,140 KiB swapfile active with 3,104 KiB used at priority `-2`. Tailscale remained running; GL.iNet UI returned HTTP 200; LuCI retained HTTP 403 for unauthenticated access; and no DDK listener, DDK worker, or radio client remained. Live RTL-433 decode, stop, and resource profiling remain explicitly unverified until approved hardware is attached.

### Version 1.7 live acceptance

The hardware-gated camera-still release was deployed on 2026-08-09. The true pre-release v1.6 rollback backup is `/root/ddk-backups/20260809T233913Z-field-console-v1`; a second timestamped backup at `/root/ddk-backups/20260809T234128Z-field-console-v1` records the narrow ACL correction deployment. The default DDK rollback pointer was deliberately restored to the pre-release backup after verifying its backed version.

With no camera attached, the production suite passed 31 checks with no warnings. Both backend and worker refused before capture, no JPEG or camera process remained, `mjpg-streamer` and Motion stayed UCI/init-disabled, their configurations remained byte-identical, and listener state matched the final pre-deployment snapshot. The authenticated artifact proof downloaded only the exact transient job JPEG and denied `/etc/shadow`. Browser checks passed at 320 px, 390 px, and desktop widths with the camera module visibly `HARDWARE REQUIRED`, ACTION controls disabled, local brand assets loaded, and no external request, runtime error, or horizontal overflow. Visual screenshot review found the desktop and mobile layouts coherent and readable.

All 39 deployed project files matched source byte for byte. The final acceptance snapshot reported 44,804 KiB available RAM, load averages 1.51 / 1.45 / 1.27, 27,694,860 KiB free on extroot, and the 262,140 KiB swapfile active with 4,128 KiB used at priority `-2`. Tailscale remained running and GL.iNet UI/LuCI authentication remained healthy. Live still capture, cancellation during capture, image-quality judgment, and measured capture CPU/RAM remain explicitly unverified until one approved UVC camera is attached and the operator confirms authorization and consent.

### Version 1.9 Burn One live acceptance

The combined GPS/GNSS and passive CAN release was deployed on 2026-08-09 with pre-change v1.7 backup `/root/ddk-backups/20260810T003641Z-field-console-v1`. Deployment passed identity, OpenWrt/architecture, extroot, active swap, free-space, native LuCI, installed-tool, protected-hash, and local/staged syntax gates. It reloaded only rpcd ACLs; no service was restarted and the router was not rebooted.

The comprehensive suite passed 35 checks with no warnings. GPS/GNSS and CAN backend refusals occurred before job creation; both workers independently failed closed; no raw NMEA, decoded GNSS scratch, CAN frame file, GPS/CAN process, new listener, or configuration change remained. The GPSD UCI file stayed byte-identical and disabled. The CAN API/UI correctly reported both no physical interface and missing `candump` despite the installed empty `canutils` package record.

Authenticated Chrome verification passed the `/ddk` redirect, camera-artifact ACL isolation, every local brand asset, and the new disabled ACTION controls at 320 px, 390 px, and desktop widths with no external request, runtime error, or horizontal overflow. Visual review confirmed coherent mobile/desktop hierarchy. All 39 deployed files matched source byte for byte, and listener state matched the pre-deployment backup.

The final acceptance snapshot reported 44,320 KiB available RAM, load averages 1.73 / 1.58 / 1.28, 27,694,340 KiB free on extroot, and the 262,140 KiB swapfile active with 4,904 KiB used at priority `-2`. Tailscale remained running and GL.iNet UI/LuCI authentication remained healthy. Live GNSS fix/cancellation and CAN receive/cancellation/bus-impact acceptance remain pending approved hardware; CAN additionally requires a separately reviewed `candump` availability decision.

## Native LuCI conventions

This firmware contains both generations of LuCI application structure:

- Modern applications use `/usr/share/luci/menu.d/*.json`, `/usr/share/rpcd/acl.d/*.json`, and JavaScript views below `/www/luci-static/resources/view/`.
- `luci-app-ttyd`, `luci-app-nlbwmon`, and `luci-app-ser2net` use that modern pattern.
- `luci-compat` is installed and applications such as `luci-app-commands` still use Lua controllers and templates.
- Because nginx's `/ubus/` route is broken on this image, the console combines native menu JSON with an authenticated standalone Lua template and the existing `cgi-io` file-execution mechanism. This avoids a persistent rpcd plugin and any nginx change.

Relevant confirmed paths:

- `/usr/share/luci/menu.d/`
- `/usr/share/rpcd/acl.d/`
- `/www/luci-static/resources/`
- `/usr/lib/lua/luci/view/`
- `/usr/lib/lua/luci/`
- `/usr/libexec/`

## Installed application examples inspected

- `luci-app-commands`
- `luci-app-ttyd`
- `luci-app-nlbwmon`
- `luci-app-statistics`
- `luci-app-ser2net`
- `luci-app-mjpg-streamer`
- `luci-app-dump1090`

## Packet-capture capability

- `tcpdump` 4.9.3-4 is already installed at `/usr/sbin/tcpdump`; libpcap is 1.10.1 with TPACKET_V3.
- The fixed `arp or icmp or (ip and udp and (port 67 or port 68))` expression compiled successfully against `br-lan`.
- A three-second non-promiscuous capability trial left the interface flags exactly `0x1003` before, during, and after, exited at the deliberate timeout, and left no `tcpdump` process.
- The native LAN was up on `br-lan` at `192.168.8.1/24` during inspection.
- No package installation, interface mutation, PCAP file, or captured packet content was required for capability discovery.

## RTL-SDR / rtl_433 capability

- `rtl_433` 20.11-2 is installed at `/usr/bin/rtl_433`; `rtl-sdr` 0.6.0-2 supplies the local tuner tools and `librtlsdr` 0.6.0.
- The installed build accepts an explicit `/dev/null` configuration and documents serial-based device selection, fixed frequency/sample-rate controls, JSON output, metadata, raw-save disablement, and a built-in duration.
- No reviewed RTL-SDR USB ID, `/dev/dvb` node, DVB/RTL module, radio receiver process, or RTL-related listener was present during Phase 3B discovery.
- The packaged `rtl_tcp` init link exists, but `rtl_tcp.main.disabled='1'`; the service was not running and port 1234 was not listening. The console does not alter or invoke this service.
- BusyBox `ulimit -f` was verified in `/tmp` to enforce POSIX 512-byte block limits; the disposable probe was removed immediately.
- No tuner was opened, driver detached, module changed, service started, or package installed during discovery.

## UVC camera capability

- `fswebcam` 20140113-2, `mjpg-streamer` 1.0.0-5, Motion 4.3.2-1, `v4l-utils` 1.20.0-4, `v4l2tools` 0.1.8-1, and `v4l2rtspserver` 0.2.3-5 were already installed.
- `/usr/bin/fswebcam`, `/usr/bin/v4l2-ctl`, `/usr/bin/file`, `hexdump`, and `timeout` provide the required bounded still-capture and validation primitives; no package is needed.
- The `uvcvideo`, `videodev`, and videobuf2 kernel modules were already loaded, but no `/dev/video*` node or `/sys/class/video4linux` entry existed during Phase 3C discovery.
- `fswebcam`, `mjpg_streamer`, Motion, and `v4l2rtspserver` were stopped. Both the `mjpg-streamer` and Motion init services and their UCI enable flags were disabled. No camera port was listening.
- The native authenticated `/cgi-bin/cgi-download` endpoint is already present through `cgi-io`; version 1.7 grants only a strict DDK-job JPEG read pattern instead of adding a CGI or listener.
- No camera was opened, image captured, service started, listener created, config value revealed, or package installed during discovery.

## GPS/GNSS capability

- `gpsd` 3.23.1-2, `/usr/bin/gpsdecode`, `gpspipe`, `cgps`, `gpsctl`, RTKLIB's `rtkrcv`, and `ntripclient` were already installed during Phase 3D discovery.
- No external USB descriptor identified a GPS, GNSS, or u-blox receiver. The only serial nodes were the four EC25-AF modem-reserved functions; none was opened or reclassified.
- `/etc/config/gpsd` has `core.enabled='0'` and names `/dev/ttyUSB0`, which is modem-reserved. No `gpsd` process or TCP 2947 listener existed. Version 1.8 protects this configuration hash and never invokes the service.
- The installed `gpsdecode -d` accepted checksum-valid NMEA and rejected invalid-checksum test sentences, providing an on-device validation stage without a daemon or listener.
- No serial setting, receiver state, service, listener, NTRIP connection, network request, package, or configuration was changed during discovery.

## CAN capability

- `canutils` 2021.08.0-2 and `kmod-can` 5.10.176-1 are recorded as installed, but `opkg files canutils` lists no payload and no `candump`, `cansend`, or other CAN utility executable exists in the standard binary paths.
- No `/sys/class/net` entry reported ARPHRD_CAN type `280`, and `ip -o link show type can` returned no interface.
- The package database and installed system therefore cannot perform a `candump` capture today. Burn One must report that exact incomplete software/runtime state and must not install, replace, or force a package merely to enable the control.

## Android, Apple, and firmware-tool capability

- `adb` 1.0.32 is installed at `/usr/bin/adb`. `fastboot` is unavailable.
- `idevice_id`, `ideviceinfo`, and `idevicepair` are installed at `/usr/bin`; `irecovery` and `idevicerestore` are installed; `usbmuxd` exists at `/usr/sbin/usbmuxd`.
- `openocd`, `avrdude`, `dfu-util`, `dfu-programmer`, `stm32flash`, `bossac`, `lpc21isp`, and `ftdi_eeprom` are executable in the standard paths.
- The `flashrom-usb` package record exists, but `flashrom` is unavailable in the executable paths. The console reports that state and does not install a substitute.
- The exact installed help output was inspected for ADB, idevicepair, irecovery, idevicerestore, OpenOCD, AVRDUDE, both DFU tools, STM32Flash, BOSSA, and FTDI EEPROM. Help-only inspection left all related process and listener state unchanged.
- No reviewed Android, Apple mobile, or firmware-programmer USB identity was attached. The live topology remained the Quectel modem, USB storage, hub, and USB/IP virtual host controllers.
- Synthetic fixtures on the router's actual Lua 5.1/nixio stack accepted Android ADB `18d1:4ee7`, Apple recovery `05ac:12a8`, and SEGGER `1366:0105` identities while rejecting Apple Bluetooth `05ac:8290` and generic FTDI `0403:6001` examples.
- A staged v2 backend against live sysfs completed all six new INFO actions with zero DDK jobs, device-tool processes, or ADB/mobile listener changes. Production v1.9 files remained untouched during that pre-deployment proof.

## Network and remote-access baseline

- LAN: `br-lan`, `192.168.8.1/24`, up.
- WAN: `eth0`, DHCP, up; a second default route existed on `wlan-sta0` with a higher metric.
- Tailscale 1.32.3 returned a Tailscale IPv4 address and `tailscaled` was visible in the process table.
- No network, wireless, firewall, or Tailscale configuration was read into project source or changed.

## Hardware baseline

- USB: Quectel EC25-AF modem, Generic USB Storage, USB 2.0 hub, and USB/IP virtual host controllers.
- Serial: `/dev/ttyUSB0` through `/dev/ttyUSB3`; sysfs attributes all four to Quectel `2c7c:0125`, USB interfaces `00`–`03`, using the `option` driver. They are `MODEM RESERVED`, not general-purpose adapters.
- Video: no `/dev/video*` node.
- CAN: no CAN interface.
- Bluetooth: no active controller reported by `hciconfig`.
- I2C/SPI: no `/dev/i2c-*` or `/dev/spidev*` node.
- No RTL-SDR USB identifier was detected.
- No reviewed Android, Apple mobile, or firmware-programmer identity was detected.

### Cellular integration findings

- Modem: Quectel EC25-AF, USB `2c7c:0125`.
- Management: `/dev/cdc-wdm0`, driver `qmi_wwan`, attributed netdev `wwan0`.
- Serial functions: `/dev/ttyUSB0` through `/dev/ttyUSB3`; the console does not open them.
- Installed clients: `uqmi` 2022-05-04 and `qmi-utils`/`libqmi` 1.30.8.
- Active manager: `netifd`; no ModemManager or QMI proxy daemon was running during inspection.
- One-time read-only trials for operating mode, data status, signal information, and serving system completed while protected hashes and WWAN state remained unchanged.
- Subscriber identifiers, SIM content, APN/current settings, cell location, network scans, resets, and raw AT/QMI commands were not queried.

## Protected configuration baseline

The following SHA-256 values are verification evidence, not files this project may modify:

| File | SHA-256 |
| --- | --- |
| `/etc/config/network` | `fc86f6db509478753f7748bd42b8201a5af89b5dedf4705bcef59a6f0a0d3846` |
| `/etc/config/firewall` | `0962f72fa72245bb422bc648843615e5a18feafcfdfd04d93603a4a4d869fa9f` |
| `/etc/config/wireless` | `59f540ed2424a5a9805a09876c22a0d3504ee110897887b596cb35793e90e5fa` |
| `/etc/config/uhttpd` | `bc654f394ab804a78ffe3c143b309f00b8abdf6090162060f555e905868bba18` |
| `/etc/config/rpcd` | `1a40da0ebe45b1afd131dfc4650592913e38445e7fe42f96d3b95ad5151ac0e6` |
| `/etc/config/rtl_tcp` | `500d071555f688b493b2937f8ef1edf7f56dfddd3888aa584e8b572d5db3f2ad` |
| `/etc/config/mjpg-streamer` | `00f24dd633bac043f1063b36ae60bef53659c52237e3cfefc27a611b4806944f` |
| `/etc/config/motion` | `574743e3859793b10328389d2f1a37e4dce88f0e753029a102a43d073b6ca22f` |
| `/etc/config/gpsd` | `e500321d73a7329e11423769f37ea1bb7c11d2dc20f10a3cc126c67b9a7bf078` |

## Pre-existing exposure note

Discovery observed several existing listeners, including nginx, Dropbear, DNS/DHCP, Tailscale, mDNS, and USB/IP on port 3240. They predate this console. The console adds no socket and does not attempt to remediate or reconfigure existing exposure as part of this scoped build.
