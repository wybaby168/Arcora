# Arcora app icon

The app icon pairs a blue rounded-square tile with a white archive case,
documents, and a zipper. The high-contrast silhouette stays recognizable in
Finder and at compact sidebar sizes. Action icons remain native SF Symbols;
the app identity is shared by the application bundle, sidebar, About page,
and the English, Chinese, and Japanese READMEs.

## Source and packaging

- Artwork: [ArcoraIcon.png](../Sources/Arcora/Resources/Brand/ArcoraIcon.png),
  1254 × 1254 PNG with transparency. The original pixels are unchanged.
- Master SHA-256:
  `6dec252b6f7f336cb223901d829342779b0314bc2398bd857f55c6606d6d9eed`.
- Native document: [Arcora.icon](../Configuration/Arcora.icon), editable in
  Apple's Icon Composer. It includes a byte-identical copy of the artwork.
- The existing padded artwork is placed at its native point size, centered on
  the 1024 pt system canvas. This gives it full coverage inside the system's
  mask. Do not first normalize the padded image down to 1024 pt: that would
  reintroduce the small inner tile. Raster-layer glass is disabled because the
  artwork already contains its own shading.
- [make-icon.swift](../Scripts/make-icon.swift) uses Xcode 26+ `actool` to
  compile **both** `Assets.car` and `Arcora.icns`. The catalog contains native
  Default, Dark, and Mono icon stacks and a legacy multi-size fallback.
  No artwork is redrawn or downloaded during a build.
- `CFBundleIconName=Arcora` selects the compiled native icon. The matching
  `CFBundleIconFile=Arcora` retains the legacy fallback. The catalog deployment
  target remains macOS 14.0, with both arm64 and x86_64 app binaries.
- `--standalone-icon-behavior all` produces the complete ICNS: 16, 32, 128,
  256, and 512 pt representations at 1× and 2×, covering 16–1024 physical pixels.
- [BrandIcon.swift](../Sources/Arcora/BrandIcon.swift) loads the same master
  through the app's SwiftPM resource bundle, resolving the explicit PNG URL
  and decoding it with `NSImage(contentsOf:)`. The decoded image is cached and
  passed to SwiftUI as `Image(nsImage:)`. Do not replace this with named-image
  lookup: the packaged loose resource rendered blank through that path on
  macOS 26.6.2. A native archive symbol is used if the file cannot be decoded.

Build and inspect the packaged icon on macOS:

```sh
bash Scripts/build-app.sh
xcrun swift Scripts/verify-icon.swift dist/Arcora.app/Contents/Resources/Arcora.icns
python3 Scripts/check-icon-assets.py dist/Arcora.app
bash Scripts/verify-brand-icon.sh dist/Arcora.app
```

[verify-icon.swift](../Scripts/verify-icon.swift) decodes the delivered ICNS
and checks every expected representation, pixel dimensions, nonempty artwork,
and transparent outer padding of the legacy fallback.
[check-icon-assets.py](../Scripts/check-icon-assets.py) also checks the shared
artwork, native canvas layout, Info.plist wiring, compiled appearance stacks,
and deployment target. Both the app build and macOS CI run these checks.

[verify-brand-icon.sh](../Scripts/verify-brand-icon.sh) compiles the production
`BrandIcon` view with a resource-bundle provider pointing at the packaged app.
It renders the sidebar (44 pt) and About (88 pt) marks at 1×/2× in light/dark
mode and compares their pixels with an explicitly decoded PNG reference.
A separate process verifies the missing-image fallback. This supplements,
but does not replace, inspection of the installed application's two screens.
Build 7 adds this check and fixes the in-app loading regression; the native
Finder/Dock resource format introduced in build 6 remains unchanged.

Build 5 supplied only a padded ICNS. On macOS Tahoe, Finder placed that image
inside another system plate, producing a smaller blue icon on a gray rounded
background. Build 6 fixes the resource format and layout; it does not attempt
to repair this by clearing system caches or overriding the icon in Finder.
Ship the full app bundle, not a loose ICNS, to retain native rendering.

For a new design, update both artwork copies and the hash here, adjust the
Icon Composer layout, rebuild, and inspect the actual 16/32 px representations
and Finder preview. The automated checks supplement visual inspection; they
do not evaluate design quality or establish compatibility with an untested OS.

Apple's [Icon Composer workflow](https://developer.apple.com/videos/play/wwdc2025/361/)
describes system-applied masks and native icon delivery. The
[bundle icon keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)
define the catalog name and legacy file fallback.

## Generation provenance

The selected master was generated on 2026-09-08 using the **built-in image
generation tool** through the `imagegen` skill, not the fallback CLI. It is a
standalone generation, not a derivative of the discarded white-tile studies.
The generated alpha channel is preserved. Build 6 reuses that image without
regeneration and composes it through Apple's native icon resource format.

Final generation prompt:

> Use case: logo-brand. Create ONE finished production macOS application icon
> for Arcora, a professional archive and file-compression utility. A clean,
> saturated indigo-blue rounded-square tile, with generous even transparent
> padding. On the tile, a bold simple porcelain-white archive box with a small
> centered blue zipper and two compressed white document layers. Refined
> geometric shapes, beautifully balanced proportions, precise front view, soft
> satin finish and restrained shallow depth. Professional, calm and clean;
> recognizable at 32 pixels. The outside edge of the rounded square is entirely
> saturated blue, never white. Uniform smooth rounded corners, perfectly clean
> continuous silhouette, no outer shadow, no glow, no outline and no stray
> pixels. The tile occupies about 82 percent of the square canvas. The
> background outside the blue tile is genuinely transparent alpha. No white
> backing plate, no white rectangle, no checkerboard artwork, no presentation
> background, no text, no letters, no badge, no sparkle, no watermark, no
> decorative elements. Final square icon PNG, 1024x1024.

The prompt requests a 1024 px image; the returned artwork is 1254 px. Icon
Composer's layout uses its actual dimensions, and the asset compiler creates
the exact platform representations.
