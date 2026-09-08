#!/usr/bin/env python3
"""Audit public Git inputs, never the ignored local RAR or delivery directories.

--staged reads index blobs, not working-tree replacements. This is a bounded
publication guard, not a general-purpose secret scanner or legal assessment.
"""
import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
READMES = ("README.md", "README.zh-CN.md", "README.ja.md")
PRIVATE_PARTS = {
    ".local", ".build", ".downloads", "dist", ".swiftpm", "__pycache__",
    "xcuserdata", "node_modules",
}
PRIVATE_NAMES = {
    "rar", "unrar", "default.sfx", "rarreg.key", ".rarreg.key", ".rarregkey",
    "arcora-acceptance.json", "arcora-package.json", "delivery.json",
    "sha256sums.txt", ".ds_store",
}
PRIVATE_SUFFIXES = {".key", ".pem", ".p12", ".pfx", ".p8", ".cer", ".mobileprovision", ".pyc"}
ARCHIVE_SUFFIXES = (".zip", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".7z", ".rar", ".dmg")
EXECUTABLE_MAGIC = {
    b"\x7fELF", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
}
SECRET_PATTERNS = (
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    re.compile(rb"\bsk_live_[A-Za-z0-9]{20,}\b"),
)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def path_problem(name):
    path = PurePosixPath(name)
    lower = name.lower()
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        return "unsafe repository path"
    if any(part.lower() in PRIVATE_PARTS or part.lower().endswith(".app") for part in path.parts):
        return "private or generated directory"
    if lower.startswith("documentation/validation/"):
        return "private validation log"
    if lower.startswith("vendor/") and name != "Vendor/engines.lock.json":
        return "vendored artifact (only the lock file belongs in public Git)"
    if path.name.lower() in PRIVATE_NAMES or path.suffix.lower() in PRIVATE_SUFFIXES:
        return "private component or credential filename"
    if path.name.lower().startswith("rarmacos-"):
        return "original proprietary RAR package"
    if path.name.lower().startswith(".env") and path.name != ".env.example":
        return "local environment file"
    if lower.endswith(ARCHIVE_SUFFIXES) and not name.startswith("Tests/ArcoraCoreTests/Fixtures/"):
        return "unreviewed archive outside attributed test fixtures"
    return None


def content_problem(data):
    if len(data) > 4 * 1024 * 1024:
        return "unexpectedly large public source file"
    if data[:4] in EXECUTABLE_MAGIC:
        return "compiled executable, including possible renamed engine"
    if data.lstrip(b"\xef\xbb\xbf \t\r\n").startswith(b"RAR registration data"):
        return "renamed RAR registration file"
    if any(pattern.search(data) for pattern in SECRET_PATTERNS):
        return "credential-like content"
    if re.search(rb"/Users/[A-Za-z0-9._-]+/|/private/tmp/arcora-[A-Za-z0-9._-]+/", data):
        return "machine-specific path in public source"
    return None


def read_inputs(staged):
    top = Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve()
    if top != ROOT:
        raise SystemExit("Run this audit in Arcora's own Git repository, not a parent repository.")
    entries = {}
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, filename = record.split(b"\t", 1)
        mode, oid, stage = metadata.decode().split()
        if stage != "0":
            raise SystemExit("Resolve merge conflicts before auditing public source.")
        entries[filename.decode()] = (mode, oid)
    if not staged:
        for filename in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
            if filename:
                entries[filename.decode()] = ("100644", None)
    if not entries:
        raise SystemExit("No public files to audit; stage the intended source first.")
    files, failures = {}, []
    for name, (mode, oid) in sorted(entries.items()):
        problem = path_problem(name)
        path = ROOT / name
        if problem or mode not in {"100644", "100755"} or (not staged and path.is_symlink()):
            failures.append((name, problem or "symlink or unsupported Git file mode"))
            continue
        if staged:
            data = git("cat-file", "blob", oid)
        elif not path.is_file():
            failures.append((name, "missing tracked file; stage the deletion or restore it"))
            continue
        else:
            data = path.read_bytes()
        problem = content_problem(data)
        if problem:
            failures.append((name, problem))
        files[name] = data
    return files, failures


def check_links(files, failures):
    for name in READMES:
        if name not in files:
            failures.append((name, "required README translation is missing"))
        else:
            for language in READMES:
                if ("(" + language + ")").encode() not in files[name]:
                    failures.append((name, "missing language switch: " + language))
    for name, data in files.items():
        if not name.endswith(".md"):
            continue
        # Markdown links only; do not interpret paths in examples or code as links.
        for match in re.finditer(r"\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", data.decode("utf-8")):
            target = unquote(match.group(1).strip("<>"))
            if urlsplit(target).scheme or target.startswith(("#", "//")):
                continue
            target = target.split("#", 1)[0].split("?", 1)[0]
            resolved = (ROOT / name).parent.joinpath(target).resolve()
            try:
                relative = resolved.relative_to(ROOT).as_posix()
            except ValueError:
                failures.append((name, "local link escapes repository"))
                continue
            if relative not in files and not any(item.startswith(relative + "/") for item in files):
                failures.append((name, "local link is not in public tree: " + target))


def self_test():
    for name in (".local/keep.txt", "dist/App.zip", "Documentation/Validation/run.txt",
                 "Vendor/7zip/7zz", "renamed.key", "rarmacos-arm-723.tar.gz", "Secret.app/Info.plist"):
        assert path_problem(name), name
    for name in ("README.ja.md", "Vendor/engines.lock.json", "Tests/ArcoraCoreTests/Fixtures/rar5-stored.rar"):
        assert path_problem(name) is None, name
    assert content_problem(b"RAR registration " + b"data\nINVALID TEST ONLY")
    assert content_problem(b"\xef\xbb\xbf RAR registration " + b"data\nINVALID TEST ONLY")
    assert content_problem(bytes.fromhex("cffaedfe") + b"placeholder")
    assert content_problem(b"ghp" + b"_" + b"A" * 36)
    assert content_problem(b"normal source text") is None
    files = {name: b"[EN](README.md) [ZH](README.zh-CN.md) [JA](README.ja.md)" for name in READMES}
    failures = []
    check_links(files, failures)
    assert not failures, failures
    files["README.md"] += b" [private](.local/missing.txt)"
    check_links(files, failures)
    assert failures
    print("PASS: public-tree audit self-tests")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="inspect exact staged blobs before committing")
    parser.add_argument("--self-test", action="store_true", help="run bounded guard regression checks")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    files, failures = read_inputs(args.staged)
    check_links(files, failures)
    if failures:
        for name, reason in failures:
            # Report filenames and categories only, never potentially secret content.
            print("FAIL: " + name + ": " + reason)
        raise SystemExit(1)
    print(f"PASS: {len(files)} public files; no prohibited artifacts detected; local Markdown links and 3 READMEs checked")


if __name__ == "__main__":
    main()
