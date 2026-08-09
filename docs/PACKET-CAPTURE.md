# Bounded LAN Metadata Capture

## Product boundary

Version 1.5 enables one packet-observation profile: `capture.lan_metadata_snapshot`. It is an authenticated SECURITY job for short LAN discovery and reachability triage, not a general packet-capture frontend.

The browser sends only the exact action ID. It cannot provide an interface, filter, executable, flag, duration, packet count, snap length, output format, filename, or PID.

## Fixed profile

After independently confirming that the native LAN is up and its L3 device is exactly `br-lan`, the worker invokes:

```text
/usr/sbin/tcpdump -i br-lan -p -n -q -e -l -tttt -s 96 -c 128 \
  'arp or icmp or (ip and udp and (port 67 or port 68))'
```

The worker adds an independent 20-second wall window. Reaching either 128 packets or 20 seconds completes the job normally.

| Control | Fixed behavior |
| --- | --- |
| Interface | Native LAN must resolve to exactly `br-lan` |
| Promiscuous mode | Disabled with `-p` |
| Name resolution | Disabled with `-n` |
| Traffic | ARP, ICMP, and IPv4 DHCP only |
| Snap length | 96 bytes |
| Packet ceiling | 128 |
| Wall window | 20 seconds |
| Output | Decoded text, capped at 64 KiB |
| Concurrency | One capture; two total DDK jobs |
| Storage | Mode-restricted `/tmp/ddk/jobs/<job-id>/` |
| Retention | Four-hour age cleanup and 20-job ceiling |

## Privacy

The decoded result may include timestamps, MAC addresses, IP addresses, ARP relationships, ICMP types, and brief DHCP metadata. This is disclosed in the confirmation prompt. Output is visible only through the authenticated LuCI boundary and is transient across reboot.

The profile does not expose:

- TCP sessions or application traffic;
- DNS queries or reverse lookups;
- packet payload hex/ASCII dumps;
- a downloadable PCAP;
- WAN, cellular, Tailscale, monitor-mode, or all-interface capture;
- packet injection or replay.

Do not treat this profile as consent to capture third-party or customer networks. Future profiles require their own privacy and authorization review.

## Process and resource controls

The existing DDK worker owns the direct `tcpdump` child. An authenticated stop request supplies a generated DDK job ID, never a PID; the backend verifies worker ownership before signaling it. The worker then terminates only its tracked child.

The worker records `br-lan` flags before and after a completed capture and fails the job if they differ. Local validation rejects payload-dump, PCAP-writer, rotation, and all-interface flags from the reviewed worker command. Production verification proves fixed-filter compilation, singleton enforcement, cancellation, unchanged interface flags, output bounds, absence of PCAP artifacts, and absence of a remaining `tcpdump` process.

The feature adds no daemon, listener, timer, service, firewall rule, interface change, or persistent log. Idle CPU and memory overhead remain zero.

## Deliberately deferred

- Operator-selectable interfaces or filters.
- DNS, TCP, or application-aware profiles.
- PCAP generation or download.
- Longer capture windows or persistent ring buffers.
- WAN, cellular, Tailscale, wireless-monitor, or `any` interface capture.
- Packet replay or injection.

Each deferred capability requires a new exact allowlist, privacy decision, resource bounds, and test plan.

## Live acceptance

Version 1.5 was deployed on 2026-08-09 with pre-change backup `/root/ddk-backups/20260809T224048Z-field-console-v1`. The production suite passed 27 checks with no warnings. It proved malformed and extra arguments were rejected, only one capture could run, authenticated cancellation stopped the owned child, a full fixed-window capture completed, interface flags stayed unchanged, output stayed bounded, no PCAP was written, and no `tcpdump` or DDK worker remained.

Authenticated desktop and mobile validation confirmed the capture control in both Jobs & Reports and Tool Registry with SECURITY styling, no external request, no runtime error, and no document overflow. All 39 project files matched the source tree byte for byte after deployment.
