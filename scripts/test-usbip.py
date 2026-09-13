#!/usr/bin/env python3
"""Protocol fixtures for the real USB/IP adapter; no USB hardware is touched."""
import importlib.machinery
import importlib.util
import socket
import struct
import sys
sys.dont_write_bytecode = True
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "files/usr/libexec/ddk-usbip-client"
loader = importlib.machinery.SourceFileLoader("usbip_adapter", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)


class Peer:
    def __init__(self, opcode, payload, request_size=8):
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(1)
        self.port = self.server.getsockname()[1]
        self.opcode, self.payload, self.request_size = opcode, payload, request_size
        self.error = None

    def __enter__(self):
        def run():
            try:
                with self.server, self.server.accept()[0] as sock:
                    sock.settimeout(3)
                    request = b""
                    while len(request) < self.request_size:
                        chunk = sock.recv(self.request_size - len(request))
                        if not chunk:
                            raise AssertionError("Truncated request")
                        request += chunk
                    assert request[:8] == struct.pack("!HHI", 0x0111, self.opcode, 0)
                    if self.request_size == 40:
                        assert request[8:] == b"7-2" + b"\0" * 29
                    # Deliberately split the header and descriptor across TCP sends.
                    for i in range(0, len(self.payload), 3):
                        sock.sendall(self.payload[i:i+3])
            except (ConnectionResetError, BrokenPipeError):
                pass
            except Exception as error:
                self.error = error
        self.thread = threading.Thread(target=run)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.thread.join(5)
        self.server.close()
        assert not self.thread.is_alive(), "Fixture peer did not stop"
        if self.error:
            raise self.error


def descriptor(busid=b"7-2", speed=3):
    return (b"/sys/devices/fixture".ljust(256, b"\0") + busid.ljust(32, b"\0") +
            struct.pack("!IIIHHH6B", 7, 2, speed, 0x1234, 0x5678, 0x0100, 0, 0, 0, 1, 1, 1))


class USBIPTests(unittest.TestCase):
    def test_fragmented_device_list(self):
        payload = bytes.fromhex("011100050000000000000001") + descriptor() + bytes.fromhex("ff420100")
        with Peer(0x8005, payload) as peer:
            devices = list(client.list_remote("127.0.0.1", peer.port, 2))
        self.assertEqual(devices[0]["busid"], "7-2")
        self.assertEqual(devices[0]["interface_classes"], ["ff:42:01"])

    def test_protocol_rejection_and_short_reply(self):
        for payload in (bytes.fromhex("0111000500000001"), bytes.fromhex("0112000500000000"), b"\1\21"):
            with Peer(0x8005, payload) as peer:
                with self.assertRaises((OSError, ValueError)):
                    list(client.list_remote("127.0.0.1", peer.port, 2))

    def make_vhci(self, root):
        (root / "status").write_text("hub port sta spd dev sockfd local_busid\n"
                                    "hs 0000 004 000 00000000 000000 0-0\n"
                                    "hs 0001 006 003 00070002 000007 2-1\n"
                                    "ss 0008 004 000 00000000 000000 0-0\n")
        (root / "attach").write_text("")
        (root / "detach").write_text("")

    def test_import_selects_native_speed_port_and_passes_socket(self):
        for speed, expected in ((3, 0), (5, 8)):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.make_vhci(root)
                payload = bytes.fromhex("0111000300000000") + descriptor(speed=speed)
                with Peer(0x8003, payload, 40) as peer:
                    result = client.attach("127.0.0.1", peer.port, "7-2", 2, root)
                fields = list(map(int, (root / "attach").read_text().split()))
                self.assertEqual(fields[0], expected)
                self.assertGreaterEqual(fields[1], 0)
                self.assertEqual(fields[2:], [0x70002, speed])
                self.assertEqual(result["attached_port"], expected)

    def test_import_never_substitutes_target(self):
        payload = bytes.fromhex("0111000300000000") + descriptor(busid=b"7-3")
        with Peer(0x8003, payload, 40) as peer:
            with self.assertRaises(ValueError):
                client.attach("127.0.0.1", peer.port, "7-2", 2)

    def test_detach_protection_follows_storage_topology(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            proc, sysroot = root / "proc", root / "sys"
            (proc / "net").mkdir(parents=True)
            (sysroot / "class/block").mkdir(parents=True)
            target = sysroot / "devices/vhci/usb2/2-1/2-1:1.0/block/sdb/sdb1"
            target.mkdir(parents=True)
            (sysroot / "class/block/sdb1").symlink_to(target)
            (proc / "mounts").write_text("/dev/sdb1 /mnt/external ext4 rw 0 0\n")
            (proc / "swaps").write_text("Filename Type Size Used Priority\n")
            (proc / "net/route").write_text("Iface Destination\n")
            self.assertIsNotNone(client.detach_reason("2-1", sysroot, proc))
            self.assertIsNone(client.detach_reason("2-10", sysroot, proc))


if __name__ == "__main__":
    unittest.main()
