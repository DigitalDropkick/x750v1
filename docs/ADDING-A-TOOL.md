# Adding a Tool Module

Tool modules are data, not executable plugins. One JSON file adds a card and detection metadata; execution remains impossible until the backend separately implements and allowlists an action ID.

## 1. Create one manifest

Add a lowercase file below:

```text
files/usr/share/ddk-field-console/tools/
```

The shipped Nmap entry is the concrete reviewed example. Its relevant fields in `network-discovery.json` are:

```json
{
  "id": "network-discovery",
  "name": "Network Discovery",
  "category": "Network Diagnostics",
  "description": "Bounded host discovery on an explicitly permitted local subnet.",
  "package_names": ["nmap-full"],
  "expected_binaries": ["nmap"],
  "required_hardware": [],
  "status_probe": "software",
  "risk_level": "SECURITY",
  "enabled": true,
  "actions": [
    {
      "id": "network.nmap_lan_discovery",
      "class": "SECURITY",
      "enabled": true
    }
  ],
  "help_text": "The enabled profile performs host discovery only on the server-derived private br-lan subnet; all other discovery actions remain disabled."
}
```

That manifest is only one gate. The action runs because the same exact ID is also implemented in the backend `job_actions` table, mapped to the fixed `nmap_lan_discovery` worker task, included in `scripts/enabled-security-actions.txt`, and rendered with a dedicated confirmation path. Copying a manifest alone cannot create executable behavior.

## Manifest fields

| Field | Rule |
| --- | --- |
| `id` | Unique lowercase identifier: letters, digits, dots, underscores, or hyphens. |
| `name` | Human-readable concise product label. |
| `category` | Existing category name unless the product taxonomy deliberately changes. |
| `description` | What capability the installed software provides. |
| `package_names` | Exact opkg package names; any match establishes software presence. |
| `expected_binaries` | Binary names or absolute paths; any match also establishes software presence. |
| `required_hardware` | Symbolic hardware classes only. Empty means no special hardware requirement. |
| `status_probe` | Symbolic allowlisted probe ID, never a command. |
| `risk_level` | `INFO`, `ACTION`, `DISRUPTIVE`, or `SECURITY`. |
| `enabled` | Whether console behavior has been deliberately wired. Default false. |
| `actions` | Descriptive action IDs with class and enabled state. Data alone cannot execute them. |
| `help_text` | Operator-facing limitations or next-step guidance. |

Supported phase-one hardware classes are:

```text
usb serial cellular_modem video rtl_sdr can bluetooth i2c spi gps
android apple_mobile smartcard programmer usb_storage
```

## 2. Validate the manifest

```sh
jq -e . files/usr/share/ddk-field-console/tools/network-discovery.json
./scripts/validate-local.sh
```

## 3. Enabling an action is a separate change

Before changing `enabled`:

1. Assign the correct security class.
2. Define every accepted argument and reject everything else.
3. Decide timeout, concurrency, output, retention, and cancellation limits.
4. Implement an exact server-side allowlist entry in `ddk-console`.
5. Never use a manifest `status_probe`, name, package, binary, or browser parameter as shell syntax.
6. Add an exact `cgi-io` file ACL command only if the existing fixed-helper ACL no longer covers the call.
7. Add success, failure, injection, traversal, resource, and stop tests.
8. Document operational impact and rollback.

The shipped Nmap profile is still classified `SECURITY`. It uses `/usr/bin/nmap` with fixed host-discovery-only arguments, a server-derived `br-lan` CIDR, RFC1918 and `/24`-or-smaller checks, fixed retry/rate/host/wall-time limits, one-scan concurrency, bounded transient output, and explicit operator confirmation. It accepts no raw Nmap flags or free-form target.

## 4. Review state semantics

- Package/binary absent: `UNAVAILABLE`.
- Software present but required hardware absent: `HARDWARE REQUIRED`.
- Device-oriented repair tooling with `no_device_state`: `READY / NO DEVICE`.
- Software/hardware ready but console behavior disabled: `NOT CONFIGURED`.
- Fully wired reviewed module: `READY`.
