# Finder actions

Arcora provides six native macOS file services for compression and extraction. Select files or folders in Finder, then choose the relevant action from Services.

## Use

1. Move the built application into `/Applications` or your own `Applications` folder, and open it once.
2. Select one or more files or folders in Finder and right-click.
3. In **Services**, choose **Arcora — Quick ZIP**, **Quick 7z**, **Quick RAR**, **Custom Compression…**, **Extract Archive** or **Extract to Folder…**. macOS controls menu placement.

**Extract Archive** creates a new folder beside each selected archive. **Extract to Folder…** opens a destination picker. Selecting several parts of the same archive schedules one extraction. Encrypted archives may request a password through the task's Retry action.

Matching requests are coalesced while a form is open or the same request is waiting. Distinct requests retain their file selection and wait for the active form to close. A waiting count appears in the compression form.

Open an existing archive and choose **Archive → Split Archive…** to divide its original bytes into numbered parts. The default part size is 2 GiB. Creating a new compressed archive also exposes its part-size control in the main form.

Quick compression creates one unencrypted archive in the selected items' folder, verifies the archive and reveals the committed result in Finder. The Activity page provides progress and cancellation. Name collisions receive a numbered output name.

Single-file output uses the file's base name; a directory keeps its full name, including dots. Multiple sibling items use their containing folder's name. When a selected folder already contains another selected item, that item is included only once. If selections span different locations or the containing folder is not writable, a folder picker asks where to save. Cancelling that picker creates nothing. Selecting links or unsupported special files fails safely.

Use **Custom Compression…** for passwords, encrypted names, split volumes, compression tuning or a different destination. A service received while a modal form is open waits for it to close and does not replace its inputs. Services copy the selected URLs immediately, so later clipboard changes cannot change a pending job. They can launch Arcora when it is not running.

## RAR and privacy

Quick RAR observes exactly the same RAR availability and registration policy as ordinary creation. Standard builds require the user's imported official engine and valid registration; without them, Arcora opens the creation form with RAR selected and a link to engine settings. It does not silently create ZIP instead or bypass registration checks. A private local codec-evaluation build remains subject to the upstream trial and licensing terms and must not be distributed.

Quick output has **no password**. Choose custom compression before sharing sensitive material. The service sends file URLs to the local application, never uploads them, and uses the existing archive engine and safety limits. Completed tasks use Arcora's ordinary local history, which contains paths; the user can clear history in Settings.

## Missing menu items

- Keep one installed copy of the app in Applications and open it after installing an update.
- In Arcora, use **Settings → General → Finder actions → Refresh Finder services**. This calls Apple's supported `NSUpdateDynamicServices()` API.
- Check **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders** and enable the desired Arcora entries. Arcora does not override a user's disabled-service choices.
- Services menu titles follow the app-resource language chosen by macOS, not necessarily Arcora's in-app language preference. English, Simplified Chinese and Japanese menu resources are provided. Reopen the application after changing its system language.
- macOS security approval may still be required for a downloaded app. Developer ID signing and notarization remain separate release requirements; no Gatekeeper or quarantine bypass is installed.

The private RAR build and the standard build are different app identities. Private builds label their menus **Arcora Personal** (Chinese: **Arcora 个人版**, Japanese: **Arcora 個人用**) so they remain distinguishable if both variants are registered. A license-gate test build uses **Arcora RAR Test** instead. Prefer one installed variant for daily work.

## Implementation and verification

`FinderServicesProvider` snapshots the pasteboard on the main actor and queues requests until its handler is ready. The application delegate owns the model before registering the provider. File planning then runs off the main actor, and actual work enters the existing task queue. Compression accepts files and folders through `public.item`. Extraction accepts regular file selections through `public.data`.

The six fixed file actions declare `NSRestricted = false` to avoid macOS's extra restricted-service confirmation. The receiver validates local file URLs, bounds request counts and dispatches a fixed action enum. Services use a one-way protocol with no returned file contents. Output uses the archive service's resource limits, path checks and new-destination commits. [Apple's Services keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html)

```bash
python3 Scripts/check-finder-services.py
swift test --filter FinderCompressionTests
python3 Scripts/check-finder-services.py dist/Arcora.app
# With the app installed and the service enabled, invoke a real macOS service:
xcrun swift Scripts/invoke-finder-service.swift 'Arcora — Quick ZIP' --wait-for /absolute/path/to/sample.zip /absolute/path/to/sample.txt
```

Use the registered service name accepted by `NSPerformService` (the default English title on the validation Mac). A successful call confirms dispatch only: system confirmation can defer delivery. `--wait-for` retains the test pasteboard for up to 120 seconds and checks that a previously absent output appears; inspect, extract and compare that archive separately. Unit tests cover request validation, pasteboard forms, startup buffering, naming, deduplication, location selection, limits and quick presets. They do not prove Finder registration on an untested macOS release.

Apple references: [Providing a Service](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html) and [NSServices property-list keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html).
