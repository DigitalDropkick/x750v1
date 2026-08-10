# Digital Dropkick Field Console Engineering Rules

## Target

- Device: GL.iNet GL-X750 (Spitz), OpenWrt 22.03.4, `ath79/nand`, `mips_24kc`.
- Hardware budget: one QCA9533-class core and about 121 MB RAM.
- Root filesystem is extroot on `/dev/sda1`; preserve it and its data.
- The GL.iNet UI, LuCI authentication, networking, and Tailscale are operational infrastructure.


Operator functionality policy:

The Field Console is an authenticated professional field-service appliance.
Installed command-line tools should expose their materially useful native
functionality through the GUI whenever practical.

Do not intentionally reduce a tool to a diagnostic subset solely because
its full operation can modify devices, generate traffic, capture data, or
perform security testing.

Instead:

- expose operations through structured controls;
- validate all arguments server-side;
- construct argv server-side;
- never accept arbitrary shell syntax;
- classify impactful operations clearly;
- require confirmation for destructive/disruptive actions;
- hardware-gate operations requiring attached hardware;
- preserve job cancellation and resource locking;
- never modify the router's own networking/firewall/Tailscale configuration
  unless that specific operation is explicitly intended by the operator.

The GUI should provide the functionality of the installed tool, not an
artificially limited substitute for it.
