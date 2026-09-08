#!/usr/bin/env python3
"""Negative checks: no grant or release credentials are invented for testing."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
env = {key: value for key, value in os.environ.items() if key not in (
    "ARCORA_RAR_DISTRIBUTION_DIR", "SIGN_IDENTITY", "NOTARY_PROFILE", "ARCORA_RAR_LOCAL_EVALUATION", "ARCORA_RELEASE_RAR_PACKAGE", "ARCORA_RELEASE_LICENSE_FILE")}
checks = []

def refused(command, expected, environment=env):
    result = subprocess.run(command, cwd=root, env=environment, text=True, capture_output=True, timeout=30)
    diagnostic = result.stdout + result.stderr
    if result.returncode == 0 or expected not in diagnostic:
        raise RuntimeError("Release gate did not refuse safely: " + diagnostic)
    checks.append({"command": command[:2], "refused": True, "reason": expected})

refused(["bash", "Scripts/build-app.sh"], "This edition does not distribute the RAR encoder", dict(env, ARCORA_RAR_DISTRIBUTION_DIR="/missing/not-authorized"))
refused(["bash", "Scripts/release-rar.sh"], "Provide the original RAR package")
refused(["bash", "Scripts/build-rar-test-app.sh"], "For local evaluation under RARLAB terms only")
with tempfile.TemporaryDirectory(prefix="Arcora-gate-test-") as temporary:
    folder = Path(temporary)
    source, app = folder / "unlicensed-components", folder / "Empty.app"
    source.mkdir()
    app.mkdir()
    # This example explicitly declares both permission flags false.
    (source / "distribution.json").write_bytes((root / "Configuration/rar-distribution.example.json").read_bytes())
    refused(["python3", "Scripts/package-rar.py", "--source", str(source), "--app", str(app)], "written bundling permission and customer-supplied license policy")
    assert not list(app.iterdir()), "A refused import must not modify the app"
    contents = app / "Contents"
    contents.mkdir()
    policy = {"CFBundleIdentifier": "app.arcora.desktop", "ArcoraRARCustomerLicenseRequired": True, "ArcoraRARLocalEvaluation": False}
    info = contents / "Info.plist"
    info.write_bytes(plistlib.dumps(policy))
    for filename, data, expected in (
        ("rar", b"test binary placeholder", "RAR encoder or original package"),
        ("rarmacos-arm-723.tar.gz", b"test package placeholder", "RAR encoder or original package"),
        ("rarreg.key", b"INVALID TEST ONLY", "private RAR registration"),
        ("renamed.txt", b"RAR registration data\nINVALID TEST ONLY", "renamed private RAR key"),
    ):
        candidate = contents / filename
        candidate.write_bytes(data)
        refused(["python3", "Scripts/assert-distribution-clean.py", str(app)], expected)
        candidate.unlink()
    info.write_bytes(plistlib.dumps(dict(policy, ArcoraRARLocalEvaluation=True)))
    refused(["python3", "Scripts/assert-distribution-clean.py", str(app)], "local codec evaluation flag")
    info.write_bytes(plistlib.dumps(dict(policy, ArcoraRARCustomerLicenseRequired=False)))
    refused(["python3", "Scripts/assert-distribution-clean.py", str(app)], "customer-owned RAR license policy")
print(json.dumps({"passed": True, "checks": checks}, indent=2))
