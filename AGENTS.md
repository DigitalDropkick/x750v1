# Digital Dropkick Field Console Engineering Rules

## Target

- Device: GL.iNet GL-X750 (Spitz), OpenWrt 22.03.4, `ath79/nand`, `mips_24kc`.
- Hardware budget: one QCA9533-class core and about 121 MB RAM.
- Root filesystem is extroot on `/dev/sda1`; preserve it and its data.
- The GL.iNet UI, LuCI authentication, networking, and Tailscale are operational infrastructure.

## Non-negotiable safety

- Never run `opkg upgrade`, `--force-depends`, or `--force-overwrite`.
- Never replace GL.iNet/OpenWrt core libraries, SSL/libustream, or kernel modules for this app.
- Never change LAN, WAN, cellular, Wi-Fi, firewall, Tailscale, extroot, or swap configuration without explicit approval.
- Never add a listener, expose a service to WAN, enable ttyd on WAN, reboot, or start unrelated daemons.
- Never factory reset, repartition, format, or delete `/overlay/ddk-install.swap`.
- Never modify GL.iNet proprietary UI files for this application.
- Back up every existing target file before replacement and maintain tested rollback tooling.

## Implementation rules

- Follow patterns verified on this device; do not assume current upstream LuCI conventions.
- Prefer native LuCI, Lua 5.1, shell, rpcd, ubus, and small JavaScript.
- No Node/npm runtime, external CDN, database, secondary web server, background polling daemon, or unnecessary package.
- Namespace all UI CSS under `.ddk-console`.
- Use `/tmp/ddk/` only for bounded transient jobs and reports.
- Keep idle CPU at zero and persistent memory overhead effectively zero.

## Action security

- Every browser action maps to a server-side allowlisted action ID.
- Never accept a browser-supplied command, executable path, PID, output path, or shell fragment.
- Validate every argument against a strict allowlist or format before use.
- Never concatenate browser input into a shell command.
- INFO actions may be enabled. ACTION, DISRUPTIVE, and SECURITY actions remain disabled until deliberately reviewed.
- Stop only validated jobs created by this console, after verifying the worker identity.

## Change and completion discipline

- Inspect `git status` before edits; preserve unrelated work.
- Make the smallest complete change and avoid unrelated refactors or upgrades.
- Run syntax, JSON, security, deployment, rollback, and responsive-UI validation where available.
- Review the final diff and report tests, risks, rollback, and remaining uncertainty.
- Do not push, merge, release, or modify production-sensitive configuration without explicit instruction.
