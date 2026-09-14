# Orbit 4.2: field network tools

Five workflows extend the existing Network tool library. The registry now has
24 modules, 97 enabled actions and 83 structured forms. No background dashboard
service is added. The current Orbit iPhone app displays the router's forms and
results; this release does not require a new IPA or signing profile.

Reconnect in Orbit, open **Tools → Network**, and search the workflow names below.
Use each card's star to keep it in Favorites. Results offer follow-up forms with
observed targets carried forward; review the selected target before starting.

| Workflow | Field use | Results and next step |
| --- | --- | --- |
| Switch & port | Identify the advertising switch and connected port with existing lldpd | Local port, switch name, remote port and management address; open an SNMP check or scan that address |
| Equipment check | SNMP system identity/uptime, interface counters, Printer-MIB, UPS-MIB or custom numeric GET/walk | Friendly system/interface labels alongside exact OIDs and values; inspect errors, change the profile or test reachability |
| Compare scans | Select two saved, completed Nmap jobs containing XML | Native Ndiff changes, earlier/later values and complete downloadable output; match scan scope/settings before interpreting a disappearance |
| Path & MTU | IPv4/IPv6 UDP path probes with chosen packet size, port and hop count | Hop replies, reported PMTU and whether the destination replied; continue to latency, throughput or capture |
| Windows & NAS shares | List shares, browse a selected folder or test an upload/download | Authentication/access errors, directory contents, byte count, SHA-256 result and explicit test-file cleanup status |

## Operation details

- Save two Nmap cases using the default XML artifact format (or All). Comparison
  dropdowns show eligible saved scans; the defaults select oldest and newest.
  Both source cases remain locked against deletion during comparison. XML is
  checked for completion and unsafe entity declarations before Ndiff reads it.
- LLDP reports only received advertisements. An empty list is an observation,
  not evidence that a cable or switch failed. Switch advertising configuration
  and the connected Ethernet port determine what can be discovered.
- Orbit 4.2.1 uses isolated Net-SNMP 5.9.5.2 clients with AES-128, AES-192/256
  (Blumenthal and Cisco/Reeder variants), DES and the existing v1/v2c/v3 modes.
  See [SNMP encryption](SNMP-AES.md) for setup, build and verification details.
  Printer/UPS profiles need the corresponding MIB implemented and
  exposed by the device. Counters are snapshots, not calculated traffic rates.
- SNMP credentials and SMB passwords use private files in the RAM-backed job
  directory. They are excluded from prepared metadata, native argv and saved
  cases. Files are removed on completion/stop; RAM credentials do not survive a
  power loss. Native output is redacted before it becomes downloadable.
- SMB2 means minimum SMB2_02, allowing SMB2 and SMB3 servers. SMB3 means minimum
  SMB3_00; NT1 additionally permits legacy SMB1. Browser folder/share values are
  literal arguments. Only generated filenames enter smbclient's command parser.
- Transfer tests require the displayed target confirmation. They create a
  random `orbit-test-<32 hex digits>.bin`, upload/download it, verify SHA-256 and
  attempt deletion in a separate worker cleanup phase even after Stop. If a
  server disconnects or power is lost, use the exact filename in Output to check
  for a remaining file. Cleanup failure is never reported as success. Timing
  includes connection/authentication overhead and is not a line-rate benchmark.
- SMB passwords use a separate private `PASSWD_FILE`, preserving significant
  leading/trailing spaces and punctuation. Account/domain identity files still
  reject surrounding whitespace instead of silently changing an account name.
- SMB defaults to a 30-second request timeout. Cleanup honors that timeout and
  can continue for up to three request windows plus ten seconds after Stop.

## Packages and installation

`scripts/msp-packages.lock.json` pins eight architecture-matched archives and
SHA-256 checksums from this appliance's GL.iNet feed. LLDP and SNMP were already
installed. New packages are ndiff, python3-xml, iputils-tracepath, samba4-client,
samba4-libs, libgnutls, liburing and attr: about 7.9 MiB downloaded and 24 MiB
unpacked. Payload review found no installed-path collisions or init scripts.

Build and validate locally with `./scripts/validate-local.sh`, publish the
reviewed branch, then stage the eight exact IPKs plus the lock and installer on
the router. Run:

```sh
python3 install-msp-tools.py /path/to/staged-ipks msp-packages.lock.json
```

The installer checks this exact device/release, archive hashes, dependencies,
free space and existing package versions. It uses an isolated configuration,
empty feed/config directories and the local archive closure, first in no-action
mode. The firmware loads feed snippets even with an alternate config file, so
`OPKG_CONF_DIR` is isolated explicitly. It records added packages under
`/root/ddk-backups/msp-packages-<timestamp>` and verifies every
previously installed version is preserved. It performs no feed refresh, kernel
change or bulk upgrade. Then use the normal `deploy.sh` with the router's SSH
control connection. Deployment backs up application files and reloads rpcd ACLs.

## Validation and rollback

Local validation includes all existing suites plus numeric target/OID validation,
SNMPv3 compatibility, secret isolation, saved-scan selection, XML entity and
incomplete-scan rejection, SMB command separation and cleanup failure reporting.
An isolated SMB2 server also exercised the actual laptop smbclient: share listing,
a folder containing spaces/semicolon, 1 MiB upload/download, SHA-256 and deletion.
Router and browser acceptance results are recorded below.

Use the exact application backup printed by `deploy.sh` with `./rollback.sh`.
That restores the previous dashboard and removes the new helper; saved cases
remain. The new userspace packages can remain installed for command-line use.
To remove them, review `added.txt` in the package backup and use ordinary
`opkg remove` for those packages only, dependent packages first. Never force
removal if another tool now depends on them. No network or firmware rollback is
needed for this release.

## Installed acceptance: September 14, 2026

- Local validation passed after the final application change. Authenticated
  browser checks exercised all 83 forms, all five pages at 1440/440/390/320 px,
  SNMP/SMB field transitions, Orbit connection/offline behavior, native Nmap and
  fping, target handoff, Stop, case save/export, downloads, file reuse and upload.
  All five new forms were also checked at phone widths, with screenshots.
- The focused installed-browser SMB run passed after correcting the test's
  share-name casing assumption: native share rows displayed, the observed data
  share/server/port carried into Browse, and native directory contents displayed
  at 440 px. The suggestion avoids the special IPC$ service share. Its transient
  LuCI session and owned browser jobs were removed.
- `scripts/test-msp-router.py --smb-port 2445` passed on the installed router:
  all five native schemas, LLDP JSON, IPv4/IPv6 loopback tracepath, SNMP GET/walk
  and bad-community timeout, two real saved Nmap scans with an open/closed-port
  comparison, and guest SMB listing/browsing/2 MiB transfer. The transfer exceeded
  its 1 MiB log budget and still verified its full payload. Owned fixture jobs
  and saved cases were deleted; all nine protected configuration hashes matched.
- Native router SMB 4.14.12 authenticated share listing, directory browsing and
  a 1 MiB upload/download passed against an isolated SMB2 fixture. The synthetic
  password included significant surrounding spaces, quotes, a percent sign and
  a backslash. SHA-256 and remote test-file deletion passed. Deliberately wrong
  credentials produced a login failure. Results excluded the password and the
  private RAM credential directories were removed after every operation.
- Stopping both 4 MiB and 32 MiB transfers after partial uploads retained stopped
  results and confirmed deletion of the exact generated remote files.
- An earlier 32 MiB test coincided with an unexpected router restart while power
  remained connected. It was not counted as a pass; its synthetic local and
  remote leftovers were removed explicitly. The boot log reports a previous
  watchdog reset, but no persisted crash record established the cause. The
  monitored 32 MiB repeat passed without a restart. This remains an unresolved
  stability observation, not a claimed software fix. Its 60 recorded uptime
  samples were monotonic; available RAM stayed at or above 44,692 KiB in that
  monitoring window, with at least 249,532 KiB of swap free.
- Package backup: `/root/ddk-backups/msp-packages-20260914T141023Z`.
  To return to the pre-MSP dashboard, use application backup
  `/root/ddk-backups/20260914T141417Z-field-console-v4` with `rollback.sh`.
  Later backups contain earlier revisions of 4.2 itself.
- Final application deployment backup:
  `/root/ddk-backups/20260914T150227Z-field-console-v4`. This deployment reloaded
  rpcd ACLs without restarting a service or rebooting the appliance.
- Final verification matched all 63 deployed project files and permissions to
  local source. There are 895 installed packages: all 887 original versions
  remain, plus the eight pinned additions. Protected configuration hashes match
  the pre-MSP backup; extroot and swap remain active. No SMB server listener or
  MSP private credential directory remained. Temporary fixture servers and SSH
  test forwards were removed, preserving the user's authenticated SSH terminal.

The physical field checks still belong on the actual equipment: an advertising
switch, an SNMPv3 device, printer/UPS MIB support, and the customer's Windows/NAS
permissions and network path. Loopback and isolated fixture acceptance do not
substitute for those equipment-specific checks. The existing phone app uses the
same router pages; reconnect it to load 4.2. No native iOS code changed.
