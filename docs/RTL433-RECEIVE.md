# Hardware-Gated RTL-433 Sensor Snapshot

## Product boundary

Version 1.6 adds `radio.rtl433_snapshot`, a bounded ACTION workflow for receiving common 433.92 MHz ISM sensor transmissions through one reviewed RTL-SDR dongle. It is not a general SDR frontend, spectrum recorder, raw-sample collector, transmitter, or network radio server.

The browser sends only the exact action ID. It cannot provide a device, USB serial, frequency, sample rate, gain, duration, decoder, configuration path, input/output path, output protocol, network destination, or process ID.

## Hardware gate

The console reports the workflow as `HARDWARE REQUIRED` unless all of these conditions hold:

- exactly one USB device has reviewed ID `0bda:2832` or `0bda:2838`;
- its sysfs USB serial is present, at most 64 characters, and contains only letters, digits, dot, underscore, or hyphen;
- no USB interface belonging to that device has a kernel driver attached;
- no other DDK job owns the `rtl_sdr` resource.

The backend checks this before creating a job. The worker independently repeats the USB, serial, and driver checks immediately before opening the tuner. It selects the tuner with the server-derived serial form `-d :<serial>`; browser input is never used.

The worker refuses multiple reviewed dongles rather than guessing an index. It also refuses to detach a DVB driver, stop an existing receiver, or replace an existing RTL-SDR client.

## Fixed receive profile

The reviewed invocation is equivalent to:

```text
/usr/bin/rtl_433 -c /dev/null -d :<server-derived-serial> \
  -f 433920000 -s 250000 -S none -F json \
  -M time:iso -M protocol -T 20
```

| Control | Fixed behavior |
| --- | --- |
| Frequency | 433.92 MHz |
| Sample rate | 250 kS/s |
| Tuner gain | `rtl_433` automatic default |
| Decoders | Installed standard decoder set |
| Internal duration | 20 seconds |
| Independent wall limit | 25 seconds |
| Output | JSON event lines rendered as transient text |
| Raw I/Q | Disabled explicitly with `-S none` |
| Configuration | Explicit empty file `/dev/null`; default/user files are not loaded |
| Concurrency | One workflow and one shared `rtl_sdr` resource |
| Storage | Mode-restricted `/tmp/ddk/jobs/<job-id>/` |
| Retention | Four-hour age cleanup and 20-job ceiling |

Each child output file is restricted with a POSIX file-size limit of 112 blocks, or 56 KiB. The worker then constructs a final result capped at 64 KiB and removes its intermediate files. A file-limit stop is reported as the bounded output ceiling rather than retried.

## Privacy and authorization

Decoded event output may contain sensor model names, rolling or device identifiers, channel numbers, temperatures, humidity, battery state, counters, timestamps, and other measurements transmitted nearby. The confirmation prompt discloses this before the job begins.

Use the receiver only for equipment and radio traffic you own or are authorized to inspect. Output remains transient, authenticated through LuCI, and is not forwarded to MQTT, InfluxDB, syslog, `rtl_tcp`, or any other network destination.

## Explicit exclusions

- No browser-selectable frequency, hopping, sample rate, gain, duration, or decoder.
- No custom decoder (`-X`), analyzer mode, test-file input, or arbitrary config file.
- No raw I/Q save, signal autosave, file output, or persistent log.
- No `rtl_tcp` start, listener, connection, service mutation, or firewall rule.
- No AIS, ADS-B, FM, spectrum/power scan, replay, injection, or transmit workflow.
- No kernel-driver unbind, module load/unload, USB reset, or device EEPROM change.

## Current acceptance limit

No reviewed RTL-SDR was attached during version 1.6 development. Production verification can therefore prove the exact installed software, hardware-aware `HARDWARE REQUIRED` state, malformed/extra-argument rejection, pre-job refusal, absence of receiver processes/listeners, and unchanged `rtl_tcp` configuration. A successful live receive, owned-child cancellation, and measured CPU/RAM profile require one approved dongle to be attached and are not claimed until that test is performed.

The no-device release was deployed on 2026-08-09 with pre-change backup `/root/ddk-backups/20260809T231004Z-field-console-v1`. The production suite passed 29 checks with no warnings. Both the backend and independent worker gate refused the missing tuner without leaving a job or starting a radio process; `rtl_tcp` remained disabled and byte-identical, and port 1234 remained closed.

Authenticated browser checks passed at 320 px, 390 px, and desktop widths with the module marked `HARDWARE REQUIRED` and both ACTION controls disabled. No external request, runtime error, or document overflow occurred, and all 39 deployed files matched source byte for byte.
