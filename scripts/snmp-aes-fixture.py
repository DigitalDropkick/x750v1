#!/usr/bin/env python3
"""Temporary laptop-only Net-SNMP agent and loopback TCP/UDP test bridge.

Build a host snmpd from the pinned Net-SNMP source, then provide --agent and a
new --private-dir in /run/user/$UID. Forward the printed TCP port over the
existing SSH connection. Credentials are synthetic, generated, and file-only.
Terminate this process after testing; it terminates its own agent and deletes
its private fixture directory. No router service or firewall change is needed.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import threading
import time

AUTH = ["SHA", "SHA-256", "SHA-512", "SHA-224", "SHA-384", "MD5"]
PRIVACY = ["AES", "AES-192", "AES-256", "AES-192-C", "AES-256-C", "DES"]


def quoted(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def unpack(data):
    tag, length = data[0], data[1]
    offset = 2
    if length & 128:
        size = length & 127
        length = int.from_bytes(data[offset:offset+size], "big")
        offset += size
    return tag, data[offset:offset+length], data[offset+length:]


def exact(stream, size):
    result = b""
    while len(result) < size:
        chunk = stream.recv(size - len(result))
        if not chunk:
            raise EOFError()
        result += chunk
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", type=Path, required=True)
    parser.add_argument("--private-dir", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    root = args.private_dir.resolve()
    root.mkdir(mode=0o700)  # Refuse an existing directory; cleanup owns this tree.
    finished = threading.Event()
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda *_: finished.set())
    port_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    port_socket.bind(("127.0.0.1", 0))
    agent_port = port_socket.getsockname()[1]
    port_socket.close()
    settings = {"users": [], "community": "orbit-fixture-" + secrets.token_hex(12)}
    config = [f"agentaddress udp:127.0.0.1:{agent_port}",
              "sysDescr Orbit AES acceptance fixture", "sysName orbit-aes-fixture",
              "sysLocation Private loopback fixture", "sysContact Orbit testing",
              "rocommunity " + settings["community"] + " 127.0.0.1"]
    for auth in AUTH:
        for privacy in PRIVACY:
            user = {"auth": auth, "privacy": privacy, "username": "fixture" + str(len(settings["users"])),
                    "authpass": '  orbit "auth" \\ ' + secrets.token_hex(12) + '  ',
                    "privpass": '  orbit "privacy" \\ ' + secrets.token_hex(12) + '  '}
            settings["users"].append(user)
            config += ["createUser " + user["username"] + " " + auth + " " + quoted(user["authpass"]) + " " + privacy + " " + quoted(user["privpass"]),
                       "rouser " + user["username"] + " noauth"]
    (root/"agent.conf").write_text("\n".join(config) + "\n")
    (root/"settings.json").write_text(json.dumps(settings))
    stats = {"encrypted_requests": 0, "encrypted_responses": 0, "plaintext_v3": 0,
             "plaintext_fixture_in_encrypted_packet": 0}

    def inspect(data, response=False):
        _, body, _ = unpack(data)
        _, version, body = unpack(body)
        if version != b"\x03":
            return
        _, header, body = unpack(body)
        _, _, header = unpack(header)
        _, _, header = unpack(header)
        _, flags, _ = unpack(header)
        _, _, body = unpack(body)
        tag, _, _ = unpack(body)
        if flags[0] & 2:
            assert tag == 4, "Privacy flag without encrypted scoped PDU"
            assert flags[0] & 1, "Encrypted message lacks authentication"
            stats["encrypted_responses" if response else "encrypted_requests"] += 1
            if b"Orbit AES acceptance fixture" in data:
                stats["plaintext_fixture_in_encrypted_packet"] += 1
        elif not response:
            stats["plaintext_v3"] += 1  # Discovery and explicit non-private tests.
        (root/"wire-stats.json").write_text(json.dumps(stats))

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(5)
            size = struct.unpack("!I", exact(self.request, 4))[0]
            if size > 65535:
                return
            data = exact(self.request, size)
            inspect(data)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.settimeout(2)
                udp.sendto(data, ("127.0.0.1", agent_port))
                try:
                    response = udp.recv(65535)
                except socket.timeout:
                    response = b""
            if response:
                inspect(response, True)
            self.request.sendall(struct.pack("!I", len(response)) + response)

    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True

    agent = None
    server = None
    try:
        with (root/"agent.log").open("w") as log:
            agent = subprocess.Popen([str(args.agent.resolve()), "-f", "-Lo", "-C", "-c", str(root/"agent.conf")],
                env=dict(os.environ, MIBS="", SNMPCONFPATH=str(root), SNMP_PERSISTENT_DIR=str(root)),
                stdout=log, stderr=subprocess.STDOUT)
        time.sleep(2)
        if agent.poll() is not None:
            raise RuntimeError("Fixture agent failed; private log retained until cleanup")
        server = Server(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(json.dumps({"bridge_port": server.server_address[1], "agent_port": agent_port,
                          "matrix_cases": len(settings["users"])}), flush=True)
        while not finished.wait(1):
            if agent.poll() is not None:
                raise RuntimeError("Fixture agent exited")
    finally:
        if server:
            server.shutdown()
            server.server_close()
        if agent and agent.poll() is None:
            agent.terminate()
            try:
                agent.wait(5)
            except subprocess.TimeoutExpired:
                agent.kill()
                agent.wait()
        print(json.dumps(stats), flush=True)
        shutil.rmtree(root)


if __name__ == "__main__":
    main()
