# Field Console v4 usability and release record

Baseline: clean `main` at `b205e77da1abbcd8825a8fbf555ca870a83af937`, deployed v3.0.0.
Work branch: `feature/field-console-v4`. The user requested a full dark-theme GUI
redesign and end-to-end workflow improvements before their hardware acceptance.

## Observed in the real browser

An authenticated Chrome session was operated through DevTools because this
session has no computer-use skill or dedicated desktop-control tool. The browser
used the live router and existing LuCI authentication; credentials were handled
privately and screenshots stayed in the local audit directory.

- The home page prioritizes dense system internals over starting or resuming work.
- The Tools page presents large module cards and backend-policy text. Individual
  action names and practical task phrases are not consistently searchable.
- Tool dialogs are attached outside `.ddk-console`, so scoped styles do not reach
  their inputs/buttons. Native browser defaults appear inside the dark interface.
- Opening a dialog leaves focus on the button behind it. Escape does not dismiss
  it. There is no keyboard focus trap or background scroll lock.
- Validation errors open nested dialogs; review has no back/edit step. Starting a
  tool requires another navigation decision to reach its output.
- Jobs display large raw output blocks and many equally weighted buttons, without
  an outcome summary, focused job view or result-specific next steps.
- Files live under Settings, far from the tool that needs them. Upload/reuse ends
  with an acknowledgment instead of a direct continuation into a compatible tool.
- Stopped jobs are styled as failures. Retention/help text still contains old
  implementation terminology and an obsolete 64-input claim.

## Design and implementation plan

- Graphite surfaces, readable system typography, lime accents, consistent icons,
  sidebar navigation on desktop and usable mobile navigation. Preserve the logo,
  dark theme, local assets and the small router runtime.
- A task-focused home page and action-level tool library with search by purpose,
  native tool, family and name; categories, browser-local favorites/recent tools,
  and keyboard tool search. Every enabled action remains reachable.
- One accessible configure/review dialog with common presets, contextual help,
  inline validation, back/edit, visible target and direct navigation into results.
  Hardware and private parameters remain freshly validated by the backend.
- A jobs/cases workspace with stable selection, readable times and targets, output
  controls, file downloads, case saving/export and explicit next-tool handoffs.
- Summaries derived only from observed native output. Show parsing limits and
  incomplete results; retain raw output and label suggestions separately.
- Upload and select inputs inside the tool form, with progress and direct reuse.
- Regressions for search coverage, parsing, parameter handoffs, accessibility,
  mobile overflow, focus/scroll stability, real loopback workflows and cleanup.

## Implemented

The five existing routes now share a responsive graphite/lime workspace with
local SVG icons and the Digital Dropkick mark. The tool library exposes all 92
actions, with six task families, search, favorites, recent tools and Ctrl/Cmd K.
The overview includes useful starting workflows, recent cases and real appliance
status. Mobile navigation remains labelled and the decorative hero is condensed.

All 78 structured workflows use the live server schema. One dialog handles
configuration, review, inline errors and editing. Focus is contained and restored;
Escape dismisses a dialog. Native consequences still require the server's exact
confirmation phrase. Device/file refresh preserves existing valid selections.
Presets exclude private fields and file selections. Uploads finish verification
and select their result before returning to the parent form.

Jobs open directly into a selected workspace. Summary, Output and Files provide
conservative interpretation, native text filtering/copy/download, file download,
image preview, case save/name/export, rerun and manual next-tool handoffs. Output
controls survive status transitions and polling. Stopped jobs retain partial data
and use an amber status. Network target lists appear alongside the chosen
interface in reviews, results and searches.

The only runtime backend change gives rotated PCAP inputs a supported filename
while reading the original registered artifact. `capture.pcap0` becomes a verified
input named `capture.pcap0.pcap`; the source file and bytes remain unchanged.

## Validation

- `./scripts/validate-local.sh`: passed, including existing native planner,
  lifecycle, USB topology, protocol, hashing and rollback tests; seven new tool
  guide tests cover complete action/search coverage, Nmap/fping/DNS/iperf/Android
  summaries, partial/private outputs and typed file handoffs.
- Authenticated Chrome: five routes at 1440, 390 and 320 pixels (15 viewport
  checks), all 78 structured forms, focus restoration/Escape, action search,
  favorites, keyboard search, network ADB and inline APK access. No page overflow.
- Real loopback Nmap and fping: configuration errors preserve the form, Back
  preserves the target, observed hosts carry into the next tool, output controls
  remain usable during polling, stop retains results, and case save/export works.
  Actual text and artifact downloads were checked for their native loopback data.
- Reusing a result opens a compatible tool with that input selected. A public
  four-byte upload fixture exercises upload, verification and form selection.
- `scripts/test-v4-input-native.py`: passed against the actual Lua/nixio runtime
  in `/tmp/ddk-v4-validation`. A native loopback capture was reused by all three
  capture consumers with matching SHA-256 and unchanged source bytes.

`DDK_BROWSER_PREVIEW=1 ./scripts/verify-browser-authenticated.sh` substitutes local
presentation assets in Chrome while retaining the router's native HTML response
and live backend. This avoids changing Chrome's local-network security context.
`DDK_BROWSER_QUICK=1` reruns the workflow checks without repeating the full page
and form matrix. Fixture jobs and inputs are tracked and cleaned individually.

Physical Android/Apple devices, programmers, serial/CAN/Modbus adapters, tuners,
cameras and recovery disks still require Addam's attached-device acceptance.
Synthetic Android output tests do not establish OEM or hardware compatibility.
The installed ADB build still requires an already enabled TCP debugging endpoint;
modern wireless pairing, missing fastboot and missing ideviceinstaller are native
software limitations inherited from v3. No firmware/library upgrades are included.

## Release and rollback

Final release: **v4.0.1**, code commit
`83bd73cf9d4cb2c775f1481dff17323ed0fabf29`, published to GitHub and installed
on 2026-09-14 UTC (September 13 local time). The original `v4.0.0` tag remains
available in the release history.

Deployment used `./deploy.sh`. `./verify.sh` passed the installed native runtime
checks. The complete authenticated browser verifier passed against live v4.0.1
assets, including all 78 forms, every workflow assertion and the added search
icon/text geometry check at 1440, 390 and 320 pixels. Local validation passed.

The final visual patch fixes a CSS specificity conflict that had overridden
padding beside the tool-search icon. It changes no native tool behavior.

- All 58 installed application files match the committed source by SHA-256.
- All nine protected configuration files and all 39 listeners match the fresh
  deployment baseline. The existing retention-data file is unchanged.
- GL.iNet, LuCI, Tailscale, extroot and swap passed the final health check.
- The final live browser run passed all 15 page viewports, all 78 forms and typed
  handoffs, and the actual network/file/case workflows described above.
- Zero test jobs and zero uploaded test inputs remain. The isolated native
  validation tree was removed. Transient browser sessions were destroyed.

The application rollback snapshot is:
`/root/ddk-backups/20260914T000631Z-field-console-v4`.
It contains the prior v3 files. The additional snapshot
`/root/ddk-backups/20260914T002403Z-field-console-v4` contains the v4.0.0 files
before the final visual patch. To restore v3 with the connection helper open:

```sh
DDK_TARGET=root@100.122.115.85 \
DDK_SSH_CONTROL_PATH=/run/user/1000/ddk-router-1000/control \
./rollback.sh /root/ddk-backups/20260914T000631Z-field-console-v4
```

Rollback restores the application and reloads its ACLs. It retains saved cases
and reusable inputs. The rollback fixtures passed for v1, v3 and v4 folder names.

## Changed files

| Area | Files and purpose |
| --- | --- |
| Interface | `console-app.js`, `console.css`, `shell.htm`: navigation, responsive design, dialogs, job workspace and files |
| Guidance | `console-guide.js`: all action descriptions, presets, output summaries and compatible handoffs |
| Runtime | `ddk-console`: canonical input names for rotated PCAP reuse; `VERSION`: 4.0.1 |
| Release tooling | `router-install.sh`, `router-verify.sh`, `router-rollback.sh`, `rollback.sh`: v4 deployment, verification and rollback |
| Validation | `validate-local.sh`, `audit-operator-release.sh`, `verify-browser.mjs`, `test-rollback.py`, `test-console-guide.cjs`, `test-v4-input-native.py`: updated contracts and regressions |
| Documentation | `README.md`, this release record and the screenshots below |

## Verified screenshots

[Desktop overview](screenshots/v4-overview-desktop.png) ·
[Mobile overview](screenshots/v4-overview-mobile.png) ·
[Tool library](screenshots/v4-tool-library.png) ·
[Live case and observed results](screenshots/v4-live-case.png)

The case screenshot contains public loopback test data. Those test jobs and
inputs were deleted after verification; customer data were not used.
