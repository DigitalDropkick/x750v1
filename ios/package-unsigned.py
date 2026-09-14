#!/usr/bin/env python3
"""Package an actual iPhone build for local signing; never sign on the runner."""
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

app, output = (Path(value).resolve() for value in sys.argv[1:])
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert info["CFBundleIdentifier"] == "com.digitaldropkick.orbit"
assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Refusing a simulator app"
binary = app / info["CFBundleExecutable"]
with binary.open("rb") as stream:
    magic, architecture = struct.unpack("<II", stream.read(8))
assert magic == 0xFEEDFACF and architecture == 0x100000C, "Expected arm64 Mach-O"
assert not (app / "embedded.mobileprovision").exists(), "Unsigned package must not contain a profile"
assert not (app / "_CodeSignature").exists(), "Expected unsigned build"
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        assert not path.is_symlink(), "Unexpected symlink in iPhone app"
        if path.is_file():
            archive.write(path, "Payload/Orbit.app/" + path.relative_to(app).as_posix())
print(f"Packaged unsigned iPhone arm64 app {info['CFBundleShortVersionString']}: {output.name}")
print("Apple signing is still required on the installation computer or iPhone.")
