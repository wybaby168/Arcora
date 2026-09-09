# Single-workspace window regression

Verified locally on 2026-09-09, macOS 26.6.2 / Apple Silicon, Arcora 1.3.0 build 8.

## Cause and ownership

Arcora has one application-wide archive model, task queue and set of presentation
flags. The previous `WindowGroup` allowed external file-open events to create
additional root views for that same model. Each root view attached an extraction
sheet to `showExtraction`, so a single action could present sheets in two windows.
The affected app had both `main-AppWindow-1` and `main-AppWindow-2`; cancelling a
sheet could switch focus between those windows.

The primary scene is now a unique SwiftUI `Window`. Finder file-open events are
handled once by `AppDelegate.application(_:open:)`, not by each root view.
Reopening raises or restores the same `main` window. Closing the window does not
terminate the process or its background jobs. Extraction submission also consumes
its presentation state before enqueueing, preventing repeated activation of one
sheet from scheduling another task.

This follows Apple's [single-window scene contract](https://developer.apple.com/documentation/swiftui/window).
Independent simultaneous archive workspaces would require independent model and
sheet ownership; adding a `WindowGroup` around the shared model is not sufficient.

## Native UI checks

These are actual local accessibility/UI observations, not automated XCTest UI
coverage and not evidence of behavior on every supported macOS version.

| Scenario | Observed result |
| --- | --- |
| Launch the updated app after quitting the affected build | One root window with identifier `main`; no duplicate restored workspace |
| Open a RAR, show extraction, then cancel | One sheet; one cancellation returns to the same `main` window |
| Open an archive through Finder's Open With action while the app is running | Reuses the workspace |
| Close the archive and main window, then open a different RAR through Finder | Process stays running; the workspace reopens and displays the new archive |
| Rapidly double-click the extraction submit button | Exactly one successful extraction job and one output directory; extracted bytes match the fixture |
| Quit the process completely, then use Finder to open a ZIP | A new process loads the ZIP and uses the same unique `main` window |

The extraction case used the repository's `rar5-stored.rar` fixture under a fresh
local test name. The cold-start case used `normal.zip`. System-wide file
associations, Finder/Dock caches and security settings were not changed.

## Build and engine regression

- `Scripts/validate.sh`: 127 tests discovered, 117 passed, 10 optional RAR tests
  skipped when their explicit encoder override was not provided; no failures.
- Release tests with an explicitly supplied local official RAR encoder:
  127 passed, no skips or failures. This exercises the codec, not ownership or
  seat coverage of a customer's RAR license.
- Universal arm64 / x86_64 app build, icon/resource verification and strict
  ad-hoc signature verification passed.
- `Scripts/verify-app.py` passed for the standard app, including packaged
  RAR4/RAR5 extraction outside the developer working directory.

The local personal build retains its existing RAR configuration and remains
non-distributable. This bug fix does not change the standard edition's RAR
licensing or distribution boundaries.
