# Arcora 1.2.0

Native macOS 14+ archive utility. Build with Xcode and Python 3:

```bash
bash Scripts/bootstrap-engines.sh
bash Scripts/build-app.sh
open dist/Arcora.app
```

The universal app includes 7-Zip 26.03, libarchive 3.8.9 and liblzma 5.8.3. These included formats require no extra installation. Optional RAR creation has the one-time setup below.

RAR/RAR5 browsing, testing and extraction work immediately. To create RAR5, open Settings → Engines: open the official download for your Mac, import the original downloaded .tar.gz, then import your own purchased rarreg.key and confirm usage rights. No manual extraction, terminal, Homebrew or administrator installation is required. Solid compression, Unicode passwords, encrypted names and volumes are supported.

This product does not distribute a RAR encoder or license, mirror downloads or download in the background. Original-package and binary hashes are pinned; modified or mismatched packages are rejected. macOS security checks remain enabled. A real purchased-license activation test, Developer ID signing, notarization and clean-machine acceptance are still required before public release. See RAR_DELIVERY.md.

RAR recovery records, REV repair, SFX creation and in-place archive editing are not implemented. ZIP creation requires an ASCII password (AES: up to 99 characters); use 7z or RAR for Unicode passwords. Unsafe paths, links and special files are rejected.

See TEST_REPORT.md for actual macOS verification and USER_GUIDE.md for use and release instructions.
