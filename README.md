# Arcora

<p align="center"><img src="Sources/Arcora/Resources/Brand/ArcoraIcon.png" width="112" height="112" alt="Arcora app icon"></p>

**A native macOS archive utility. Local files, native UI, transparent format support.**

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

[![macOS validation](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml/badge.svg)](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

Arcora brings archive creation, browsing, extraction and integrity checks to a SwiftUI / AppKit application. It runs on Apple Silicon and Intel Macs and includes English, Simplified Chinese and Japanese interfaces. Archive contents stay on your Mac: no account, upload service, advertising SDK or telemetry.

> This repository contains source code and build scripts, not a notarized installer. Standard builds include their runtime dependencies, but **do not include the proprietary RAR encoder or any RAR license**. RAR extraction works immediately; RAR creation requires the optional setup below.

## Highlights

- Native archive browser with drag and drop, Finder integration, search, sorting, selected extraction and Quick Look.
- Finder right-click quick ZIP, 7z and optional RAR creation, plus a custom compression action.
- Create 7z, ZIP, TAR-based archives and single-file compressed streams; optionally create RAR5.
- Encryption and split volumes where the format supports them, including encrypted file names for 7z and RAR.
- A task queue with progress, pause, resume, cancellation and thread / memory budgets.
- Transactional output: validate in a private workspace, then publish without silently overwriting existing files.
- Universal app packaging with pinned upstream dependencies; no Homebrew installation required on the destination Mac.

## Format support

| Format | Browse / extract / test | Create | Notes |
| --- | --- | --- | --- |
| 7z | Built in | Built in | AES-256, encrypted names, split volumes |
| ZIP | Built in | Built in | AES-256 or ZipCrypto; numeric split volumes |
| RAR4 / RAR5 | Built in | Optional, RAR5 only | Official encoder + your own license in standard builds |
| TAR, TAR.GZ, TAR.BZ2, TAR.XZ | Built in | Built in | No encrypted or split creation |
| GZ, BZ2, XZ | Built in | Built in | One regular input file per compressed stream |
| Other 7-Zip formats | Read-only engine integration | Not exposed | Variant coverage is not exhaustively tested |

See the [detailed support matrix](Documentation/FORMAT_SUPPORT.md) for additional read-only formats and tested boundaries. RAR repair, recovery records, REV, SFX creation and in-place archive editing are not implemented. ZIP creation requires an ASCII password; AES passwords are limited to 99 characters. Use 7z or RAR for Unicode passwords.

## Build and run

Build requirements: a Mac that supports Xcode 26 or later, that Xcode's command-line tools selected, and Python 3. Xcode 26 is needed for the native macOS icon resources; the built app still targets macOS 14 or later. Initial dependency preparation requires internet access.

```bash
git clone https://github.com/wybaby168/Arcora.git
cd Arcora
bash Scripts/bootstrap-engines.sh
bash Scripts/build-app.sh
open dist/Arcora.app
```

The bootstrap script verifies pinned SHA-256 values for official 7-Zip 26.03, libarchive 3.8.9 and XZ 5.8.3 assets. The build script produces a universal arm64 / x86_64 app and retains the required upstream source archives and notices. Versions and hashes live in [engines.lock.json](Vendor/engines.lock.json).

Default signing is **ad-hoc**, for local development. Developer ID signing, Apple notarization and clean-machine acceptance are separate release steps; see [release instructions](Documentation/RELEASE.md). Arcora does not disable Gatekeeper or remove download quarantine to bypass macOS checks.

## Finder quick compression

Move the built app to **Applications** (the system or your user Applications folder), then open it once. Select files or folders in Finder, right-click and choose **Services → Arcora — Quick ZIP / Quick 7z / Quick RAR**.

Quick actions create an **unencrypted**, verified archive beside the selected items, keep the originals and automatically number name collisions. Multiple selections become one archive; items from different locations prompt for an output folder. Tasks appear in Arcora with progress and cancellation, and Finder reveals the result. The app can start directly from the service.

macOS may ask you to confirm **Run Service** before it hands over the files. This system safety check remains enabled.

Choose **Arcora — Custom Compression…** for a password, split volumes or other settings. Quick RAR uses the same engine and license checks as the app; if setup is incomplete, it opens the RAR form without silently changing formats.

If the actions are missing, use **Settings → General → Finder quick compression → Refresh Finder services**. Also check **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**. Menu placement and menu language are controlled by macOS; Arcora does not force-enable services you have disabled. See the [Finder guide](Documentation/FINDER_SERVICES.md).

The [Finder validation record](Documentation/FINDER_VALIDATION.md) distinguishes actual UI checks, automated coverage and remaining release gates.

## Optional RAR creation

In the standard app, open **Settings → Engines**:

1. Open the official RARLAB download link selected for your Mac's hardware.
2. Import the unchanged original `.tar.gz`. Arcora verifies its version, architecture and SHA-256, then configures it in your private application-data directory.
3. Import your own purchased `rarreg.key` and confirm that your rights cover this use. Creation is enabled only after the official engine recognizes the registration.

No manual extraction, terminal command, Homebrew or administrator installation is needed. Downloads happen in the browser at the user's request; Arcora has no runtime downloader or mirror. Licenses are stored locally, never included in the application or sent to a service. Unknown or modified packages and invalid licenses are rejected.

For a **private, local-only build with the encoder already included**, see [local RAR builds](Documentation/LOCAL_RAR.md). Its binaries, original RAR downloads and registration files must never be uploaded to this repository or attached to a release. Local use remains subject to the official evaluation limit and licensing terms.

Arcora's MIT license does not grant RAR usage or redistribution rights. The integration is not a RARLAB endorsement or a legal audit of license ownership or seat counts. Read the [RARLAB EULA](https://www.rarlab.com/license.htm), [integration policy](Documentation/RAR_DELIVERY.md) and [license-storage design](Documentation/RAR_LICENSES.md).

## Development and verification

After bootstrapping dependencies:

```bash
ARCORA_REQUIRE_7ZZ=1 bash Scripts/validate.sh
ARCORA_REQUIRE_7ZZ=1 swift test -c release
python3 Scripts/verify-app.py dist/Arcora.app
```

GitHub Actions checks the public source tree, localization, compilation, baseline tests and the actual universal app. It does not download RAR or supply a license. Tests requiring optional RAR components explicitly skip when those components are absent; a green baseline run does not prove licensed RAR creation. Private RAR test commands and current limitations are documented in the [validation report](Documentation/TEST_REPORT.md).

The CLI is available as `.build/debug/arcora-cli` during development and `dist/Arcora.app/Contents/Helpers/arcora` in the app:

```bash
.build/debug/arcora-cli engines
.build/debug/arcora-cli inspect /path/to/example.rar
.build/debug/arcora-cli extract /path/to/example.rar --to /path/to/output
.build/debug/arcora-cli create --format 7z --output /path/to/archive.7z -- /path/to/documents
```

Supply passwords through `--password-stdin`, not command-line arguments. Packaged executables ignore development engine-path overrides.

## Security and project structure

Arcora rejects unsafe paths, links and special files, applies resource limits and audits extracted output. External codecs are native child processes, **not a strong App Sandbox boundary**. Archive bugs, hostile files and resource exhaustion remain risks. This is not a full-fidelity Unix backup tool: ACLs, ownership, resource forks and all extended attributes are not guaranteed to round-trip.

| Location | Responsibility |
| --- | --- |
| `Sources/Arcora` | SwiftUI / AppKit application and translations |
| `Sources/ArcoraCore` | Archive services, scheduling primitives, safety and RAR setup |
| `Sources/CArcora`, `Sources/ArcoraWorker` | Native libarchive bridge and worker process |
| `Sources/ArcoraCLI` | Command-line interface |
| `Tests`, `Scripts` | Regression fixtures, build and verification tooling |

Read the [architecture](Documentation/ARCHITECTURE.md), [security design](Documentation/SECURITY.md) and [vulnerability reporting policy](SECURITY.md).

## Documentation and contributions

- [English quick start](Documentation/QUICKSTART.en.md) · [中文用户指南](Documentation/USER_GUIDE.md) · [日本語クイックスタート](Documentation/QUICKSTART.ja.md)
- [Contributing](CONTRIBUTING.md) · [macOS acceptance checklist](Documentation/MACOS_ACCEPTANCE.md)
- [Validation scope and outstanding release gates](Documentation/TEST_REPORT.md)

Bug reports should include the macOS version, app revision, format and a minimal non-sensitive reproduction. Never attach customer archives, passwords or registration keys. Contributions that improve shared format behavior, safety, accessibility and localization are welcome.

## License

Original Arcora code and documentation are [MIT licensed](LICENSE). Third-party engines and attributed fixtures keep their own licenses, including applicable 7-Zip / unRAR restrictions. See [third-party notices](THIRD_PARTY_NOTICES.md); the RAR encoder is proprietary and is not part of the public source distribution.
