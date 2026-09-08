#!/usr/bin/env python3
"""Exercise the actual packaged app from an unrelated directory, without PATH engines."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("--require-rar", action="store_true")
parser.add_argument("--arch", choices=("arm64", "x86_64"))
parser.add_argument("--expect-license-required", action="store_true")
parser.add_argument("--license-file", type=Path, help="Private publisher test key, copied only into a temporary profile and never into the app")
parser.add_argument("--rar-package", type=Path, help="User-downloaded original .tar.gz; imported only into a temporary profile, never bundled")
args = parser.parse_args()
if args.expect_license_required and args.license_file:
    parser.error("Choose either an unlicensed gate test or a private licensed roundtrip.")
app = args.app.resolve(strict=True)
fixtures = Path(__file__).resolve().parents[1] / "Tests/ArcoraCoreTests/Fixtures"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
cli = app / "Contents/Helpers/arcora"
report = {"app": str(app), "architecture": args.arch or "native", "checks": []}
with tempfile.TemporaryDirectory(prefix="Arcora-bundle-test-") as scratch:
    root = Path(scratch)
    env = dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin", ARCORA_7ZZ="/missing/7zz", ARCORA_RAR="/missing/rar")
    prefix = (["/usr/bin/arch", "-" + args.arch] if args.arch else []) + [str(cli)]
    profile = root / "private-license-profile"
    engine_profile = root / "private-engine-profile"

    def raw(*argv, password=None):
        return subprocess.run(prefix + [argv[0], "--rar-license-directory", str(profile), "--rar-engine-directory", str(engine_profile)] + list(argv[1:]), cwd=root, env=env, text=True,
                                   input=None if password is None else password + "\n",
                                   capture_output=True, timeout=60)
    def run(*argv, password=None):
        completed = raw(*argv, password=password)
        if completed.returncode:
            raise RuntimeError(f"Packaged command {argv[0]} failed: {completed.stderr[-4096:]}")
        return json.loads(completed.stdout)

    engines = run("engines")
    assert run("engines", "--rar", "/bin/echo")["RAR"] == engines["RAR"], "Packaged CLI must ignore unvalidated executable overrides"
    if args.rar_package:
        assert engines["RARMode"] == "unavailable", "Customer app must not include a RAR encoder"
        package = args.rar_package.resolve(strict=True)
        before = hashlib.sha256(package.read_bytes()).hexdigest()
        metadata = run("rar-package-info")
        assert before == metadata["sha256"], "Use the original package matching this Mac's hardware (including under Rosetta)"
        assert metadata["downloadURL"].startswith("https://www.rarlab.com/rar/")
        imported = run("rar-package-import", str(package))
        assert imported == {"state": "imported", "licenseIncluded": False, "originalFileUntouched": True}
        assert hashlib.sha256(package.read_bytes()).hexdigest() == before
        engines = run("engines")
        assert engines["RARMode"] == "user-imported-original"
        assert Path(engines["RAR"]).is_relative_to(engine_profile)
        for name in (metadata["filename"], "rar/license.txt", "rar/order.htm", "rar/rar.txt", "rar/acknow.txt"):
            assert (engine_profile / "current" / name).is_file()
        bad = root / "modified.tar.gz"
        bad.write_bytes(package.read_bytes()[:100])
        assert raw("rar-package-import", str(bad)).returncode != 0
        assert run("engines")["RARMode"] == "user-imported-original"
        report["package"] = metadata
        report["checks"].append("architecture-aware official metadata; local original-package import; unchanged source and full upstream documentation; damaged replacement refused")
    for key in ("7zz", "worker"):
        if not Path(engines[key]).is_relative_to(app):
            raise RuntimeError(f"Packaged {key} escaped the app: {engines[key]}")
    report["engines"] = engines
    report["checks"].append("bundled helpers found without developer cwd; packaged environment and explicit RAR executable overrides ignored")
    archive = fixtures / "rar4-solid-encrypted.rar"
    manifest = run("inspect", str(archive), "--password-stdin", password="password")
    if len(manifest["entries"]) != 4:
        raise RuntimeError("Incomplete RAR4 listing")
    run("test", str(archive), "--password-stdin", password="password")
    output = run("extract", str(archive), "--to", str(root), "--name", "restored", "--password-stdin", password="password")
    for name in ("a.txt", "b.txt", "c.txt", "d.txt"):
        assert (Path(output["outputs"][0]) / name).read_text() == "This is from " + name
    report["checks"].append("RAR4 encrypted solid listing, test and exact-content extraction")
    for name in ("rar5-stored.rar", "rar5-compressed.rar"):
        run("test", str(fixtures / name))
        run("extract", str(fixtures / name), "--to", str(root), "--name", name + "-out")
    report["checks"].append("RAR5 stored and compressed extraction")
    if args.require_rar and engines.get("RARMode") not in ("bundled", "user-imported-original"):
        raise RuntimeError("RAR creation must use a validated managed import or the separate local codec-test bundle")
    if engines.get("RARMode") in ("bundled", "user-imported-original"):
        if engines["RARMode"] == "bundled" and not Path(engines["RAR"]).is_relative_to(app):
            raise RuntimeError("RAR encoder escaped the app")
        if engines.get("RARLicensePolicy") == "customer-supplied-required":
            assert run("rar-license-status")["state"] == "missing"
            blocked_source = root / "blocked-input.txt"
            blocked_source.write_text("No-license gate test")
            blocked = raw("create", "--format", "rar", "--output", str(root / "blocked.rar"), "--", str(blocked_source))
            assert blocked.returncode != 0 and "RAR creation is locked" in blocked.stderr
            assert not (root / "blocked.rar").exists()
            invalid_key = root / "invalid-license-test.txt"
            invalid_key.write_text("RAR registration data\nArcora Invalid Test\nNOT A LICENSE\nUID=INVALID\nINVALID\n")
            rejected = raw("rar-license-import", str(invalid_key), "--acknowledge-rar-license")
            assert rejected.returncode != 0 and run("rar-license-status")["state"] == "missing"
            assert not (profile / "config/rar/rarreg.key").exists()
            report["checks"].append("missing and invalid customer licenses keep RAR creation locked; RAR extraction remains available")
            if args.license_file:
                run("rar-license-import", str(args.license_file.resolve(strict=True)), "--acknowledge-rar-license")
                assert run("rar-license-status")["state"] == "verified"
                report["checks"].append("customer-supplied private test license confirmed by official RAR in temporary profile")
            elif not args.expect_license_required:
                raise RuntimeError("Use --expect-license-required for gate testing, or supply your own --license-file for a licensed roundtrip")
        elif args.expect_license_required:
            raise RuntimeError("Customer test cannot use a codec-evaluation bypass")
        if args.expect_license_required:
            report["rarCreation"] = "correctly locked until a customer license is imported"
            report["passed"] = True
            print(json.dumps(report, ensure_ascii=False, indent=2))
            raise SystemExit(0)
        source = root / "资料 日本語"
        source.mkdir()
        (source / "中文🔐.txt").write_text("Arcora RAR Unicode content", encoding="utf-8")
        (source / "empty").mkdir()
        (source / "data.bin").write_bytes(bytes(range(256)) * 800)
        password = "密码_日本語_🔐"
        result = run("create", "--format", "rar", "--output", str(root / "output.rar"),
                     "--threads", "2", "--dictionary", "4", "--level", "0", "--volume", "64 KiB",
                     "--password-stdin", "--", str(source), password=password)
        parts = sorted(Path(result["outputs"][0]).glob("*.rar"))
        assert len(parts) > 2
        restored = run("extract", str(parts[1]), "--to", str(root), "--name", "roundtrip",
                       "--password-stdin", password=password)
        actual = Path(restored["outputs"][0]) / source.name
        assert (actual / "中文🔐.txt").read_bytes() == (source / "中文🔐.txt").read_bytes()
        assert (actual / "data.bin").read_bytes() == (source / "data.bin").read_bytes()
        assert (actual / "empty").is_dir()
        report["checks"].append("RAR creation with encrypted names, Unicode password and multipart exact-content roundtrip")
    else:
        if args.expect_license_required:
            raise RuntimeError("Import an original RAR package with --rar-package to test the customer license gate")
        report["rarCreation"] = "requires user import of official original package and customer license"
report["passed"] = True
print(json.dumps(report, ensure_ascii=False, indent=2))
