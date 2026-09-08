# Third-party notices

Original Arcora source is licensed under MIT. No MIT claim is made over upstream engines, OS libraries, commercial RAR software, or attributed test fixtures.

## 7-Zip 26.03

Author: Igor Pavlov and the respective upstream copyright holders.
Official project: https://www.7-zip.org/
License text: https://www.7-zip.org/license.txt
Pinned release: https://github.com/ip7z/7zip/releases/tag/26.03

Most 7-Zip code is under GNU LGPL; specified portions are under BSD 3-clause terms, and specified unRAR-derived portions carry unRAR restrictions. Consult the exact release's license files, not this summary, for authoritative terms. Those restrictions do not license creation of a competing RAR encoder using restricted unRAR code.

The public repository provides a pinned download/verification recipe, not prebuilt engines. `bootstrap-engines.sh` retrieves exact upstream assets and corresponding source, verifies pinned SHA-256 values, and preserves original license files. `build-app.sh` includes the original license material and unmodified `7z2603-src.tar.xz` in `Contents/Resources/ThirdParty/`. Do not remove them from a distributed build. The 7-Zip executable remains a separate process, not statically linked into Arcora's original Swift source.

If modifying the upstream engine or changing how it is linked/distributed, review all applicable source, modification and relinking obligations before distribution. Original source archives retain all their own notices.

## libarchive 3.8.9 and liblzma (XZ 5.8.3)

Official project: https://www.libarchive.org/
Source and full notices: https://github.com/libarchive/libarchive
License overview: https://github.com/libarchive/libarchive/blob/master/COPYING

The macOS build statically links the pinned, unmodified libarchive 3.8.9 and liblzma from XZ 5.8.3, built from official source for arm64 and x86_64 with the macOS SDK. Linux development still uses its system libarchive. The macOS SDK supplies zlib, bzip2 and iconv. No Homebrew runtime libraries are required. Original source archives and COPYING notices accompany the application in Contents/Resources/ThirdParty. The full source archives contain the authoritative per-file license texts.

XZ official source: https://github.com/tukaani-project/xz/releases/tag/v5.8.3
libarchive pinned source: https://github.com/libarchive/libarchive/releases/tag/v3.8.9

## RAR 7.23 command-line tool

Author: Alexander L. Roshal; licensor: win.rar GmbH.
Official download information: https://www.rarlab.com/
EULA: https://www.rarlab.com/license.htm

Ordinary/source builds do not redistribute the proprietary RAR executable or registration data. Official RAR 7.23 may be downloaded separately for local evaluation using Scripts/prepare-rar-testing.sh, subject to the vendor's evaluation and use terms. Local evaluation does not grant bundling rights or perpetual customer-use rights.

This edition does not bundle the RAR encoder or original RAR download. The user opens a hardware-matched official URL in their browser, then imports the unchanged original locally into private application data. Original-package and executable SHA-256 pins are checked, the complete upstream package and documentation are retained, and macOS quarantine is preserved. Arcora does not provide a runtime downloader, mirror, repackaged download or administrative installer. Its release checks refuse RAR components in the app.

Arcora's MIT license does not license the proprietary RAR encoder. Customers provide their own valid rarreg.key and confirm their usage rights; the official tool's registration response gates creation. This does not audit purchase provenance or seat counts and is not a vendor endorsement or blanket legal opinion. If future versions bundle components or downloads, the required written permissions must be obtained separately. The application's no-advertising policy is not a promise about independently obtained third-party tools.

## RAR5 regression fixtures from libarchive

The two small fixture files `rar5-stored.rar` and `rar5-compressed.rar` under `Tests/ArcoraCoreTests/Fixtures` were decoded without content modification from the official libarchive test fixtures:

- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar5_stored.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar5_compressed.rar.uu

The associated upstream tests and copyright notice are in `libarchive/test/test_read_format_rar5.c`. Retrieved 2026-09-07. See `Documentation/FIXTURE_PROVENANCE.md` for local file SHA-256 values. Their applicable notice is reproduced below:

```text
Copyright (c) 2018 Grzegorz Antoniak
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Other generated regression archives are created by `Scripts/generate-fixtures.py` from original artificial data. Malicious-path fixtures are inert test archives and should only be used in controlled tests; do not deliberately extract them with an unsafe third-party tool.

The additional RAR4 fixtures rar4-windows.rar and rar4-solid-encrypted.rar are unchanged uudecoded files from libarchive v3.8.9. Their source names, hashes, and complete original notices are recorded in Documentation/RAR_FIXTURE_NOTICES.md. RAR archives generated during integration tests contain original artificial test data and are removed with their temporary test directories.

## Apple frameworks and icons

SwiftUI, AppKit, Foundation and QuickLookUI are system frameworks, not copied framework binaries. SF Symbols are used via system image names at runtime; no font files are included. The app icon is generated from original vector geometry by `Scripts/make-icon.swift`. Apple developer tools, framework use, signing and distribution remain subject to Apple's applicable terms.
