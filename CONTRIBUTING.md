# Contributing to Arcora

Thank you for helping improve Arcora. Issues and pull requests in English, Chinese or Japanese are welcome.

## Before changing code

Check existing issues and describe the observable problem, affected format and intended behavior. Prefer fixes to shared format or safety semantics over special cases for a particular filename or sample. Keep unrelated changes separate.

For defects, provide the macOS version, architecture, app revision, engine version and minimal reproduction. Use synthetic files with no private content. Security-sensitive reports belong in the [private reporting channel](SECURITY.md), not a public issue.

## Start on another Mac

Use a Mac that supports Xcode 26 or later, select that Xcode's command-line
tools, and have Python 3 available. The built app still targets macOS 14+.
The initial dependency bootstrap needs internet access; no Homebrew packages,
private signing identity, RAR engine or registration key are needed for the
standard build and public baseline tests.

```bash
git clone https://github.com/wybaby168/Arcora.git
cd Arcora
git switch -c feature/describe-your-change
```

To review an existing pull request, check out its branch instead of starting
from `main`. Unmerged work is not included in the default clone checkout.
Share the PR URL and full commit SHA (`git rev-parse HEAD`) so collaborators
test the same revision.

All application source, translations, test fixtures, icon artwork, the native
`.icon` document and build scripts belong in Git. Generated `.build/`, `dist/`,
`.downloads/` and vendored caches do not. `Vendor/engines.lock.json` pins the
official downloads and hashes; bootstrap reconstructs the public dependencies
without copying files from another developer's machine. Do not copy `.local/`
or private RAR packages into a checkout to make the baseline build work.

## Local workflow

```bash
bash Scripts/bootstrap-engines.sh
ARCORA_REQUIRE_7ZZ=1 bash Scripts/validate.sh
ARCORA_REQUIRE_7ZZ=1 swift test -c release
bash Scripts/build-app.sh
python3 Scripts/verify-app.py dist/Arcora.app
```

The app build checks both native Finder icon resources and actual SwiftUI
brand-icon rendering from the packaged resource bundle. See the
[brand asset workflow](Documentation/BRAND_ASSETS.md) when changing artwork or
its loading code; check the installed sidebar and About page as well.

Use a focused branch and add regression coverage. Run localization checks after every UI change and update all three languages together. Keep the three README files consistent when changing user-visible capabilities or requirements.

RAR encoding tests are optional in public CI. Run them only with a lawfully obtained official engine; see [local RAR verification](Documentation/LOCAL_RAR.md). Report skipped tests honestly. Never weaken the standard app's registration gate to make tests pass.

## Remote handoff

Push the feature branch and open a pull request against `main`. Include the
exact revision, macOS/Xcode versions, architecture, test results and any
untested boundaries. Wait for the checks on that revision; a green run on an
older commit is not evidence for the new work. Keep review fixes as ordinary
commits and avoid rewriting a shared branch.

Before handing off a build or changing bootstrap/packaging, repeat the local
workflow in a fresh clone with no copied build products or dependency cache.
Keep machine-specific logs local and provide a redacted summary in the PR.
Do not upload the local RAR evaluation app as a collaboration artifact.

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
