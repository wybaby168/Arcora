#!/usr/bin/env python3
"""Export source and public build dependencies; never export local RAR engines."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
folders = ("Sources", "Tests", "Scripts", "Configuration", "Documentation", "Vendor", ".github")
files = [root / name for name in ("Package.swift", "README.md", "README.zh-CN.md", "README.ja.md", "CONTRIBUTING.md", "SECURITY.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "Makefile", ".gitignore")]
for name in folders:
    files += [path for path in (root / name).rglob("*") if path.is_file()
              and "__pycache__" not in path.relative_to(root).parts
              and not path.relative_to(root).as_posix().startswith("Documentation/Validation/")]
files = sorted(files, key=lambda path: str(path.relative_to(root)))
for path in files:
    relative = path.relative_to(root)
    if (path.is_symlink() or any(part in {".local", ".build", "dist", ".downloads", "__pycache__"} for part in relative.parts)
            or path.name.lower() in {"rar", "unrar", "default.sfx", "arcora-package.json", "rarreg.key", ".rarreg.key", ".rarregkey", "arcora-acceptance.json", ".ds_store"}
            or path.name.lower().startswith("rarmacos-")
            or path.name.lower().startswith(".env")
            or path.suffix in {".p12", ".pfx", ".p8", ".cer", ".pem", ".key", ".mobileprovision", ".pyc"}):
        raise SystemExit("Refusing unreviewed/private artifact: " + str(relative))
    if not path.is_file():
        raise SystemExit("Missing source input: " + str(relative))
    with path.open("rb") as stream:
        if stream.read(128).lstrip(b'\xef\xbb\xbf').startswith(b"RAR registration data"):
            raise SystemExit("Refusing a renamed private RAR registration file: " + str(relative))
for expected in ("Vendor/7zip/7zz", "Vendor/libarchive/lib/libarchive.a", "Vendor/libarchive/lib/liblzma.a"):
    if root / expected not in files:
        raise SystemExit("Prepare public macOS dependencies first: " + expected)
manifest = "".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + str(path.relative_to(root)) + "\n" for path in files)
# Generated build manifest, not hand-maintained source.
(root / "SHA256SUMS.txt").write_text(manifest, encoding="utf-8")
files.append(root / "SHA256SUMS.txt")
output = root / "dist/Arcora-1.2.0-RAR-Customer-License-Source.zip"
output.parent.mkdir(exist_ok=True)
staged = output.with_suffix(".zip.partial")
with zipfile.ZipFile(staged, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in files:
        archive.write(path, "Arcora/" + str(path.relative_to(root)))
with zipfile.ZipFile(staged) as archive:
    if archive.testzip() is not None:
        raise SystemExit("Source ZIP failed CRC verification")
staged.replace(output)
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(".zip.sha256").write_text(checksum + "  " + output.name + "\n", encoding="utf-8")
print(str(output))
print(f"{len(files)} files; {output.stat().st_size} bytes; SHA-256 {checksum}")
