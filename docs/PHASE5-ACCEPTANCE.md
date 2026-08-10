# Phase 5 Release Closure

Phase 5 closes the Field Console 2.1 software release. It does not manufacture capability that the production GL-X750 cannot execute. Instead, it makes the complete action inventory mechanically auditable, exposes the exact blocker beside every unavailable action, reconciles superseded fixed-profile documentation, and repeats the full appliance acceptance boundary.

## Release inventory

The reviewed 2.1 registry contains:

- 24 tool modules;
- 59 exact action IDs;
- 53 enabled actions;
- 38 `operator-v1` structured actions;
- two preserved bounded fixed-profile jobs (`can.capture` and `cellular.snapshot`);
- six technically unavailable actions.

`scripts/audit-operator-release.sh` derives these values from every manifest and fails if module/action IDs duplicate, a schema is executable without a job contract, an enabled action lacks a backend/planner, a fixed-profile job appears without review, an unavailable action lacks a bounded technical reason, or the explicit unavailable inventory drifts.

## Operator-facing blocker contract

An unavailable action must carry `unavailable_reason` on that exact action. The capability API forwards this non-secret metadata. The Tools page renders it as visible text and as the disabled control's title, so desktop, keyboard, and touch operators do not have to infer why a button is unavailable from a module-wide paragraph.

The six reviewed blockers are:

| Action | Concrete blocker |
| --- | --- |
| `can.transmit` | No physical `canN`; installed `canutils` supplies neither `candump` nor `cansend`; bus-impact acceptance is absent. |
| `cellular.raw_command` | Arbitrary AT/QMI text would be a generic device-command endpoint; operation-specific schemas and connectivity recovery are required. |
| `industrial.modbus_write` | Installed mbtools is read-oriented; `mbpoll` is absent and `mbusd` is not a register-write client. |
| `usb.power` | The only controllable hub root carries active extroot and the EC25 path; there is no isolated non-critical switchable port. |
| `usbip.attach` | The target has no usable VHCI controller. |
| `wireless.monitor` | Both radios carry management/client traffic and there is no action-owned atomic netifd/GL.iNet rollback transaction with proven management recovery. |

These actions are not disabled because of their `ACTION`, `SECURITY`, or `DISRUPTIVE` classification. When their concrete runtime, topology, and recovery prerequisites exist, they should be implemented through the same structured architecture.

## Acceptance gate

Release closure requires all of the following:

1. local shell, JavaScript, JSON, policy, size, and release-inventory validation;
2. complete staged-diff review and a clean Phase 5 checkpoint;
3. target-safe production verification with no protected configuration change;
4. authenticated browser verification at 320 px, 390 px, and desktop, including all six visible blocker disclosures;
5. source/deployed byte parity;
6. no residual DDK worker, native tool, temporary helper/listener, sealed proof input, or private job input;
7. an exact preinstall rollback snapshot if production files change.

Live device-changing acceptance remains separate and must use approved attached customer/bench hardware. The absence of that hardware does not invalidate the software release's fail-closed no-device acceptance.

## Production acceptance

Phase 5 was deployed on 2026-08-10 with preinstall rollback snapshot `/root/ddk-backups/20260810T210034Z-field-console-v1`. The complete target suite passed 50 checks with 0 warnings, including the deployed 59-action inventory, all prior native/negative/lifecycle proofs, protected configuration, and idle-state checks.

Authenticated browser acceptance passed at 1440 px, 390 px, and 320 px. All six unavailable actions displayed their exact blocker as visible card text and disabled-control title; local-only requests, authenticated artifact/upload boundaries, layouts, and runtime-error checks passed. Visual inspection confirmed the new panels remain readable in the existing console design.

All 47 deployed project files matched source byte for byte. No DDK worker, private input, proof upload, native helper, or temporary listener remained. The deployment reloaded rpcd ACL recognition only; it did not reboot, install a package, restart a service, or change network, firewall, wireless, camera, GPS, Tailscale, extroot, or swap configuration.
