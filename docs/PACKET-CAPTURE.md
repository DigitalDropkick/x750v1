# Operator Packet Capture

## Status and native target

Version 2.1 migrates `capture.lan_metadata_snapshot` from the v2 fixed metadata profile to the reusable Operator Mode transport. The exact production target is `/usr/sbin/tcpdump` 4.9.3 with libpcap 1.10.1. Deployment acceptance exercised bounded loopback capture, PCAP generation, invalid-BPF rejection, cancellation, and cleanup.

The old action ID is retained for compatibility. The v2.1 browser obtains its schema from the backend, prepares a validated plan, reviews the server-built invocation, confirms sensitive modes, and starts the one-time prepared request.

## Controls

The operator can select:

- a live interface reported by the router, including `any` when present;
- one bounded printable BPF capture filter;
- duration and/or packet ceiling;
- snap length;
- decoded text, PCAP, or decoded text plus PCAP;
- promiscuous behavior;
- capture direction supported by the installed binary;
- numeric/name resolution behavior;
- timestamp, link-header, verbosity, payload-display, immediate-mode, and buffer controls.

Interface values come from the backend's live-choice list. The filter is carried as one JSON value and becomes exactly one argv element; it is never parsed as a command or appended to shell syntax. Artifact names and paths are server-owned constants.

## Validation and execution

The backend rejects unknown options, wrong types, unavailable interfaces, control characters, filters over 1024 bytes, unsupported enum values, and values outside the action-specific duration/count/snap/buffer ranges. It maps accepted values to a literal argv array beginning with `/usr/sbin/tcpdump`.

Before capture, the worker:

1. verifies the exact action, Operator Mode metadata, executable, interface, and job-local output path;
2. invokes the exact installed tcpdump in BPF-compile mode against the selected interface;
3. records the selected physical interface flags when meaningful;
4. starts the bounded native child and tracks it for cancellation.

On completion it compares interface flags, enforces output/file ceilings, verifies that a PCAP is a regular non-symlink file with recognized PCAP magic, and optionally performs a separately bounded decode of the completed PCAP. Failed, invalid, or oversized artifacts are removed or rejected.

## Privacy and confirmation

Packet capture may reveal local/customer addresses, device identities, queries, credentials, application data, or third-party traffic. The review shows the exact interface, filter, duration/count, snap length, and output mode. Plans using promiscuous mode, payload display, or PCAP generation require the exact target-bound confirmation phrase returned by the backend.

Ordinary bounded decoded capture without those sensitive modes does not add a second typed confirmation. The operator is still responsible for owned/authorized scope.

## Resource and artifact boundary

- At most one packet-capture action and two total DDK jobs may run.
- The worker applies an independent wall limit and direct-child cancellation.
- PCAP output is capped at 8 MiB.
- Browser-visible stdout/stderr retain the common 128 KiB/32 KiB limits.
- Output remains in the generated mode-0700 `/tmp/ddk/jobs/<job-id>/` directory.
- `capture.pcap` is the only PCAP basename and is mode 0600.
- The backend advertises it only for a completed matching action after type/size checks.
- Native `cgi-download` permits only `/tmp/ddk/jobs/job-[0-9]*-[0-9]*/capture.pcap` through the authenticated DDK ACL.
- Four-hour age cleanup and the 20-job retention ceiling still apply.

There is no arbitrary output path, persistent ring buffer, network export, upload, packet replay, injection, monitor-mode transition, interface configuration, firewall change, or background capture service.

## Legacy compatibility

The original v2 worker remains in source for rollback/regression compatibility. Its fixed command is non-promiscuous `br-lan` ARP/ICMP/IPv4-DHCP metadata, 20 seconds or 128 packets, decoded text only. The v2.1 UI no longer uses that fixed transport as the primary capture workflow.

## Acceptance plan

Local validation checks the structured schema/builder/backend/worker mapping, exact executable, filter handling, artifact placeholder, ACL, GUI review/download path, and absence of command execution inside the builder.

After an explicitly approved deployment, target-safe verification will:

- reject malformed/unknown structured fields;
- compile and run a loopback-only capture;
- generate and validate a bounded PCAP;
- reject an invalid BPF expression before capture;
- exercise cancellation and singleton behavior;
- prove interface flags and protected configuration remain unchanged;
- prove no tcpdump worker or unexpected listener remains;
- exercise authenticated download and outside-path denial.

No v2.1 production acceptance is claimed until those deployed target and authenticated-browser checks actually pass.
