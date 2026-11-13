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

The multipart RAR5 fixtures below were decoded from the pinned libarchive 3.8.9 source archive on 2026-11-13. The original filenames follow `libarchive/test/test_read_format_rar5_multiarchive.partNN.rar.uu`. Archive bytes are preserved. The payload contains libarchive's compiled test programs. Regression coverage lists the archives, checks their integrity and diagnoses missing volumes. The 2018 Grzegorz Antoniak notice in THIRD_PARTY_NOTICES.md applies. [Upstream tests and notice](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/test/test_read_format_rar5.c)

| Local file | SHA-256 | Bytes |
| --- | --- | --- |
| `rar5-multipart.part01.rar` | `2f3894dc4b8a1bba90830ef1f89f457b0295b6f9030c70febd57283721bc2ce3` | 15360 |
| `rar5-multipart.part02.rar` | `0a5b7a8923beb5747d67f708f17bdc4ebfc8cf2c3010523332e1a1633d7a4c72` | 15360 |
| `rar5-multipart.part03.rar` | `31699cbed68297245347911910743c3cb0c6075d28336a7dd4864d4019b8208a` | 15360 |
| `rar5-multipart.part04.rar` | `c2d0d72b7c4dd229a944986eee95f802e487e4570e41f7ca7e77b9e82ca4119c` | 15360 |
| `rar5-multipart.part05.rar` | `cc69c161ec00e2deeec263fb24f704d1f0d90ccc6b2aeb3baed2539878b5240d` | 15360 |
| `rar5-multipart.part06.rar` | `86b7efeacaf2443564220c683eec0880b999dbfe27ae1bc2645f0fffe4646d8c` | 15360 |
| `rar5-multipart.part07.rar` | `0b2c9bc7b5679069f9cbe68a9e08351868a3309bf24a5534d8207cf14d41b8b7` | 15360 |
| `rar5-multipart.part08.rar` | `b86fa56607d4ee98e0374f84040a0e11ab18bc726a8b772151a1feee9c7045a3` | 9208 |

The remaining fixtures are synthetic, generated locally by `Scripts/generate-fixtures.py`. They include ordinary ZIP/TAR variants and intentionally unsafe metadata for negative tests. They contain no real personal documents, credentials or executable payloads. `expected.json` records the benign generated data in hexadecimal. Re-running the generator must not erase the separately attributed RAR fixtures.
