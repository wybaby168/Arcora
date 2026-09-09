# Arcora

<p align="center"><img src="Sources/Arcora/Resources/Brand/ArcoraIcon.png" width="112" height="112" alt="Arcora アプリアイコン"></p>

**macOS ネイティブのアーカイブツール。ローカル処理、自然な操作感、明確な対応範囲。**

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

[![macOS 検証](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml/badge.svg)](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

Arcora は SwiftUI / AppKit で構築された、圧縮・閲覧・展開・整合性検査のためのアプリです。Apple Silicon と Intel Mac に対応し、日本語・英語・簡体字中国語の UI を備えています。アーカイブの内容は Mac 内で処理され、アカウント、アップロードサービス、広告 SDK、テレメトリーはありません。

> このリポジトリはソースコードとビルドスクリプトを提供します。公証済みインストーラーではありません。標準ビルドは実行時依存関係を同梱しますが、**商用 RAR エンコーダーや RAR ライセンスは同梱しません**。RAR の展開はすぐに利用でき、RAR の作成には以下の追加設定が必要です。

## 主な機能

- ドラッグ＆ドロップ、Finder 連携、検索、並べ替え、選択項目の展開、Quick Look に対応したネイティブのアーカイブブラウザー。
- Finder の右クリックから ZIP・7z・オプションの RAR をすばやく作成。詳細設定用の圧縮メニューも用意。
- 7z、ZIP、TAR 系形式、単一ファイルの圧縮ストリームを作成。RAR5 の作成はオプションで利用可能。
- 対応形式での暗号化と分割。7z / RAR ではファイル名の暗号化も可能。
- 進捗表示、一時停止、再開、キャンセル、スレッド数・メモリー予算を備えたタスクキュー。
- 非公開の作業領域で処理・検証してから出力を確定し、既存ファイルを黙って上書きしない設計。
- 固定バージョンの依存関係を使う Universal App。利用先の Mac に Homebrew を導入する必要はありません。

## 対応形式

| 形式 | 閲覧 / 展開 / 検査 | 作成 | 備考 |
| --- | --- | --- | --- |
| 7z | 内蔵 | 内蔵 | AES-256、ファイル名暗号化、分割 |
| ZIP | 内蔵 | 内蔵 | AES-256 / ZipCrypto、連番分割 |
| RAR4 / RAR5 | 内蔵 | オプション、RAR5 のみ | 標準版では公式エンコーダーと利用者自身のライセンスが必要 |
| TAR、TAR.GZ、TAR.BZ2、TAR.XZ | 内蔵 | 内蔵 | 暗号化・分割作成には非対応 |
| GZ、BZ2、XZ | 内蔵 | 内蔵 | 圧縮ストリームごとに通常ファイル 1 個 |
| その他の 7-Zip 対応形式 | 読み取り専用のエンジン連携 | 提供なし | すべての形式・派生仕様を検証済みではありません |

追加の読み取り専用形式と検証範囲は[対応形式の詳細](Documentation/FORMAT_SUPPORT.md)を参照してください。RAR 修復、リカバリーレコード、REV、SFX 作成、既存アーカイブ内部の編集は未実装です。ZIP 作成時のパスワードは ASCII のみで、AES は最大 99 文字です。Unicode パスワードには 7z または RAR を使用してください。

## ビルドと起動

ビルドには macOS 26 以降、Xcode 26 以降と選択済みのコマンドラインツール、Python 3 が必要です。ネイティブアイコンの検証には新しい CoreUI ツールを使用しますが、生成したアプリは引き続き macOS 14 以降に対応します。初回の依存関係の準備にはインターネット接続を使用します。

```bash
git clone https://github.com/wybaby168/Arcora.git
cd Arcora
bash Scripts/bootstrap-engines.sh
bash Scripts/build-app.sh
open dist/Arcora.app
```

準備スクリプトは公式の 7-Zip 26.03、libarchive 3.8.9、XZ 5.8.3 を取得し、固定 SHA-256 と照合します。ビルドスクリプトは arm64 / x86_64 の Universal App を生成し、必要な上流ソースアーカイブとライセンス文書を保持します。バージョンとハッシュは [engines.lock.json](Vendor/engines.lock.json) に記録されています。

既定の署名はローカル開発用の **ad-hoc 署名**です。Developer ID 署名、Apple の公証、クリーンな環境での受け入れ試験は別途必要です。[リリース手順](Documentation/RELEASE.md)を参照してください。Arcora は Gatekeeper を無効化したり、ダウンロードの隔離属性を削除して macOS の検査を回避したりしません。

## Finder からすばやく圧縮

ビルドしたアプリをシステムまたは利用者の **Applications フォルダー**に移動し、一度起動してください。Finder でファイルやフォルダーを選択し、右クリックの**サービス → Arcora — ZIP / 7z / RAR にすばやく圧縮**を選びます。

クイック圧縮は**暗号化なし**で作成・検証し、選択項目と同じ場所に保存します。元のファイルは残し、同名の出力には番号を付けて上書きを防ぎます。複数の項目は一つにまとめ、異なる場所からの選択では保存先を確認します。Arcora で進捗確認とキャンセルができ、完了後は Finder に結果を表示します。サービスからアプリを起動することもできます。

macOS がサービス実行の確認を表示する場合は、確認後にファイルが渡されます。このシステムの安全確認は無効にしません。

パスワードや分割などが必要な場合は **Arcora — 詳細設定で圧縮…**を選んでください。RAR のクイック圧縮にも通常のエンジン・ライセンス確認を適用し、未設定なら RAR の設定画面を開きます。別の形式へ自動変更することはありません。

項目が見つからない場合は、**設定 → 一般 → Finder クイック圧縮**でサービスを更新し、**システム設定 → キーボード → キーボードショートカット → サービス → ファイルとフォルダ**も確認してください。メニューの配置と言語は macOS が管理します。利用者が無効にしたサービスを強制的に有効化することはありません。[Finder ガイド](Documentation/FINDER_SERVICES.md)も参照してください。

[Finder 検証記録](Documentation/FINDER_VALIDATION.md)では、実際の UI 操作、自動テストの範囲、残っているリリース条件を区別しています。

## RAR 作成の追加設定

標準アプリの**設定 → エンジン**を開きます。

1. Mac のハードウェアに合う RARLAB 公式ダウンロードリンクを開きます。
2. 変更していない元の `.tar.gz` をインポートします。Arcora がバージョン、アーキテクチャ、SHA-256 を検証し、利用者専用のアプリデータ領域に設定します。
3. 自分で購入した `rarreg.key` をインポートし、使用権が今回の利用をカバーすることを確認します。公式エンジンが登録を確認した後に作成機能が有効になります。

手動展開、ターミナル操作、Homebrew、管理者権限でのインストールは不要です。ダウンロードは利用者の操作でブラウザーから行い、アプリ内ダウンローダーやミラーは提供しません。ライセンスはローカルに保存され、アプリへの同梱やサーバーへの送信は行いません。不明なパッケージ、改変されたパッケージ、無効なライセンスは拒否します。

自分の Mac だけで使う場合は、[エンコーダーを内蔵したローカルビルド](Documentation/LOCAL_RAR.md)も利用できます。そのバイナリー、RAR の元パッケージ、登録ファイルをリポジトリやリリース添付物にアップロードしてはいけません。ローカル利用にも公式の評価期間とライセンス条件が適用されます。

Arcora の MIT ライセンスは RAR の使用権や再配布権を付与しません。この連携は RARLAB の承認を意味せず、ライセンスの取得経路やライセンス数を監査するものでもありません。[RARLAB EULA](https://www.rarlab.com/license.htm)、[連携ポリシー](Documentation/RAR_DELIVERY.md)、[ライセンス保存設計](Documentation/RAR_LICENSES.md)を確認してください。

## 開発と検証

依存関係の準備後に実行します。

```bash
ARCORA_REQUIRE_7ZZ=1 bash Scripts/validate.sh
ARCORA_REQUIRE_7ZZ=1 swift test -c release
python3 Scripts/verify-app.py dist/Arcora.app
```

GitHub Actions は公開ソース、翻訳、コンパイル、基本回帰テスト、実際の Universal App を検査します。RAR のダウンロードやライセンスの提供は行いません。オプションの RAR がない場合、該当テストは明示的にスキップされます。基本 CI の成功は、実ライセンスによる RAR 作成の検証完了を意味しません。非公開で行う RAR テストの方法と未完了事項は[検証レポート](Documentation/TEST_REPORT.md)に記載しています。

開発用 CLI は `.build/debug/arcora-cli`、アプリ同梱 CLI は `dist/Arcora.app/Contents/Helpers/arcora` です。

```bash
.build/debug/arcora-cli engines
.build/debug/arcora-cli inspect /path/to/example.rar
.build/debug/arcora-cli extract /path/to/example.rar --to /path/to/output
.build/debug/arcora-cli create --format 7z --output /path/to/archive.7z -- /path/to/documents
```

パスワードはコマンドライン引数ではなく `--password-stdin` から渡してください。アプリ同梱の実行ファイルは、開発用エンジンパスの上書き指定を無視します。

## セキュリティーと構成

危険なパス、リンク、特殊ファイルを拒否し、リソース制限と展開後の検査を行います。外部コーデックはネイティブの子プロセスですが、**強固な App Sandbox の隔離境界ではありません**。コーデックの脆弱性、悪意のあるファイル、リソース枯渇のリスクは残ります。完全な Unix バックアップツールではなく、ACL、所有者、リソースフォーク、すべての拡張属性の復元を保証しません。

| 場所 | 役割 |
| --- | --- |
| `Sources/Arcora` | SwiftUI / AppKit アプリと翻訳 |
| `Sources/ArcoraCore` | アーカイブ処理、スケジューリング基盤、安全性、RAR 設定 |
| `Sources/CArcora`、`Sources/ArcoraWorker` | libarchive のネイティブブリッジとワーカープロセス |
| `Sources/ArcoraCLI` | コマンドラインインターフェース |
| `Tests`、`Scripts` | 回帰テスト用データ、ビルド・検証ツール |

[アーキテクチャー](Documentation/ARCHITECTURE.md)、[安全性の設計](Documentation/SECURITY.md)、[脆弱性の報告方針](SECURITY.md)も参照してください。

## ドキュメントと貢献

- [English quick start](Documentation/QUICKSTART.en.md) · [中文用户指南](Documentation/USER_GUIDE.md) · [日本語クイックスタート](Documentation/QUICKSTART.ja.md)
- [貢献ガイド](CONTRIBUTING.md) · [macOS 受け入れチェックリスト](Documentation/MACOS_ACCEPTANCE.md)
- [検証範囲とリリース前の確認事項](Documentation/TEST_REPORT.md)

不具合報告には macOS のバージョン、ソースのリビジョン、形式、機密情報を含まない最小の再現手順を添えてください。顧客のアーカイブ、パスワード、登録キーは添付しないでください。共通の形式処理、安全性、アクセシビリティー、翻訳の改善を歓迎します。

## ライセンス

Arcora 独自のコードと文書は [MIT ライセンス](LICENSE)です。外部エンジンと出典を明示したテストデータには、該当する 7-Zip / unRAR の制限を含む、それぞれのライセンスが適用されます。[第三者ソフトウェアの表示](THIRD_PARTY_NOTICES.md)を参照してください。RAR エンコーダーはプロプライエタリーソフトウェアであり、公開ソース配布物には含まれません。
