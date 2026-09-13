#!/bin/sh
# Read-only native capability discovery. No configuration or device operations.
set -u
printf '%s\n' 'DDK_V3_READ_ONLY_DISCOVERY'
ubus call system board
printf 'Field Console version: '; cat /usr/share/ddk-field-console/VERSION
printf '\nMemory and storage\n'; free; df -Pk /overlay /tmp; cat /proc/swaps
printf '\nInstalled package inventory\n'; opkg list-installed
printf '\nNative help (no hardware opened)\n'
for tool in arp-scan fping dig mosquitto_sub mosquitto_pub iw iwinfo hciconfig hcitool bluetoothctl gatttool sdptool \
 qmicli uqmi qcsuper rtl_433 rtl_test rtl_tcp rtl_ais readsb rigctl gpsd gpspipe gpsctl rtkrcv ntripclient \
 fswebcam v4l2-ctl mjpg_streamer motion v4l2rtspserver candump cansend canplayer ip mbpoll mbcollect \
 ftdi_eeprom flashrom openocd avrdude adb fastboot idevicebackup2 ideviceinstaller idevicecrashreport \
 ddrescue dd_rescue dd smartctl xxd strace gdbserver bmon htop oathtool stoken pcsc_scan usbip uhubctl socat picocom; do
 path="$(command -v "$tool" 2>/dev/null || true)"
 printf '\n=== %s %s ===\n' "$tool" "${path:-MISSING}"
 [ -n "$path" ] || continue
 case "$tool" in
  uqmi|rtl_433|rtl_test|rtl_tcp|rtl_ais|rigctl|fswebcam|mjpg_streamer|candump|cansend|canplayer|ftdi_eeprom|dd_rescue) option=-h ;;
  dig) option=-h ;;
  qmicli) option=--help-all ;;
  avrdude) option='-?' ;;
  *) option=--help ;;
 esac
 timeout 5 "$path" "$option" </dev/null 2>&1 | head -c 24576
done
