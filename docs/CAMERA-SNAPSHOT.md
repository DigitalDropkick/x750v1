# Camera Still Snapshot

Version 1.7 adds one hardware-gated `camera.still_snapshot` ACTION. It uses the already-installed `fswebcam` and V4L2 tools. It does not install a package, start a service, or create a listener.

## Hardware gate

The status backend and worker independently require:

- exactly one physical USB camera whose video nodes resolve through sysfs;
- the `uvcvideo` driver and USB video interface class `0e`;
- a valid four-hex-digit USB VID and PID;
- exactly one sysfs video node with index `0`;
- a character device at the corresponding server-derived `/dev/videoN` path.

The worker then runs a five-second `v4l2-ctl --info` query and requires both `uvcvideo` and `Video Capture`. It scans `/proc/*/fd` and refuses a node already open by another process. The browser cannot provide a device path, VID:PID, node, resolution, filename, or flag.

Multiple cameras or multiple primary nodes are deliberately ambiguous. They remain `HARDWARE REQUIRED` until a future reviewed selection model exists.

## Fixed capture profile

The only capture command is a server-defined profile:

```text
fswebcam --quiet --device <server-derived-node> --resolution 640x480
         --fps 10 --skip 5 --frames 1 --no-banner --jpeg 85 <job>/snapshot.jpg.next
```

The worker provides no config file, loop/background mode, command hook, network target, stream output, audio, or user-controlled argument. It applies:

- one active camera job and one shared camera resource;
- a 20-second independent wall-clock limit;
- a 256 KiB process file-size limit;
- JPEG magic, `file(1)` type, and 1 KiB-to-256 KiB final-size validation;
- atomic rename to `snapshot.jpg` only after validation;
- mode `0600` on the artifact and mode `0700` on the job directory.

Failed, rejected, and stopped jobs retain no JPEG. Completed artifacts follow the existing four-hour/20-job transient cleanup boundary.

## Authenticated view and download

The JPEG never lives below `/www`. The backend advertises an artifact only for a completed camera job whose fixed file is a regular, bounded JPEG. The client accepts only generated `job-<digits>-<digits>` IDs and derives this exact path:

```text
/tmp/ddk/jobs/<job-id>/snapshot.jpg
```

Download uses OpenWrt's existing authenticated `cgi-download` endpoint. The DDK ACL grants read access only to the strict camera-artifact glob. No new CGI, port, listener, or authentication mechanism is created. Verification proves an allowed transient artifact can be read and `/etc/shadow` cannot.

## Privacy and service posture

A still frame can contain people, customer property, documents, screens, or location details. The UI requires explicit confirmation and tells the operator to establish authorization and consent first. Camera frames are excluded from DDK System Reports.

`mjpg-streamer`, Motion, and RTSP remain outside this action. Deployment and verification require the existing `mjpg-streamer` and Motion UCI flags and init states to remain disabled, require no camera client to be running, and protect both configuration hashes. DDK never starts, stops, enables, or reconfigures those services.

## Current acceptance limit

No `/dev/video*` device was attached during version 1.7 development. Production verification proved installed tools, the conservative `HARDWARE REQUIRED` state, malformed/extra-argument rejection, backend pre-job refusal, independent worker refusal, absence of image artifacts/processes/listeners, unchanged camera configurations, and authenticated artifact ACL isolation. The authenticated proof allowed the exact transient job JPEG and denied `/etc/shadow`. A real still, cancellation during capture, image-quality judgment, and measured capture CPU/RAM remain pending one approved UVC camera and explicit operator consent.
