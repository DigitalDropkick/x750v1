# Phase 4 Operator Mode

Phase 4 completes structured coverage for monitoring, Wi-Fi survey, USB inventory, file forensics, packet replay, ADS-B, AIS, Bluetooth discovery, MQTT publishing, USB relay control, Modbus reads, smartcard/YubiKey workflows, temporary camera streaming, and NTRIP corrections. The implementation targets the exact packages and help output inspected on the production GL-X750; it installs no substitutes.

## Shared execution boundary

All 15 actions use the existing `operator-v1` envelope. `operator-phase4.lua` rejects unknown fields, normalizes typed values, selects a fixed executable, and builds a literal argv plan. Secrets become named one-time private inputs, never job metadata or browser-built command text. `ddk-console` binds plans to five-minute single-use prepared IDs, exact workers/executables, resource locks, sealed inputs, fixed artifacts, wall limits, and target-bound confirmation. `ddk-phase4-worker` independently revalidates the action, executable, argv shape, live target, sealed-input hash, private-input name, artifact ceiling, and cleanup ownership before native execution.

There is no generic shell, executable selector, arbitrary flag list, router path, raw modem command, or generic service endpoint.

## Implemented families

- `monitoring.snapshot`: vnStat 2.9 history or bounded iftop 1.0pre4 live-flow text for a current interface.
- `wireless.survey`: iwinfo/iw information, scan, or station inventory for a server-listed wireless interface. It does not change channel, mode, power, association, or netifd state.
- `usb.inventory`: usbutils 014 summary, tree, or per-VID:PID verbose inventory.
- `forensics.inspect_file`: fixed file 5.41, hashdeep 4.4, ssdeep 2.14.1, checksec 2.5.0, or YARA 4.1.3 analysis of sealed DDK inputs only. YARA rules are a separate sealed input.
- `capture.replay`: tcpreplay 4.4.1 with selected live output interface, loop, packet, duration, and native speed controls. The sealed capture must parse as PCAP/PCAPNG before transmission. Exact interface/input confirmation is mandatory.
- `adsb.receive`: readsb 3.9.0 with reviewed RTL-SDR serial, frequency, gain, PPM, output, Mode A/C, metric, duration, cancellation, and text artifact controls. Networking is not enabled.
- `radio.ais`: rtl_ais 0.3 dual-frequency receive with reviewed tuner and exact frequency/rate/gain/PPM controls. The worker captures console NMEA evidence; it starts no persistent radio service.
- `bluetooth.scan`: bounded classic or LE discovery through one already-up reviewed HCI controller. It does not start bluetoothd, bring HCI up, pair, connect, or accept raw HCI commands.
- `automation.mqtt_publish`: one-shot mosquitto_pub 2.0.15 with host, port, TLS system certificates, topic, QoS, retain, protocol, credentials, repeat, delay, and wall controls. Payload/password are one-time private files; retained publishes require exact broker/topic confirmation.
- `automation.relay`: crelay 0.14 status/on/off for a freshly enumerated serial-identified compatible controller and bounded channel. Physical changes require exact controller/channel/state confirmation.
- `industrial.modbus_read`: mbcollect from installed mbtools with TCP or reviewed non-EC25 RTU transport, unit, holding-register list, datatype, interval, and duration. Its config is generated inside the job and removed afterward.
- `auth.inventory`: on-demand PC/SC reader inventory or indexed YubiKey information. DDK starts `pcscd --foreground --auto-exit` only when it owns the workflow and stops it afterward.
- `auth.program`: ykpersonalize 1.20.0 dry-run or confirmed slot configuration/delete/swap. Secret key material is one-time and redacted; commit confirmation names the token index, operation, and slot.
- `camera.stream`: a temporary mjpg-streamer 2.0 listener for a reviewed primary UVC node, exact current IPv4 address, non-privileged port, resolution, FPS, quality, username, password, and duration. It requires exact target confirmation and does not enable the packaged boot service, Motion, RTSP, or a firewall rule.
- `gps.ntrip`: ntripclient 1.51 for an exact reviewed non-EC25 GNSS serial target, caster, mountpoint, account, transport, serial format, and duration. The password is one-time; confirmation names the selected receiver and mountpoint. gpsd remains disabled.

## Artifact and secret handling

Forensics and packet replay consume only sealed upload IDs from DDK-controlled extroot storage. Workers verify the regular-file mode, declared kind, size, and SHA-256 immediately before use. Text artifacts have fixed names below the mode-0700 job directory and exact authenticated rpcd read patterns. No action accepts a router filesystem path.

MQTT payload/password, YubiKey secret, camera password, and NTRIP password are hex-encoded only inside mode-0600 job-private files, decoded immediately by the worker, absent from metadata/review output, and removed on success, failure, or cancellation.

## Genuine target limitations

- CAN configuration/transmit remains unavailable because no `canN` hardware exists and the installed `canutils` record supplies no `candump`/`cansend` payload.
- Modbus writes remain unavailable because the installed mbtools payload contains read-oriented `mbcollect`/`mbrecorder`; `mbpoll` is absent and `mbusd` is a gateway, not a reliable write client.
- USB hub power control is withheld because the only controllable physical root path also carries the EC25 modem and active extroot. A per-port topology that cannot power-cycle appliance-critical devices is required.
- USB/IP attach is unavailable because the target reports no usable VHCI controller.
- Wi-Fi monitor-mode/interface changes are withheld because both radios participate in active management/client service and no action-owned atomic netifd/GL.iNet rollback transaction exists.
- Cellular raw commands remain outside the GUI because arbitrary raw-command text is equivalent to a generic device shell. A future migration needs operation-specific QMI schemas plus connectivity recovery/rollback, not a raw string box.
- Live hardware execution remains pending for currently unattached RTL-SDR, UVC camera, GNSS, Bluetooth, smartcard/YubiKey, relay, CAN, and general serial devices. The production no-device paths fail before opening a native target and clean all owned state.

These are runtime or architecture constraints. `ACTION`, `SECURITY`, and `DISRUPTIVE` classification is not itself a blocker.
