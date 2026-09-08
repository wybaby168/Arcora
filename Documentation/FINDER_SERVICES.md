# Finder quick compression

Arcora 1.3 adds four native macOS file services. They work with files and folders selected in Finder; no Finder Sync extension, administrator helper or shell plug-in is installed.

## Use

1. Move the built application into `/Applications` or your own `Applications` folder, and open it once.
2. Select one or more files or folders in Finder and right-click.
3. In **Services**, choose **Arcora — Quick ZIP**, **Quick 7z**, **Quick RAR** or **Custom Compression…**. macOS controls whether eligible services appear in a submenu or elsewhere in the context menu.

Quick compression needs no settings sheet in the ordinary case. macOS can show a **Run Service** confirmation before handing over selected files; approve it to continue. Arcora retains this protection and does not bypass it. It produces one unencrypted archive in the selected items' folder, keeps the originals, verifies the archive and reveals the committed result in Finder. The Activity page provides progress and cancellation. Existing output is never overwritten: name collisions receive a numbered alternative.

Single-file output uses the file's base name; a directory keeps its full name, including dots. Multiple sibling items use their containing folder's name. When a selected folder already contains another selected item, that item is included only once. If selections span different locations or the containing folder is not writable, a folder picker asks where to save. Cancelling that picker creates nothing. Selecting links or unsupported special files fails safely.

Use **Custom Compression…** for passwords, encrypted names, split volumes, compression tuning or a different destination. A service received while a modal form is open waits for it to close and does not replace its inputs. Services copy the selected URLs immediately, so later clipboard changes cannot change a pending job. They can launch Arcora when it is not running.

## RAR and privacy

Quick RAR observes exactly the same RAR availability and registration policy as ordinary creation. Standard builds require the user's imported official engine and valid registration; without them, Arcora opens the creation form with RAR selected and a link to engine settings. It does not silently create ZIP instead or bypass registration checks. A private local codec-evaluation build remains subject to the upstream trial and licensing terms and must not be distributed.

Quick output has **no password**. Choose custom compression before sharing sensitive material. The service sends file URLs to the local application, never uploads them, and uses the existing archive engine and safety limits. Completed tasks use Arcora's ordinary local history, which contains paths; the user can clear history in Settings.

## Missing menu items

- Keep one installed copy of the app in Applications and open it after installing an update.
- In Arcora, use **Settings → General → Finder quick compression → Refresh Finder services**. This calls Apple's supported `NSUpdateDynamicServices()` API.
- Check **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders** and enable the desired Arcora entries. Arcora does not override a user's disabled-service choices.
- Services menu titles follow the app-resource language chosen by macOS, not necessarily Arcora's in-app language preference. English, Simplified Chinese and Japanese menu resources are provided. Reopen the application after changing its system language.
- macOS security approval may still be required for a downloaded app. Developer ID signing and notarization remain separate release requirements; no Gatekeeper or quarantine bypass is installed.

The private RAR build and the standard build are different app identities. Private builds label their menus **Arcora Personal** (Chinese: **Arcora 个人版**, Japanese: **Arcora 個人用**) so they remain distinguishable if both variants are registered. A license-gate test build uses **Arcora RAR Test** instead. Prefer one installed variant for daily work.

## Implementation and verification

`FinderServicesProvider` snapshots the pasteboard on the main actor and queues requests until its handler is ready. The application delegate owns the model before registering the provider. File planning then runs off the main actor, and actual work enters the existing task queue. Each service declares `public.item` file input, an explicit context and `NSRestricted` so it is not available as an arbitrary-file-processing escape from another app's sandbox.

```bash
python3 Scripts/check-finder-services.py
swift test --filter FinderCompressionTests
python3 Scripts/check-finder-services.py dist/Arcora.app
# With the app installed and the service enabled, invoke a real macOS service:
xcrun swift Scripts/invoke-finder-service.swift 'Arcora — Quick ZIP' --wait-for /absolute/path/to/sample.zip /absolute/path/to/sample.txt
```

Use the registered service name accepted by `NSPerformService` (the default English title on the validation Mac). A successful call confirms dispatch only: system confirmation can defer delivery. `--wait-for` retains the test pasteboard for up to 120 seconds and checks that a previously absent output appears; inspect, extract and compare that archive separately. Unit tests cover request validation, pasteboard forms, startup buffering, naming, deduplication, location selection, limits and quick presets. They do not prove Finder registration on an untested macOS release.

Apple references: [Providing a Service](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html) and [NSServices property-list keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html).
