#!/usr/bin/env python3
"""Package explicitly supplied, authorized RAR components. Never downloads RAR."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def validate(source: Path):
    source = source.resolve(strict=True)
    lock = json.loads((Path(__file__).resolve().parents[1] / "Vendor/engines.lock.json").read_text())["rar"]
    manifest = json.loads((source / "distribution.json").read_text())
    if (manifest.get("version") != lock["version"] or
            manifest.get("redistributionAuthorized") is not True or
            manifest.get("customerLicenseMode") != "customer-supplied" or
            not str(manifest.get("permissionReference", "")).strip()):
        raise ValueError("RAR distribution.json must identify written bundling permission and customer-supplied license policy; customer licenses do not grant redistribution rights.")
    permission = (source / manifest.get("permissionDocument", "")).resolve(strict=True)
    if not permission.is_file() or permission.stat().st_size == 0:
        raise ValueError("Provide the publisher's written RAR distribution permission document.")
    checked = []
    for arch in ("arm64", "x86_64"):
        folder = source / arch
        for name in ("rar", "license.txt", "rar.txt", "acknow.txt"):
            file = folder / name
            if file.is_symlink() or not file.is_file():
                raise ValueError(f"Missing regular file: {arch}/{name}")
        binary = folder / "rar"
        if hashlib.sha256(binary.read_bytes()).hexdigest() != lock[arch]["binarySha256"]:
            raise ValueError(f"Unrecognized RAR binary: {arch}. Update the reviewed lock when changing versions.")
        subprocess.run(["xcrun", "lipo", str(binary), "-verify_arch", arch], check=True)
        checked.append((arch, folder))
    return lock, checked


def package(source: Path, app: Path) -> None:
    lock, checked = validate(source)
    source, app = source.resolve(strict=True), app.resolve(strict=True)
    target = app / "Contents/Helpers/rar"
    if not (app / "Contents/Helpers").is_dir() or target.exists():
        raise ValueError("RAR packaging requires a new, staged app bundle.")
    # Copy only reviewed runtime files. Never sweep up a developer's rarreg.key,
    # personal HOME files, signing keys, or the private permission document.
    for arch, folder in checked:
        destination = target / arch
        destination.mkdir(parents=True)
        for name in ("rar", "license.txt", "rar.txt", "acknow.txt"):
            shutil.copy2(folder / name, destination / name)
        (destination / "rar").chmod(0o755)
    notices = app / "Contents/Resources/ThirdParty/RAR"
    notices.mkdir(parents=True)
    for name in ("license.txt", "rar.txt", "acknow.txt"):
        shutil.copy2(source / "arm64" / name, notices / name)
    print(f"Packaged authorized RAR {lock['version']} for arm64 and x86_64. Sign helpers before signing the app.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    try:
        if args.check_only:
            validate(args.source)
            print("RAR component manifest and binary checks passed. No customer license is bundled.")
        elif args.app is not None:
            package(args.source, args.app)
        else:
            raise ValueError("Supply --app or --check-only.")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"RAR packaging refused: {error}\n")
