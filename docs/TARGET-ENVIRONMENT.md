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

Deployment treats inactive swap as a failed safety preflight. The project never deletes, recreates, formats, resizes, stops, or silently activates the swap file. Persistence is not considered proven until the compact verifier passes after a separately authorized reboot.

## Web and authentication topology

- nginx 1.17.7 is the active public HTTP/HTTPS server on ports 80 and 443.
- Its document root is `/www`, directory index is `gl_home.html`, and directory canonicalization allows a project-owned `/ddk` shortcut without changing nginx configuration.
- `http://192.168.8.1/` and `https://192.168.8.1/` returned the GL.iNet UI with HTTP 200.
- Unauthenticated `http://192.168.8.1/cgi-bin/luci/` returned HTTP 403 with `X-LuCI-Login-Required: yes`.
- The LuCI dispatcher, Lua templates, modern JavaScript views, menu JSON, and rpcd ACL directories are present.
- `uhttpd` is configured for LuCI on 8080/8443, but the only observed active uhttpd listener was the existing Prometheus exporter on `127.0.0.1:9100`. The public UI is therefore treated as nginx-fronted; no web-server configuration is changed.
- The nginx front end returned 404 for LuCI's `/ubus/` JSON-RPC route, with matching failures predating this project in the existing nginx error log. The console therefore uses LuCI's working authenticated `/cgi-bin/cgi-exec` (`fs.exec_direct`) path and does not alter nginx.
- LuCI session authentication uses `sysauth_http` / `sysauth_https`; the rpcd root login has wildcard read/write ACLs. Password material was redacted during discovery.

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

## Pre-existing exposure note

Discovery observed several existing listeners, including nginx, Dropbear, DNS/DHCP, Tailscale, mDNS, and USB/IP on port 3240. They predate this console. The console adds no socket and does not attempt to remediate or reconfigure existing exposure as part of this scoped build.
