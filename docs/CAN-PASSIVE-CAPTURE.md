# Passive CAN Frame Snapshot

Version 1.9 adds the fail-closed `can.capture` ACTION workflow. It is receive-only and operates only when the router already has one up physical SocketCAN interface named `canN` and `/usr/bin/candump` is present.

On the current GL-X750, the package database records `canutils` 2021.08.0-2, but that package has no listed payload, `candump` is absent, and no CAN interface exists. The console reports both conditions and disables the action. It does not install, repair, replace, or force a package.

## Hardware and runtime gate

The backend and worker independently require:

1. exactly one `/sys/class/net/canN` interface;
2. ARPHRD_CAN type `280`;
3. an attributed physical sysfs device path below `/sys/devices/`;
4. the interface `IFF_UP` flag already set; and
5. executable `/usr/bin/candump`.

`vcanN`, `slcanN`, renamed interfaces, multiple physical CAN interfaces, down interfaces, and missing `candump` all fail closed. The console never runs `ip link set`, chooses a bitrate, raises an interface, attaches a serial line discipline, or restarts networking.

## Fixed receive profile

The browser submits only `action_id=can.capture`. The server derives the interface and invokes exactly:

```text
/usr/bin/timeout 25 /usr/bin/candump -L -n 128 -T 20000 <server-derived-canN>
```

The profile is bounded to 128 frames, a 20-second candump timeout, a 25-second independent wall limit, a 56 KiB child file, a 64 KiB final output, one active CAN action, and one shared CAN resource. Interface flags are compared before and after capture; a change fails the job.

The `-L` option selects stdout log formatting. The workflow never uses candump's persistent log-file option.

## Authorization and privacy

CAN frames can disclose vehicle, industrial-machine, medical-equipment, sensor, access-control, or automation state. The UI requires explicit confirmation that the bus is owned or authorized. Output is transient under `/tmp/ddk/jobs/` and is eligible for cleanup after four hours.

## Deliberately excluded

- `cansend`, `cangen`, replay, ISO-TP transmit, or any other transmission;
- bitrate, sample-point, restart-ms, listen-only, loopback, termination, or link-state configuration;
- browser-selected interface, filter, frame count, duration, command, flags, or output path;
- persistent candump logs or packet databases; and
- automatic package installation or replacement.

Live receive, cancellation, output-format, and bus-impact acceptance remain pending an approved CAN adapter, an already-configured `canN` interface, and a reviewed `candump` executable. Until then, both the backend and worker refusal paths are production-testable.
