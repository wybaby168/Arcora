#!/usr/bin/env python3
"""Refuse RAR encoder packages, registrations and evaluation bypasses in customer builds."""
import argparse
from pathlib import Path
import plistlib

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("app",type=Path)
parser.add_argument("--allow-local-test-encoder",action="store_true",help="Only the private app.arcora.desktop.rar-evaluation bundle; never a distribution check")
args=parser.parse_args()
app=args.app.resolve(strict=True)
info=plistlib.loads((app/"Contents/Info.plist").read_bytes())
if args.allow_local_test_encoder and info.get("CFBundleIdentifier")!="app.arcora.desktop.rar-evaluation":
    raise SystemExit("The encoder exception is restricted to the local test bundle identifier.")
if info.get("ArcoraRARLocalEvaluation") is True:
    raise SystemExit("Customer distribution refused: local codec evaluation flag is enabled.")
if info.get("ArcoraRARCustomerLicenseRequired") is not True:
    raise SystemExit("Customer distribution refused: customer-owned RAR license policy is missing.")
for path in app.rglob("*"):
    if path.is_file():
        if not args.allow_local_test_encoder and (path.name.lower() in {"rar","unrar","default.sfx","arcora-package.json"} or path.name.lower().startswith("rarmacos-")):
            raise SystemExit("Customer distribution refused: RAR encoder or original package was included.")
        if path.name.lower() in {"rarreg.key",".rarreg.key",".rarregkey","arcora-acceptance.json"}:
            raise SystemExit("Customer distribution refused: a private RAR registration file was included.")
        with path.open("rb") as stream:
            if stream.read(128).lstrip(b'\xef\xbb\xbf').startswith(b"RAR registration data"):
                raise SystemExit("Customer distribution refused: a renamed private RAR key was included.")
print("PASS: no registration file or evaluation bypass; " + ("PRIVATE LOCAL TEST encoder exception only." if args.allow_local_test_encoder else "no RAR encoder or original RAR package in app."))
