#!/usr/bin/env python3
"""Refresh explicit manifests and reviewed action inventories from v3 definitions."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
families = {
    "firmware":"firmware-programming", "cases":"storage-recovery",
    "wireless":"wireless-diagnostics", "usb":"usb-management", "usbip":"usb-management", "industrial":"modbus-industrial", "serial":"serial", "network": "network-discovery", "automation": "automation", "cellular": "cellular",
    "forensics": "forensics", "auth": "smartcard-auth", "bluetooth": "bluetooth", "can": "can",
    "camera": "camera", "radio": "sdr-radio", "gps": "gps-gnss", "monitoring": "monitoring",
    "capture": "packet-capture", "storage": "storage-recovery", "android": "android-repair",
}
classes = {"ACTION": "enabled-action-ids.txt", "SECURITY": "enabled-security-actions.txt", "DISRUPTIVE": "enabled-disruptive-actions.txt"}
source = (root / "files/usr/share/ddk-field-console/operator-v3.lua").read_text()
definitions = re.findall(r'define\("([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"', source)
for action_id, label, action_class in definitions:
    path = root / "files/usr/share/ddk-field-console/tools" / (families[action_id.split(".")[0]] + ".json")
    source_text = path.read_text()
    entry = {"id": action_id, "label": label, "class": action_class, "execution": "job", "parameter_schema": "operator-v1", "enabled": True}
    encoded = json.dumps(entry)
    if any(item["id"] == action_id for item in json.loads(source_text)["actions"]):
        source_text, count = re.subn(r'\{\s*"id":\s*"' + re.escape(action_id) + r'"[^{}]*\}', lambda _: encoded, source_text)
        assert count == 1, action_id
    else:
        # Preserve the order of existing contracts; append v3 workflows explicitly.
        marker = source_text.index('"actions": [') + len('"actions": [')
        end = source_text.index("\n  ]", marker)
        source_text = source_text[:end].rstrip() + ",\n    " + encoded + source_text[end:]
    path.write_text(source_text)
    if action_class in classes:
        inventory = root / "scripts" / classes[action_class]
        text = inventory.read_text()
        if action_id not in text.splitlines():
            inventory.write_text(text.rstrip() + "\n" + action_id + "\n")

unavailable_path = root / "scripts/unavailable-action-ids.txt"
remaining = []
for path in sorted((root / "files/usr/share/ddk-field-console/tools").glob("*.json")):
    remaining.extend(item["id"] for item in json.loads(path.read_text())["actions"] if not item["enabled"])
unavailable_path.write_text("# Actions awaiting a concrete native implementation; hardware readiness is evaluated live.\n" + ("\n".join(sorted(remaining)) + "\n" if remaining else ""))
print(f"Updated {len(definitions)} v3 workflow contracts")
