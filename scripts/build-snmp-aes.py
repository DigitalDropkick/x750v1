#!/usr/bin/env python3
"""Build Orbit's isolated MIPS SNMP clients; never install host/router packages.

Run on x86_64 Linux with gcc, make, perl, tar and xz. Downloads and intermediates
stay in --cache. Only the two stripped clients and provenance/licenses enter
files/. No agent, listener, core library or OpenSSL configuration is installed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SDK = "openwrt-sdk-22.03.4-ath79-nand_gcc-11.2.0_musl.Linux-x86_64"
SOURCES = [
    (f"https://downloads.openwrt.org/releases/22.03.4/targets/ath79/nand/{SDK}.tar.xz",
     "25eb5618f05facf173f8890df2d84b95f0e0e4ca5ed8dbde0b4af3c953defe2e"),
    ("https://www.openssl.org/source/openssl-3.5.8.tar.gz",
     "a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"),
    ("https://downloads.sourceforge.net/project/net-snmp/net-snmp/5.9.5.2/net-snmp-5.9.5.2.tar.gz",
     "16707719f833184a4b72835dac359ae188123b06b5e42817c00790d7dc1384bf"),
]


def sha(path):
    with path.open("rb") as src:
        return hashlib.file_digest(src, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=Path.home()/".cache/orbit-snmp-build")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    for url, expected in SOURCES:
        archive = cache/url.rsplit("/", 1)[1]
        if not archive.exists():
            temporary = archive.with_suffix(archive.suffix + ".part")
            with urllib.request.urlopen(url, timeout=60) as src, temporary.open("wb") as out:
                shutil.copyfileobj(src, out)
            temporary.replace(archive)
        if sha(archive) != expected:
            raise SystemExit("Source checksum mismatch: " + archive.name)
        directory = cache/archive.name.removesuffix(".tar.xz").removesuffix(".tar.gz")
        if not directory.exists():
            subprocess.run(["tar", "-xf", str(archive), "-C", str(cache)], check=True)
    toolchain = next((cache/SDK/"staging_dir").glob("toolchain-mips_24kc*"))
    cross = str(toolchain/"bin/mips-openwrt-linux-musl-")
    env = dict(os.environ, STAGING_DIR=str(cache/SDK/"staging_dir"),
               SOURCE_DATE_EPOCH="1787616000", LC_ALL="C", TZ="UTC")
    env["PATH"] = str(toolchain/"bin") + os.pathsep + env["PATH"]
    crypto = cache/"crypto-install"
    ssl_build = cache/"mips-crypto"
    snmp_build = cache/"mips-snmp"
    for directory in (ssl_build, snmp_build):
        directory.mkdir(exist_ok=True)

    def run(label, argv, cwd):
        print(label, flush=True)
        log = cache/(label + ".log")
        with log.open("w") as out:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit(f"{label} failed; inspect {log}")

    flags = "-Os -mips32r2 -mtune=24kc -msoft-float -ffunction-sections -fdata-sections"
    run("crypto-configure", ["perl", str(cache/"openssl-3.5.8/Configure"), "linux-mips32",
        "--cross-compile-prefix=" + cross, "--prefix=" + str(crypto), "--libdir=lib",
        "no-shared", "no-tests", "no-apps", "no-docs", "no-module", "no-dso",
        "no-engine", "no-autoload-config", "no-legacy", *flags.split()], ssl_build)
    run("crypto-build", ["make", f"-j{args.jobs}", "build_libs"], ssl_build)
    run("crypto-install", ["make", "install_dev"], ssl_build)
    env.update(CC=cross+"gcc", AR=cross+"ar", RANLIB=cross+"ranlib", STRIP=cross+"strip",
               CFLAGS=flags, LDFLAGS="-static -Wl,--gc-sections", LIBS="-latomic",
               PKG_CONFIG_LIBDIR=str(crypto/"lib/pkgconfig"), PKG_CONFIG_PATH="")
    run("snmp-configure", [str(cache/"net-snmp-5.9.5.2/configure"),
        "--host=mips-openwrt-linux-musl", "--build=x86_64-pc-linux-gnu",
        "--prefix=/usr/libexec/ddk-snmp", "--disable-shared", "--enable-static",
        "--disable-agent", "--disable-embedded-perl",
        "--without-perl-modules", "--without-python-modules", "--without-rpm",
        "--disable-manuals", "--disable-scripts", "--disable-mibs",
        "--enable-blumenthal-aes", "--enable-des", "--with-default-snmp-version=3",
        "--with-sys-contact=", "--with-sys-location=", "--with-logfile=/dev/null",
        "--with-persistent-directory=/tmp/ddk-snmp", "--with-openssl=" + str(crypto)], snmp_build)
    run("snmp-library", ["make", f"-j{args.jobs}", "-C", "snmplib"], snmp_build)
    for name in ("snmpget", "snmpwalk"):
        (snmp_build/"apps"/name).unlink(missing_ok=True)
    # Libtool's -static only selects project archives; -all-static also embeds
    # musl, libgcc and libatomic, avoiding any loader or shared-library dependency.
    run("snmp-clients", ["make", f"-j{args.jobs}", "-C", "apps",
        "LDFLAGS=-all-static -Wl,--gc-sections -Wl,-u,OpenSSL_version -L" + str(crypto/"lib"),
        "snmpget", "snmpwalk"], snmp_build)
    destination = ROOT/"files/usr/libexec/ddk-snmp"
    destination.mkdir(parents=True, exist_ok=True)
    binaries = {}
    for name in ("snmpget", "snmpwalk"):
        target = destination/name
        shutil.copy2(snmp_build/"apps"/name, target)
        subprocess.run([cross+"strip", "--strip-unneeded", str(target)], check=True)
        target.chmod(0o755)
        dynamic = subprocess.check_output([cross+"readelf", "-d", str(target)], text=True)
        if "NEEDED" in dynamic:
            raise SystemExit("Client unexpectedly depends on shared libraries")
        binaries[name] = {"sha256": sha(target), "bytes": target.stat().st_size}
    notices = ROOT/"files/usr/share/ddk-field-console/snmp-aes"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(cache/"net-snmp-5.9.5.2/COPYING", notices/"NET-SNMP-LICENSE.txt")
    shutil.copyfile(cache/"openssl-3.5.8/LICENSE.txt", notices/"OPENSSL-LICENSE.txt")
    shutil.copyfile(toolchain/"info.mk", notices/"toolchain-info.txt")
    # musl's MIT license applies to the libc linked into these static clients.
    musl_license = cache/"musl-COPYRIGHT"
    url = "https://git.musl-libc.org/cgit/musl/plain/COPYRIGHT?h=v1.2.3"
    if not musl_license.exists():
        with urllib.request.urlopen(url, timeout=30) as src:
            musl_license.write_bytes(src.read())
    shutil.copyfile(musl_license, notices/"MUSL-LICENSE.txt")
    for name in ("COPYING3", "COPYING.RUNTIME"):
        source = cache/name
        if not source.exists():
            url = "https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-11.2.0/" + name
            with urllib.request.urlopen(url, timeout=30) as src:
                source.write_bytes(src.read())
        shutil.copyfile(source, notices/("GCC-" + name + ".txt"))
    # Preserve notice wording while removing upstream trailing whitespace so
    # the repository's whitespace validation also covers vendored notices.
    for notice in notices.glob("*.txt"):
        notice.write_text("\n".join(line.rstrip() for line in notice.read_text().splitlines()).rstrip() + "\n")
    manifest = {"net_snmp": "5.9.5.2", "openssl": "3.5.8", "libc": "musl 1.2.3",
        "target": "mips_24kc, MIPS32r2 big-endian soft-float, static",
        "sources": [{"url": u, "sha256": h} for u, h in SOURCES],
        "privacy": ["AES", "AES-192", "AES-256", "AES-192-C", "AES-256-C", "DES"],
        "binaries": binaries}
    (notices/"build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(binaries, indent=2))


if __name__ == "__main__":
    main()
