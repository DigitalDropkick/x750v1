#!/usr/bin/env python3
"""Loopback-only LuCI-shaped HTTPS fixture. No router or Apple credentials.

Certificates/keys are generated into a private temporary directory and never
uploaded. This tests the native transport and WebKit boundary, not router tools.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
import ssl
import subprocess
import tempfile

CONSOLE = "/cgi-bin/luci/admin/ddk/overview"
COOKIE = "sysauth_https=orbit-test-session"
PAGE = b'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
body {background:#080d19;color:#dceefa;font:18px system-ui;padding:30px} a,button {display:block;margin:24px 0;color:#83e7f4;background:#111c30;padding:16px;border:0;font:inherit}
</style></head><body><main id="ddk-app"><h1>Orbit test workspace</h1>
<p>This is a native integration fixture, not the live router.</p>
<a href="/cgi-bin/luci/admin/ddk/download" download>Download test report</a>
<form action="/cgi-bin/luci/admin/ddk/export" method="POST" target="_blank"><input type="hidden" name="format" value="text"><button>Export test case</button></form>
<iframe name="orbit-download-frame" hidden></iframe>
<form action="/cgi-bin/luci/admin/ddk/export" method="POST" target="orbit-download-frame"><input type="hidden" name="format" value="large"><button id="stream-export">Download large artifact</button></form>
<button onclick="saveBlob(new Blob(['orbit blob report\\n'],{type:'text/plain'}),'orbit-blob.txt')">Download browser report</button>
<button onclick="window.webkit.messageHandlers.orbit.postMessage({type:'connection'})">Connection settings</button>
</main></body></html>'''

# Exercise the router's actual browser export helper, including URL lifetime.
source = (Path(__file__).resolve().parents[2] / "files/www/luci-static/resources/ddk/console-app.js").read_text()
save_blob = "function saveBlob" + source.split("function saveBlob", 1)[1].split("\n\tasync function loadSnapshot", 1)[0]
helper = "function h(tag,attrs){let el=document.createElement(tag);Object.entries(attrs).forEach(([k,v])=>el.setAttribute(k,v));return el;}"
PAGE = PAGE.replace(b"</head>", ("<script>" + helper + save_blob + "</script></head>").encode())


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request headers, bodies or cookies.

    def send(self, status, body, kind="text/html", **headers):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        return COOKIE in self.headers.get("Cookie", "")

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/health":
            self.send(200, b"ready", "text/plain")
        elif path == CONSOLE:
            self.send(200 if self.authorized() else 403, PAGE if self.authorized() else b"Sign in")
        elif path == "/cgi-bin/luci/admin/ddk/download" and self.authorized():
            self.send(200, b"orbit native report\n", "text/plain", Content_Disposition='attachment; filename="orbit-report.txt"')
        elif path == "/cgi-bin/luci/admin/ddk/redirect":
            self.send(302, b"", Location="https://example.invalid/unexpected")
        else:
            self.send(404, b"Not found")

    def do_POST(self):
        data = self.rfile.read(min(int(self.headers.get("Content-Length", "0")), 4096))
        form = parse_qs(data.decode("utf-8"))
        path = urlsplit(self.path).path
        if path == CONSOLE:
            # Deliberately synthetic credentials exercise literal form encoding.
            if form == {"luci_username": ["orbit-test+operator"], "luci_password": ["test &+ unicode ü"]}:
                # LuCI sets its cookie and redirects to the route without query.
                self.send(302, b"", Location=CONSOLE,
                          Set_Cookie=COOKIE + "; Path=/cgi-bin/luci; HttpOnly; Secure; SameSite=Strict")
            else:
                self.send(403, b"Sign in")
        elif path == "/cgi-bin/luci/admin/ddk/export" and self.authorized() and form == {"format": ["text"]}:
            self.send(200, b"orbit POST case\n", "text/plain", Content_Disposition='attachment; filename="orbit-case.txt"')
        elif path == "/cgi-bin/luci/admin/ddk/export" and self.authorized() and form == {"format": ["large"]}:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="orbit-streamed.bin"')
            self.send_header("Content-Length", str(17 * 1024 * 1024))
            self.end_headers()
            for _ in range(17):
                self.wfile.write(b"X" * 1024 * 1024)
        else:
            self.send(403, b"Not authorized")


with tempfile.TemporaryDirectory(prefix="orbit-fixture-") as directory:
    root = Path(directory)
    cert, key, csr = (root / name for name in ("cert.pem", "key.pem", "request.pem"))
    (root / "index.txt").write_text("")
    (root / "serial").write_text("01\n")
    config = root / "ca.cnf"
    config.write_text(f"""[ca]
default_ca = fixture
[fixture]
database = {root}/index.txt
serial = {root}/serial
new_certs_dir = {root}
default_md = sha256
policy = names
[names]
commonName = supplied
[extensions]
subjectAltName = IP:127.0.0.1
""")
    subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                    "-subj", "/CN=Orbit simulator fixture", "-keyout", str(key), "-out", str(csr)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Explicit historical dates work with both macOS LibreSSL and OpenSSL.
    # Match the appliance's expired self-signed certificate, without relying
    # on a negative -days value (rejected by some OpenSSL implementations).
    subprocess.run(["openssl", "ca", "-batch", "-selfsign", "-config", str(config),
                    "-keyfile", str(key), "-in", str(csr), "-out", str(cert),
                    "-startdate", "20200101000000Z", "-enddate", "20250101000000Z",
                    "-extensions", "extensions"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    expired = subprocess.run(["openssl", "x509", "-in", str(cert), "-checkend", "0", "-noout"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert expired.returncode == 1, "Test certificate must be expired"
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = ThreadingHTTPServer(("127.0.0.1", 18443), Handler)
    # Browsers speculatively open idle sockets. Handshake in each request thread,
    # not accept(), so an idle socket cannot block every other connection.
    server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    print("Orbit test fixture ready at https://127.0.0.1:18443", flush=True)
    server.serve_forever()
