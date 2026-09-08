# Private local RAR builds

[English README](../README.md) · [中文说明](../README.zh-CN.md) · [日本語 README](../README.ja.md)

This workflow assembles an app with the official RAR encoder already included **for your own local use only**. It is separate from the standard public app and is not a distributable Arcora release. No registration key, usage license or redistribution grant is supplied.

RARLAB permits evaluation for a maximum of 40 days; continued use requires the applicable purchased license. A locally built app does not restart that period or grant additional seats. Import your own valid `rarreg.key` in Settings → Engines for licensed local use. See the [official terms](https://www.rarlab.com/license.htm).

## Build

After building the standard app as described in the README:

```bash
# Developer-only preparation: retrieves the pinned official packages into .local.
bash Scripts/prepare-rar-testing.sh

# Explicitly assemble a private local app, without the standard app's added license gate.
# The official RAR evaluation / usage conditions still apply.
ARCORA_RAR_LOCAL_EVALUATION=1 ARCORA_RAR_CODEC_EVALUATION=1 \
  bash Scripts/build-rar-test-app.sh
open .local/Arcora-RAR-Codec-Evaluation.app
```

The app includes separate arm64 and x86_64 official engines, original packages and notices. It creates RAR5, including solid compression, Unicode passwords, encrypted names and split volumes. It also reads RAR4 / RAR5 through the bundled 7-Zip engine. The same unsupported features listed in the README remain unsupported; an included encoder does not add RAR repair or archive editing UI.

The local-only switch allows official evaluation without Arcora's standard customer-license gate. It does not generate a key, patch the official registration mechanism or establish lawful use. If you import a valid key, actual compression receives Arcora's private RAR configuration directory. A missing key is shown as evaluation, not as registered.

The output is ad-hoc signed, not notarized. It stays under ignored `.local/`; do not copy it into public `dist/`, GitHub Actions artifacts or release attachments. The standard `dist/Arcora.app` remains free of RAR encoders and keys.

## Verification

On an Apple Silicon Mac:

```bash
ARCORA_REQUIRE_7ZZ=1 ARCORA_REQUIRE_RAR=1 ARCORA_REQUIRE_RAR_PACKAGE=1 \
  ARCORA_RAR="$PWD/.local/rar/arm64/rar" swift test
ARCORA_REQUIRE_7ZZ=1 ARCORA_REQUIRE_RAR=1 ARCORA_REQUIRE_RAR_PACKAGE=1 \
  ARCORA_RAR="$PWD/.local/rar/arm64/rar" swift test -c release
python3 Scripts/verify-app.py .local/Arcora-RAR-Codec-Evaluation.app --require-rar --arch arm64
# Requires an already available Rosetta runtime; does not install it.
python3 Scripts/verify-app.py .local/Arcora-RAR-Codec-Evaluation.app --require-rar --arch x86_64
```

On Intel, select `.local/rar/x86_64/rar` and run the x86_64 packaged-app test. The verifier uses isolated temporary data directories. Private licensed acceptance of the standard app additionally needs `--rar-package /private/path/to/original.tar.gz --license-file /private/path/to/rarreg.key`; only provide a license that covers the test machine. Test logs must stay private.

## 中文要点

本流程保留一份已内置官方 RAR 引擎的本机专用应用，无需在应用中再次下载安装。它不包含许可证，不得分发。RAR 最长 40 天评估期仍然适用；继续使用需要自己的有效许可证，可在“设置 → 引擎”导入。内置引擎不等于永久免费，也不新增修复、REV 或归档内部编辑等未实现功能。`.local` 及其中的应用、原包、日志和注册资料不得上传 GitHub。

## 日本語の要点

この手順では、公式 RAR エンコーダーを内蔵した自分の Mac 専用アプリを作成します。アプリ内で再ダウンロードする必要はありません。ライセンスは含まれず、配布もできません。最大 40 日間の評価条件が適用され、その後は有効なライセンスが必要です。自分のキーを「設定 → エンジン」からインポートしてください。内蔵は無期限の無料利用や未実装機能の追加を意味しません。`.local` 内のアプリ、原パッケージ、ログ、登録情報を GitHub にアップロードしてはいけません。
