# Finder integration validation — 1.3.0

## Update — 2026-11-13, build 11

Validated on macOS 27.0.1, Apple Silicon, with Xcode 27.0 / Swift 6.4. The standard universal app and separate local personal app built successfully; the personal app was installed locally and checked through its actual UI. The personal app is excluded from public Git and public artifacts.

- The Debug suite completed 147 tests with 10 optional RAR-encoder tests skipped and no failures. Release tests of the same archive and service implementation had the same result. Packaged standard-app checks and release-refusal checks passed.
- Six Services declarations and all three menu translations passed validation. Services now declare `NSRestricted = false`. This supersedes the restricted-service behavior recorded in the earlier baseline below.
- Two consecutive real Services calls to **Extract to Folder…**, from the same Swift test client, opened the destination picker directly without a **Run Service** confirmation. Both extractions completed; every output file matched the ZIP's contents.
- Two matching **Custom Compression…** requests submitted while its form was open produced one form and one valid archive, with no deferred second form. Distinct queued requests remain separate.
- The packaged UI opened the selected file with Space and closed it with Space; Escape also closed the preview. Search-field spaces remained ordinary text input. The preview displayed the complete expected text.
- A missing RAR5 next part produced the exact `rar5-multipart.part02.rar` filename and recovery instructions. Automated tests also cover the missing final part and the complete eight-volume set. Error details were selectable, copyable and scrollable; a long entry-information panel scrolled to its end.
- Splitting an existing ZIP through the actual UI produced three 64 KiB-or-smaller numbered parts. Rejoining them reproduced the original bytes, and opening the first part with the packaged CLI extracted the original files exactly. The updated form exposes accessible name and part-size fields, with a 2 GiB default.
- Compression duration estimates use measured progress in the current phase after work starts. They are estimates, not pre-run benchmarks for each compression level.

These checks do not replace Developer ID signing, notarization, an Intel Mac or macOS 14 acceptance checks, or validation with a customer's own RAR license. See the repository's CI for the exact published revision.

## Earlier baseline — 2026-09-08

Date: 2026-09-08. Environment: macOS 26.6.2, Apple Silicon, Xcode 26.4.1 / Swift 6.3.1. This is local validation, not Developer ID signing, notarization or clean-machine acceptance.

## Automated results

| Check | Result |
| --- | --- |
| Full Debug suite, official local RAR and package required | 127 passed, 0 failed, 0 skipped |
| Full Release suite, same optional components required | 127 passed, 0 failed, 0 skipped |
| New Finder-specific unit tests | 15 passed, included in the totals above |
| UI localization | 248 matching keys in English, Simplified Chinese and Japanese |
| Services metadata and menu localization | Four distinct actions, file/folder input, correct service ports, three complete menu translations |
| Universal app | arm64 and x86_64 built and ad-hoc signature verified |
| Actual packaged private app | arm64 and Rosetta x86_64 RAR encrypted/multivolume round trips passed |
| Actual packaged standard app | Original-package import and missing/invalid-license refusal passed; RAR extraction remained available |
| Public distribution audit | Standard app has no RAR encoder, original RAR download, registration file or evaluation bypass |

The full suites used privately obtained official RAR engines and original packages. Public CI must continue to skip optional tests when these are absent. These results are local evidence; inspect GitHub CI for the exact revision under review rather than relying on an older commit's green run.

## Interactive checks

- Finder's real file and folder context menus expose Quick ZIP, Quick 7z, Quick RAR and Custom Compression. Standard and private variants have distinguishable titles.
- Clicking the actual Finder Quick ZIP action created a valid archive. macOS presented its **Run Service** confirmation; the check was retained, not suppressed.
- Real macOS Services dispatch created ZIP from a Chinese-named file, 7z from two Chinese/Japanese-named files, and RAR from a folder whose name contains a dot. Packaged extraction reproduced the exact files, not just their names or sizes.
- Repeated output names generated numbered alternatives. The first ZIP's SHA-256 and all original file hashes remained unchanged.
- A RAR service launched the app from a stopped state. Closing the main window did not prevent a later service from showing its task.
- Custom Compression preserved the selected directory and its full name. Another quick request received while this form was open waited; closing the form allowed the queued request to complete without changing the form's inputs or creating the cancelled custom archive.
- Repeated requests initially exposed a duplicate-window issue. The final implementation uses a value-targeted SwiftUI window group. Three consecutive ZIP/7z/RAR requests on the final candidate completed with one main window listed in the Window menu.
- Settings → General displayed the Finder instructions and its refresh action returned the expected feedback.
- The standard app's actual Finder Quick RAR action selected RAR in the form, showed setup guidance and kept Start Compression disabled without the required setup. Cancelling created no RAR file and did not silently select another format.

Local logs and synthetic output fixtures are retained under the ignored `.local/finder-validation/` directory. RAR binaries, original downloads, personal app bundles and logs are not part of the public repository.

## Remaining boundaries

- Finder UI was tested in a Chinese macOS session. English/Japanese menu resources are structurally checked, not each tested in a separate OS-language session.
- No separate physical Intel Mac or macOS 14 clean machine was used. Rosetta tests do not replace those acceptance checks.
- Cross-directory destination selection, invalid URL/path handling, link refusal, parent/child deduplication and resource presets have automated planning coverage. There is no claim of a complete Finder/TCC matrix for external disks, network volumes or protected folders.
- No purchased registration key was supplied. Tests establish the unlicensed gate and the separate local vendor-evaluation path, not real customer license ownership or seat compliance.
- Public signing, notarization and customer clean-machine acceptance remain outstanding. Personal RAR builds are excluded from the repository and public CI artifacts; CI app artifacts are standard, ad-hoc-signed test builds, not public releases.

See [Finder usage and design](FINDER_SERVICES.md), [baseline archive validation](TEST_REPORT.md) and the [release acceptance checklist](MACOS_ACCEPTANCE.md).
