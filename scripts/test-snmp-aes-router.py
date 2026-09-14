#!/usr/bin/env python3
"""Real encrypted SNMP acceptance through an owned loopback SSH test bridge.

Read synthetic fixture settings from stdin, never process arguments. By default
exercise staged native clients/helper; --installed exercises actual Orbit jobs.
No network target other than loopback is accepted by this test.
"""
import argparse
import base64
import hashlib
import importlib.machinery
import json
import os
import signal
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True


def exact(stream, size):
    data = b""
    while len(data) < size:
        chunk = stream.recv(size-len(data))
        if not chunk:
            raise EOFError()
        data += chunk
    return data


class Bridge:
    def __init__(self, tcp_port, ipv6=False):
        self.socket = socket.socket(socket.AF_INET6 if ipv6 else socket.AF_INET, socket.SOCK_DGRAM)
        self.host = "::1" if ipv6 else "127.0.0.1"
        self.socket.bind((self.host, 0))
        self.socket.settimeout(.2)
        self.port = self.socket.getsockname()[1]
        self.tcp_port = tcp_port
        self.running = True
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while self.running:
            try:
                data, peer = self.socket.recvfrom(65535)
            except socket.timeout:
                continue
            try:
                with socket.create_connection(("127.0.0.1", self.tcp_port), timeout=5) as tcp:
                    tcp.sendall(struct.pack("!I", len(data)) + data)
                    length = struct.unpack("!I", exact(tcp, 4))[0]
                    response = exact(tcp, length)
                if response:
                    self.socket.sendto(response, peer)
            except (OSError, EOFError):
                pass  # The native client's timeout must remain a failure.

    def close(self):
        self.running = False
        self.thread.join(6)
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge-port", type=int, default=2461)
    parser.add_argument("--stage", type=Path, default=Path("/tmp/orbit-aes-stage/files"))
    parser.add_argument("--installed", action="store_true")
    parser.add_argument("--bridge-only", action="store_true", help="Temporary loopback endpoint for browser acceptance")
    args = parser.parse_args()
    os.umask(0o077)
    if args.bridge_only:
        bridge = Bridge(args.bridge_port)
        ended = threading.Event()
        signal.signal(signal.SIGTERM, lambda *_: ended.set())
        signal.signal(signal.SIGINT, lambda *_: ended.set())
        print(json.dumps({"pid": os.getpid(), "port": bridge.port}), flush=True)
        try:
            # A lost testing terminal cannot leave this helper indefinitely.
            ended.wait(1200)
        finally:
            bridge.close()
        return
    settings = json.load(sys.stdin)
    values = [settings["community"]] + [u[k] for u in settings["users"] for k in ("authpass", "privpass")]
    before_uptime = float(Path("/proc/uptime").read_text().split()[0])
    protected = [Path("/etc/config")/n for n in ("network", "wireless", "firewall", "uhttpd", "rpcd")]
    protected += [Path(p) for p in ("/usr/bin/snmpget", "/usr/bin/snmpwalk", "/lib/libc.so")]
    protected += list(Path("/usr/lib").glob("libcrypto.so*")) + list(Path("/usr/lib").glob("libnetsnmp.so*"))
    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    before = hashes()
    bridge, bridge6 = Bridge(args.bridge_port), Bridge(args.bridge_port, True)
    helper_path = (Path("/") if args.installed else args.stage)/"usr/libexec/ddk-network-tools"
    helper = importlib.machinery.SourceFileLoader("snmp_helper", str(helper_path)).load_module()
    created = []
    measurements = {"max_native_rss_kib": 0, "min_available_kib": 1000000}

    def clean_text(text):
        for value in values:
            text = text.replace(value, "[FIXTURE REDACTED]")
        return text

    def call(*arguments, payload=None):
        if payload is None:
            argv = ["/usr/libexec/ddk-console", *arguments]
        else:
            # Keep even synthetic credentials out of process arguments.
            argv = ["lua", "-e", 'arg={"action","prepare","network.snmp",io.read("*a")};dofile("/usr/libexec/ddk-console")']
        result = subprocess.run(argv, input=payload, capture_output=True, text=True, timeout=60)
        response = json.loads(result.stdout)
        assert response["ok"], clean_text(response.get("message", "Backend request failed"))
        return response["data"]

    def prepare(options):
        payload = base64.urlsafe_b64encode(json.dumps({"version": 1, "options": options}).encode()).decode().rstrip("=")
        return call(payload=payload)

    def finish(job):
        for _ in range(160):
            state = call("job", "status", job["id"])
            if state["status"] in ("complete", "failed", "stopped"):
                assert not Path("/tmp/ddk/jobs", job["id"], "private-msp").exists()
                assert not any(v in json.dumps(state) for v in values)
                return state
            time.sleep(.25)
        raise AssertionError("Owned SNMP job did not terminate")

    def run(user, profile="get", expected=True, version="3", level="authPriv", ipv6=False):
        endpoint = bridge6 if ipv6 else bridge
        options = dict(user, version=version, level=level, profile=profile,
                       community=settings["community"] if version != "3" else "",
                       host=endpoint.host, port=endpoint.port, oid=".1.3.6.1.2.1.1.1.0" if profile == "get" else ".1.3.6.1.2.1.1",
                       context="", timeout=3, retries=0, duration=25, output_mib=1)
        if args.installed:
            plan = prepare(options)
            job = call("job", "start", plan["prepared_id"])
            created.append(job)
            result = finish(job)
            code = 0 if result["status"] == "complete" else 1
            output, error = result["stdout"], result["stderr"]
            if expected:
                call("job", "save", job["id"])
                assert call("job", "status", job["id"])["saved"]
        else:
            with tempfile.TemporaryDirectory(prefix="orbit-snmp-client-", dir="/tmp") as tmp:
                root = Path(tmp)
                native_options = dict(options, workspace=str(root/"output"), private_dir=str(root/"private"))
                for key in ("authpass", "privpass", "community"):
                    path = root/key
                    path.write_text(native_options[key])
                    native_options[key] = str(path)
                captured = {}
                def native(argv, **kwargs):
                    assert not any(v in " ".join(argv) for v in values)
                    argv[0] = str(args.stage/argv[0].lstrip("/"))
                    with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, **kwargs) as process:
                        started = time.monotonic()
                        while process.poll() is None:
                            assert time.monotonic()-started < 25, "Native client did not terminate"
                            try:
                                status = Path(f"/proc/{process.pid}/status").read_text()
                                for line in status.splitlines():
                                    if line.startswith("VmRSS:"):
                                        measurements["max_native_rss_kib"] = max(measurements["max_native_rss_kib"], int(line.split()[1]))
                            except FileNotFoundError:
                                pass
                            memory = dict((l.split(":")[0], l.split()[1]) for l in Path("/proc/meminfo").read_text().splitlines())
                            measurements["min_available_kib"] = min(measurements["min_available_kib"], int(memory["MemAvailable"]))
                            time.sleep(.05)
                        stdout, stderr = process.communicate()
                    captured.update(stdout=stdout.decode(), stderr=stderr.decode())
                    return process.returncode
                helper.run = native
                code = helper.snmp(argparse.Namespace(**native_options))
                output, error = captured["stdout"], captured["stderr"]
                assert (root/"private/snmp.conf").stat().st_mode & 0o777 == 0o600
        assert (code == 0) == expected, clean_text(error) or "Unexpected SNMP result"
        if expected:
            assert "Orbit AES acceptance fixture" in output, "Missing fixture value"
        else:
            assert "Orbit AES acceptance fixture" not in output, "Wrong credential returned equipment data"
        assert not any(v in output + error for v in values)

    try:
        users = settings["users"]
        matrix = users if not args.installed else [u for u in users if u["auth"] == "SHA" or (u["auth"] == "SHA-256" and u["privacy"] == "AES")]
        for user in matrix:
            run(user)
            print("PASS encrypted GET " + user["auth"] + " / " + user["privacy"], flush=True)
        for user in [u for u in users if u["auth"] == "SHA"]:
            run(user, profile="walk")
            print("PASS encrypted WALK " + user["privacy"], flush=True)
        user = users[0]
        run(user, ipv6=True)
        for version in ("1", "2c"):
            run(user, version=version)
        for level in ("authNoPriv", "noAuthNoPriv"):
            run(user, level=level)
        print("PASS IPv6, SNMPv1/v2c and explicit non-private v3 compatibility", flush=True)
        for key in ("authpass", "privpass"):
            run(dict(user, **{key: "deliberately-wrong-fixture-passphrase"}), expected=False)
        run(dict(user, username="unknown-fixture-user"), expected=False)
        print("PASS wrong authentication, wrong privacy and unknown user fail without equipment data", flush=True)
        if args.installed:
            # A silent owned loopback endpoint keeps the client alive for Stop.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent:
                silent.bind(("127.0.0.1", 0))
                plan = prepare(dict(user, version="3", level="authPriv", host="127.0.0.1",
                                    port=silent.getsockname()[1], timeout=10, retries=3, duration=60, output_mib=1))
                job = call("job", "start", plan["prepared_id"])
                created.append(job)
                time.sleep(2)
                call("job", "stop", job["id"])
                assert finish(job)["status"] == "stopped"
            print("PASS encrypted job Stop, saved results and RAM credential cleanup", flush=True)
        assert hashes() == before, "Protected system files changed"
        assert float(Path("/proc/uptime").read_text().split()[0]) > before_uptime, "Router restarted"
        print("PASS protected configuration, stock SNMP/crypto/libc bytes and continuous uptime", flush=True)
        if not args.installed:
            print(json.dumps(measurements), flush=True)
    finally:
        for job in created:
            state = call("job", "status", job["id"])
            if state["status"] in ("queued", "running", "stopping"):
                call("job", "stop", job["id"])
                finish(job)
            call("job", "delete", job["id"])
        bridge.close()
        bridge6.close()


if __name__ == "__main__":
    main()
