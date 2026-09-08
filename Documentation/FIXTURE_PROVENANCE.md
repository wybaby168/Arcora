# Fixture provenance

Retrieved from the official libarchive test suite on 2026-09-07. Original uuencoding was decoded to bytes without altering archive content. Attribution and the BSD-style notice are reproduced in THIRD_PARTY_NOTICES.md. The exact bytes delivered are pinned below; the upstream URLs use the branch visible at retrieval, so compare these hashes if regenerating later.

| Local file | SHA-256 | Bytes |
| --- | --- | --- |
| `rar5-stored.rar` | `35d75e315d164d2e329afc28f7d844f013271b4fcffd4ddd78efcdd114a383a7` | 109 |
| `rar5-compressed.rar` | `68f9d7e2662cd5bc5607ba9c6bf1edbf121cf3b08011a7d8643091791750a7c8` | 436 |

Stored source: https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar5_stored.rar.uu

Compressed source: https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar5_compressed.rar.uu

Associated assertions and copyright: https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar5.c

`rar5-stored.rar` contains `helloworld.txt` with `hello libarchive test suite!\n`. `rar5-compressed.rar` contains `test.bin`: 300 little-endian UInt32 values generated from `max(0, k*k - 3*k + 1)` for k = 1...300. Actual extracted contents are checked against those expected bytes.

The additional `rar4-windows.rar` and `rar4-solid-encrypted.rar` fixtures come from pinned libarchive 3.8.9 source; full original notices, provenance and hashes are in [RAR_FIXTURE_NOTICES.md](RAR_FIXTURE_NOTICES.md).

The remaining fixtures are synthetic, generated locally by `Scripts/generate-fixtures.py`. They include ordinary ZIP/TAR variants and intentionally unsafe metadata for negative tests. They contain no real personal documents, credentials or executable payloads. `expected.json` records the benign generated data in hexadecimal. Re-running the generator must not erase the separately attributed RAR fixtures.
