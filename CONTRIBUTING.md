# Contributing to Arcora

Thank you for helping improve Arcora. Issues and pull requests in English, Chinese or Japanese are welcome.

## Before changing code

Check existing issues and describe the observable problem, affected format and intended behavior. Prefer fixes to shared format or safety semantics over special cases for a particular filename or sample. Keep unrelated changes separate.

For defects, provide the macOS version, architecture, app revision, engine version and minimal reproduction. Use synthetic files with no private content. Security-sensitive reports belong in the [private reporting channel](SECURITY.md), not a public issue.

## Local workflow

```bash
bash Scripts/bootstrap-engines.sh
ARCORA_REQUIRE_7ZZ=1 bash Scripts/validate.sh
ARCORA_REQUIRE_7ZZ=1 swift test -c release
bash Scripts/build-app.sh
python3 Scripts/verify-app.py dist/Arcora.app
```

Use a focused branch and add regression coverage. Run localization checks after every UI change and update all three languages together. Keep the three README files consistent when changing user-visible capabilities or requirements.

RAR encoding tests are optional in public CI. Run them only with a lawfully obtained official engine; see [local RAR verification](Documentation/LOCAL_RAR.md). Report skipped tests honestly. Never weaken the standard app's registration gate to make tests pass.

## Pull request checklist

- Describe the behavior changed and how it was verified.
- Preserve cancellation, output atomicity, path validation and secret handling.
- Do not add shell command interpolation or put passwords in process arguments.
- Do not commit build outputs, personal logs, customer files, licenses, signing credentials or original RAR downloads.
- Stage only intended files and run `python3 Scripts/check-public-tree.py --staged` before committing.
- Preserve dependency and fixture notices; new samples must have clear provenance and redistribution rights.
- Include UI verification for layout changes, and name any untested OS / architecture combinations.

Dependency updates must verify the official source, update pinned hashes, retain corresponding source and notices, and repeat relevant native and packaged-app tests. Do not switch to unverified `latest` URLs.

Contributions to original Arcora code are provided under the project's [MIT license](LICENSE). Third-party material remains under its own terms. No contributor agreement grants rights to redistribute the proprietary RAR encoder.
