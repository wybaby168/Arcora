# Validation report · Arcora 1.2.0

This is a scoped engineering report, not a release certification or legal opinion. Machine-specific logs, application packages and RAR registration material are kept outside public Git. The public repository contains reproducible test commands and attributed fixtures.

## Local verification · 2026-09-08

Environment: Apple Silicon, macOS 26.6.2, Xcode 26.4.1, Swift 6.3.1 in Swift 5 compatibility mode. Dependencies: 7-Zip 26.03, libarchive 3.8.9, liblzma 5.8.3 and privately obtained official RAR 7.23.

| Check | Observed result | Boundary |
| --- | --- | --- |
| Debug regression suite | 112 tests passed; zero failures or skips | Optional official RAR engine and original packages were supplied privately |
| Release regression suite | 112 tests passed; zero failures or skips | Same private test configuration |
| Localization | 239 keys × English / Chinese / Japanese passed | Static completeness, not visual review of every translated window |
| Universal app | arm64 / x86_64 build and strict nested ad-hoc signature verification passed | Not Developer ID signed or notarized |
| Private bundled-RAR app | ARM and Rosetta packaged CLI passed encrypted-name, Unicode-password, multipart RAR5 exact-content round trips | Evaluation engine; no purchased key supplied |
| Standard app | Official original import, missing / invalid license lock and RAR4 / RAR5 extraction passed | Real registered-license positive path remains unverified |
| Release boundaries | 10 negative release checks passed | Rejects prohibited default bundling, private keys, original packages and local evaluation flags |

Rosetta results are x86_64 execution on an Apple Silicon Mac, not acceptance on a separate Intel machine. A real purchased license was not provided and no activation was fabricated.

## Regression coverage

- 7z, ZIP, TAR combinations and single-file compressed streams: native processing, engine integration and exact-content round trips.
- RAR4 / RAR5 attributed read fixtures; RAR5 creation with solid compression, compression levels, Unicode paths and passwords, encrypted names, directories and split volumes.
- Intermediate volumes, missing parts, damaged archives, cancellation, changing input and transactional output publication.
- RAR original-package selection by actual hardware, including Rosetta; fixed metadata, hashes, architecture, size and entry limits; link rejection; atomic replacement; retained original content and quarantine; tamper detection before use.
- License import acknowledgment, private file permissions, failed replacement preservation, registration response parsing, invalid official-engine registration rejection and isolated subprocess configuration.
- Local evaluation passes the private license configuration to actual creation without removing the standard app's license requirement. Positive store-transaction tests use an internal mock and explicitly invalid artificial data; they do not establish real license activation.

The standard GUI was previously checked for successful original-package import, correct no-license locking and the first-selection license sheet. The rights checkbox starts unchecked and submission disabled; no rights declaration was accepted on behalf of a user. That UI evidence does not establish a licensed positive path.

## Reproduce the public baseline

```bash
bash Scripts/bootstrap-engines.sh
ARCORA_REQUIRE_7ZZ=1 bash Scripts/validate.sh
ARCORA_REQUIRE_7ZZ=1 swift test -c release
bash Scripts/build-app.sh
python3 Scripts/assert-distribution-clean.py dist/Arcora.app
python3 Scripts/verify-release-gates.py
python3 Scripts/verify-app.py dist/Arcora.app
```

GitHub Actions runs the public baseline without downloading proprietary RAR software or providing a key. Optional RAR-dependent tests explicitly skip when unavailable. Consult the [workflow run for the exact revision](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml), not this report, for current CI status. A successful baseline is not a claim that every one of the 112 tests ran without optional dependencies.

Before committing, run `python3 Scripts/check-public-tree.py --staged`. It inspects exact index blobs, rejects prohibited generated / private paths and common credential patterns, and verifies local Markdown links and all three README entry points. It is a bounded guard, not a complete secret-discovery system.

## Private RAR verification

Follow [LOCAL_RAR.md](LOCAL_RAR.md) for full codec tests and a private local bundled app. To test the standard app's customer setup without a real license:

```bash
python3 Scripts/verify-app.py dist/Arcora.app --require-rar \
  --rar-package /private/path/to/rarmacos-arm-723.tar.gz --expect-license-required
```

Use the corresponding x64 original on Intel. The verifier uses isolated temporary engine and license directories, so it does not replace a customer's profile. For the licensed positive path, use `--license-file` with a genuine license that covers the test machine; keep all inputs and resulting logs private.

## Outstanding release gates

- A genuine purchased-key import → registered status → standard-app RAR creation positive acceptance test.
- Developer ID signing, Apple notarization and download / Gatekeeper acceptance. The current app does not remove quarantine or disable security controls.
- A separate Intel Mac, the minimum macOS 14 environment and clean-machine browser-download setup.
- Broader multilingual visual, large-file, network-volume, disk-full and resource-pressure acceptance from the [macOS checklist](MACOS_ACCEPTANCE.md).
- RAR repair, recovery records, REV, SFX creation, archive-internal editing and full Unix backup semantics are outside the implemented feature set.

Public source publication is separate from distributing a customer-ready installer. Read the [RAR integration policy](RAR_DELIVERY.md), [release process](RELEASE.md) and [security design](SECURITY.md) before shipping an application.
