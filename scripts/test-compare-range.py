#!/usr/bin/env python3
import runpy
import tempfile
from pathlib import Path

compare = runpy.run_path(str(Path(__file__).resolve().parents[1] / "files/usr/libexec/ddk-compare-range"))["compare"]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    original, destination = root / "image", root / "destination"
    content = bytes(range(256)) * 2049
    original.write_bytes(content)
    destination.write_bytes(b"prefix!" + content + b"suffix!")
    assert compare(original, destination, 7, len(content)) == 0
    assert compare(original, destination, 8, len(content)) == 1
    destination.write_bytes(b"prefix!" + content[:-1])
    try:
        compare(original, destination, 7, len(content))
    except OSError:
        pass
    else:
        raise AssertionError("Short destination was accepted")
print("DDK_RANGE_COMPARE_OK: offset, multiple blocks, mismatch, short destination")
