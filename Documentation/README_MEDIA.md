# README interface tour

[English](../README.md) · [简体中文](../README.zh-CN.md) · [日本語](../README.ja.md)

The [animated WebP](Media/arcora-demo.webp) shows the actual Arcora 1.3.0 macOS interface, captured with synthetic files. It loops silently for 42 seconds. The same asset is shared by all three READMEs and shows only the Simplified Chinese app interface, with no added titles, captions, borders or decorative background.

The animation contains 11 losslessly encoded screen states on a transparent 1080 × 748 pixel canvas and is about 609 KiB. Native window pixels are preserved without scaling or cropping. Complete states are held for 2–5 seconds to keep native controls readable; no duplicate frames are stored during holds. Embedded EXIF, XMP and ICC metadata is omitted.

| Time | What is shown |
| --- | --- |
| 0–14 s | Workspace, archive folder browser, search, document preview and selected extraction |
| 14–28 s | ZIP creation, advanced encrypted and split 7z settings, completed compression/extraction/integrity-check tasks |
| 28–42 s | General settings and Finder service guidance, resource budgets, extraction safety limits and optional RAR configuration |

The UI is captured, not recreated. Scene timing is edited for reading and is not a benchmark. The Finder segment shows Arcora's in-app service instructions; it is not a recording of a Finder context-menu click. Only completed task results are shown; the tour does not demonstrate every queue control or every format variant.

RAR extraction is built in. RAR creation requires the official encoder and the user's own valid license. Neither the encoder nor a license key is included in the public app, demo assets or repository.

For a non-animated alternative, open the [still overview](Media/arcora-overview.png). The complete capability boundaries remain in the [format support matrix](FORMAT_SUPPORT.md).

## Updating the media

1. Run the standard build with synthetic input files and no unrelated task history visible.
2. Capture native windows for each workflow. Exclude personal paths, real documents, license keys and unrelated application windows.
3. Keep complete controls and useful text legible. Show only the captured UI, with no added presentation shell or captions; do not fabricate clicks, menus, progress or outcomes.
4. Produce an animated WebP and a still overview in `Documentation/Media/`. Keep each file below the repository's 4 MiB public-file limit, strip metadata and verify the loop, dimensions, timing and final frames.
5. Check all three README embeds and run `python3 Scripts/check-public-tree.py --staged` on the intended staged changes before pushing.

Capture scratch, local application bundles, proprietary engines, font files and render caches are not public deliverables. Keep them in the ignored local workspace, never in Git or release attachments.
