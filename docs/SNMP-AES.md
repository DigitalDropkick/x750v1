# Orbit 4.2.1: SNMPv3 encryption

Equipment checks now use private Net-SNMP 5.9.5.2 clients with OpenSSL 3.5.8.
The firmware's SNMP 5.9.1 clients were compiled without AES; their binaries and
libraries remain unchanged. No firmware, modem, cellular, Wi-Fi, firewall,
service, package or system-library replacement is required.

## Use from the existing iPhone app

Reconnect Orbit, open **Tools → Network → Equipment check**, and select
**Encrypted SNMPv3**. Enter the equipment address, SNMPv3 username,
authentication method/passphrase and privacy passphrase. AES-128 is selected
initially; match the device's configured encryption. Start with Identity & uptime,
then use interface counters, printer/UPS profiles or custom numeric GET/walk.
Results retain exact OIDs alongside friendly measurement labels. Save a case to
retain the output; follow-up actions carry the selected equipment address.

| Form label | Native value | Compatibility |
| --- | --- | --- |
| AES-128 (standard) | AES | RFC 3826, usual first choice |
| AES-192 / AES-256 (Blumenthal) | AES-192 / AES-256 | Extended-key variant used by some agents |
| AES-192 / AES-256 (Cisco / Reeder) | AES-192-C / AES-256-C | Alternate key-extension variant; match the equipment |
| DES (legacy) | DES | Existing older-device compatibility |

SHA-1, SHA-224/256/384/512 and MD5 authentication remain selectable. The form
also retains SNMPv1/v2c, authNoPriv and noAuthNoPriv for equipment that needs
them. No request silently falls back to unencrypted SNMP or a different cipher.
AES-192/256 are vendor extensions, so a passing fixture test does not establish
compatibility with every manufacturer's implementation.

Passphrases use owner-only configuration files in the job's RAM directory,
never native client arguments. Significant whitespace, quotes and backslashes
are preserved. Completion, failure and Stop remove the private job files.
Saved cases and downloadable results exclude passphrases.

## Build and deployment

The two stripped executables live under `/usr/libexec/ddk-snmp/`; each is about
2.8 MiB. They statically include crypto, musl and GCC runtime support. There is
no dynamic loader dependency, library search override or background daemon.
Run `python3 scripts/build-snmp-aes.py` on x86_64 Linux to rebuild them using the
pinned OpenWrt 22.03.4 MIPS 24Kc SDK. Build tools are gcc, make, perl, tar, xz
and Python 3.11+. Downloads and build trees stay in the selected cache directory.

Source URLs/checksums, output hashes/sizes and third-party licenses ship in
`files/usr/share/ddk-field-console/snmp-aes/`. The build uses unmodified upstream
sources. Net-SNMP enables extended AES and legacy DES; OpenSSL disables dynamic
modules, engines, config autoloading and external providers. The private crypto
copy must receive its own future maintenance; changing system OpenSSL does not
update these static clients.

`./scripts/validate-local.sh` checks the release, unit suites, binary hashes,
MIPS ABI and absence of dynamic linking. Normal `deploy.sh` transfers the bundle,
verifies both binaries execute on the actual router before writing application
files, backs up every replaced file, and includes new binaries in rollback.
No `opkg` operation is needed. Use the printed backup path with `./rollback.sh`
to return to 4.2.0 and remove the isolated clients while retaining saved cases.

## Validation

`scripts/snmp-aes-fixture.py` starts an owned laptop agent with 36 synthetic
users: six authentication algorithms crossed with six privacy selections. It
binds only loopback and exposes a loopback TCP bridge, carried by a temporary
SSH forward. The test agent and all credentials are deleted when it exits.
The SNMP service is never installed or enabled on the router.

`scripts/test-snmp-aes-router.py` reads the synthetic settings from stdin,
queries through an owned IPv4/IPv6 loopback bridge and supports staged native
testing or `--installed` Orbit jobs. It covers encrypted GET/walk, compatibility,
wrong credentials, stock-file hashes, uptime and cleanup. Installed tests also
exercise Save and Stop. The fixture checks SNMPv3 authentication/privacy flags
and encrypted scoped-PDU encoding in both directions.

Staged router acceptance passed all 36 encrypted GET combinations, six encrypted
walks, IPv6, v1/v2c, both explicit non-private v3 levels, wrong authentication,
wrong privacy and unknown-user failures. The fixture observed 268 encrypted
requests and 265 encrypted responses with no fixture value exposed as plaintext
in encrypted packets. Sampled native client RSS peaked at 2,852 KiB; available
router RAM stayed at or above 37,088 KiB during that test with temporary staging
and test helpers present. These are observations, not fixed per-job budgets.
Stock SNMP/crypto/libc and protected configuration hashes stayed unchanged;
uptime remained continuous.

Physical switch/printer/UPS acceptance still depends on the equipment's access
view, supported MIBs, configured credentials, encryption variant and network path.
The earlier unrelated watchdog restart recorded in MSP-TOOLS.md remains an
unresolved observation; this encryption update does not claim to fix its cause.

## Upstream references

- [Net-SNMP release source](https://www.net-snmp.org/download.html)
- [Net-SNMP command options](https://www.net-snmp.org/docs/man/snmpcmd.html)
- [Net-SNMP extended encryption](https://www.net-snmp.org/wiki/index.php/Strong_Authentication_or_Encryption)
- [OpenSSL source releases](https://www.openssl.org/source/)
- [OpenWrt 22.03.4 SDK checksums](https://downloads.openwrt.org/releases/22.03.4/targets/ath79/nand/sha256sums)
