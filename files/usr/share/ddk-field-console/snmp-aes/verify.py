#!/usr/bin/env python3
"""Verify the shipped static MIPS clients before install and on the appliance."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--native", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((args.root/"usr/share/ddk-field-console/snmp-aes/build.json").read_text())
    assert set(manifest["binaries"]) == {"snmpget", "snmpwalk"}
    for name, expected in manifest["binaries"].items():
        path = args.root/"usr/libexec/ddk-snmp"/name
        assert not path.is_symlink(), "Client must be a regular release file"
        data = path.read_bytes()
        assert len(data) == expected["bytes"] and len(data) <= 8*1024*1024
        assert hashlib.sha256(data).hexdigest() == expected["sha256"], "Client checksum mismatch"
        assert data[:7] == b"\x7fELF\x01\x02\x01", "Expected 32-bit big-endian ELF"
        assert struct.unpack_from(">H", data, 18)[0] == 8, "Expected MIPS machine"
        phoff = struct.unpack_from(">I", data, 28)[0]
        size, count = struct.unpack_from(">HH", data, 42)
        for index in range(count):
            kind = struct.unpack_from(">I", data, phoff + index*size)[0]
            assert kind not in (2, 3), "Client requires dynamic linking or an interpreter"
        assert ("OpenSSL " + manifest["openssl"]).encode() in data
        if args.native:
            result = subprocess.run([str(path), "-V"], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0 and manifest["net_snmp"] in result.stdout + result.stderr
        print("PASS isolated SNMP client: " + name + " (hash, ABI, static linkage" + (", native execution" if args.native else "") + ")")


if __name__ == "__main__":
    main()
