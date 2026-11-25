# 開発環境・起動手順と環境構築の検証記録

最終整理日：2026-11-25。対象：Repo Search（ゆめみ Flutter エンジニアコードチェック課題の自主開発）。アプリ本体の基準コミットは `8fd463c70b6a86c774c01dda9fd51f2152ca6af0`（PR #16 マージ後）。

本書の前半は現行アプリの開発・起動・検証手順、後半は環境構築とSDK更新の履歴である。過去の記録は当時の構成・実行結果を示し、現行アプリの仕様や未解決事項とは区別する。現在の機能・設計は [README](../README.md) と [現行設計書](architecture.md)、AI利用と開発中の判断は [AI利用記録](ai-notes.md) を参照する。

個人のホームディレクトリを含むパスは、公開用資料として `$HOME` や環境変数を用いた表記に整理した。過去の実行コマンドも同等の参照先を示すよう一般化しており、元ログの逐語的な転載ではない。元の記録はGit履歴に残る。

## 1. 現在の開発環境

2026-11-25の環境確認、プロジェクト設定、既存APKの検査、開発記録に基づく。第三者が同じWindows・WSL構成を用意することは必須ではない。以下のSDK・ツールと対応するAndroid端末またはエミュレーターを利用できる環境であれば、まず第2節の共通手順を使用する。

| 項目 | 使用・設定値 |
| --- | --- |
| Flutter | 3.50.1 stable（Framework revision `ae9b586f34`） |
| Dart | 3.14.0（SDK制約 `^3.14.0`） |
| DevTools | 2.61.0 |
| IDE | Visual Studio Code 1.147.0 x64 |
| 開発用OS | Windows + WSL2 / Ubuntu 24.04 |
| Android最小API | 24（Android 7.0） |
| Android Target SDK / Compile SDK | 36 / 36 |
| Java / Kotlin JVM Target | 17 / 17 |
| Gradle Wrapper | 9.5.0 |
| 動作確認端末 | Windows上のAndroidエミュレーター（Android 17 / API 37 / x86_64） |
| iOS Deployment Target | 15.0（設定確認のみ。ビルド・実行未検証） |
| アプリバージョン | `1.0.0+1` |
| Android Application ID | `com.example.yumemi_app` |
| Dartパッケージ名 | `yumemi_app` |

AndroidのminSdk・targetSdk・compileSdk・NDKはFlutter側の標準値を利用する設定。上表のAPI数値は使用SDKと既存APKの確認結果であり、すべての対象OSで動作試験を行ったという意味ではない。Android SDK、Build Tools、NDK等の導入状況の詳細は後半の環境構築時の記録を参照する。

VS Codeは実際に使用したIDE。Flutter・DartおよびWSLを利用する開発構成と組み合わせられるため、今回の環境に適している（IDE間の比較試験は行っていない）。

### 1.1 依存関係

`pubspec.yaml` と2026-11-25の `flutter pub deps --style=compact` の結果に基づく。アプリの依存解決ではリポジトリに含まれる `pubspec.lock` を利用し、セットアップ時に意図的なパッケージ更新を行わない。

| パッケージ | 解決済みバージョン | 主な用途 |
| --- | --- | --- |
| `flutter` | SDK同梱 | アプリの実行基盤 |
| `flutter_localizations` | SDK同梱 | 標準UIのローカライズ |
| `material_ui` | 1.11.1 | Material Design UI |
| `flutter_riverpod` | 3.5.0 | 状態管理・依存先の差し替え |
| `http` | 1.6.0 | GitHub REST API通信 |
| `shared_preferences` | 2.5.6 | 検索欄の配置・Issue取得方式の保存 |
| `intl` | 0.20.3 | 数値・日時の表示書式 |
| `cupertino_icons` | 1.0.9 | 初期テンプレートから維持している依存 |
| `flutter_test` | SDK同梱 | 自動テスト（開発用） |
| `flutter_lints` | 6.0.0 | 静的解析ルール（開発用） |

`intl: any` はSDKの `flutter_localizations` が要求する版とlockfileによって解決される。Riverpodのコード生成は使用しない。詳細な依存関係は `flutter pub deps --style=compact` で確認できる。

## 2. 第三者向けの起動・検証手順

### 2.1 準備と環境確認

Flutter 3.50.1 stable（Dart同梱）、Android SDKとJava 17を利用できる環境、およびGitが必要。Flutter SDKとAndroidツールの構築については [Flutter公式のセットアップ手順](https://docs.flutter.dev/get-started/install) を参照する。Gradle Wrapperはプロジェクト設定を使用する。初回の依存取得やビルドにはネットワーク接続と、必要なSDK・ライセンスの準備が必要になる場合がある。

リポジトリを取得済みの状態で、`pubspec.yaml` があるプロジェクトルートをカレントディレクトリとして以下を実行する。

```bash
flutter --version
dart --version
flutter doctor -v
```

SDKが複数インストールされている場合は、現在のシェルが意図したFlutterとDartを参照していることを確認する。WSL固有の設定は第3節を参照する。

### 2.2 依存取得と起動

```bash
flutter pub get --enforce-lockfile
flutter devices
```

Androidエミュレーターを起動するか、利用可能なAndroid端末を接続する。`flutter devices` に対象端末が表示されたことを確認し、次の例の端末IDを実際のIDに置き換えて起動する。

```bash
flutter run -d emulator-5554
```

通常起動は実際のGitHub REST APIに接続する。公開リポジトリを対象とし、GitHubの認証トークンの設定は不要。APIへのアクセスにはネットワーク接続が必要で、未認証の利用制限が適用される。検索画面の操作や通信仕様の詳細は [README](../README.md) と [現行設計書](architecture.md) を参照する。

Debug実行中はターミナルの `r` でHot Reload、`R` でHot Restart、`q` で終了する。Android/iOSのネイティブ設定・ランチャーアイコンなどの変更は、Hot Reloadだけでは反映されないため、終了してビルド・起動し直す。

### 2.3 品質検証

次のコマンドは現行のCIで行う品質検証に対応する。CIの実行条件などの正確な設定は [Workflow](../.github/workflows/flutter.yml) を参照する。

```bash
flutter pub get --enforce-lockfile
flutter gen-l10n
git status --short -- lib/l10n
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
dart format --output=none --set-exit-if-changed lib test
```

`flutter gen-l10n` の生成コード3ファイルはGit管理している。クリーンなチェックアウトから生成した場合は `lib/l10n` に意図しない差分がないことを確認する。翻訳リソースを変更した場合は必要な生成差分もレビューする。

`flutter pub get` とビルド・翻訳生成は作業ディレクトリやSDKキャッシュにファイルを書き込む処理である。`pubspec.lock` や追跡中のファイルに意図しない変更がないか、実行後に `git status --short` などで確認する。上記は再現手順であり、本資料の整理作業中に再実行した結果ではない。

## 3. Windows + WSLでの開発方法

この節は開発者が実際に用いた構成を基にした補足であり、全利用者にWSLを要求するものではない。Windows版Dartがアプリケーション制御ポリシーで起動を拒否されたことから、OSのセキュリティ設定を変更せず、WSL版Flutter・Dartによる開発に切り替えた。Windows側はAndroidエミュレーターを利用する。

### 3.1 SDKの選択

WSLのシェルで、Linux版SDKを優先する。以下は開発時の配置を一般化した例なので、実際のSDK配置に合わせて変更する。

```bash
export PATH="$HOME/develop/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
command -v flutter dart
flutter --version
flutter doctor -v
```

この `export` は実行したシェル内の環境設定。OSの設定やシェル設定ファイルを永続変更する必要はない。開発当時の具体的な調査・対応は第6節に記録する。

### 3.2 Windowsエミュレーターの認識と直接実行

開発時には既存のWSLの `networkingMode=mirrored` 環境で、Linux側のADBからWindowsエミュレーターを認識できた。別のネットワーク構成で同様に接続できることを保証するものではない。

```bash
"$ANDROID_HOME/platform-tools/adb" devices -l
flutter devices
flutter run --debug --no-pub -d emulator-5554 --host-vmservice-port=0
```

依存解決は事前に第2節の方法で行い、端末IDは実際の値を使用する。ADBの待受やデバッグ接続が利用できない場合は、接続状況を確認し、必要に応じて第4節のAPKによる実行方法を利用する。問題回避のためにADBやDart VM Serviceを外部ネットワークへ公開したり、認証・OSの保護機能を無効化したりすることは、本プロジェクトの手順には含めない。

### 3.3 SDKライセンス・環境上の警告

開発時に `flutter doctor -v` で一部のAndroid SDKライセンスの未同意警告があった。必要な構成でAndroidビルド・起動が成功することと、すべてのSDKライセンスに同意済みであることは別である。警告だけを消すための追加SDK導入や一括同意は行わない。

必要な場合は `flutter doctor --android-licenses` を対話形式で実行し、利用するSDKの条文を確認して自身で判断する。SDKの追加・ライセンスへの同意が必要な場合は、その必要性と対象を確認してから進める。初期の未同意対象7件は2026-11-18時点の記録で、現在の件数としては扱わない。

## 4. Android検証用APK

### 4.1 ローカルでのビルド

```bash
flutter pub get --enforce-lockfile
flutter build apk --release --no-pub
```

出力先は `build/app/outputs/flutter-apk/app-release.apk`。現在のAndroid Release設定は開発用Debug署名鍵で署名する検証用ビルドであり、正式なストア配布用の署名構成ではない。

ADBを使用して起動済みエミュレーターへインストールする例（`adb` がPATHにない場合はAndroid SDKの `platform-tools/adb` を使用する）：

```bash
adb devices -l
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s emulator-5554 shell am start -W -n com.example.yumemi_app/.MainActivity
```

WSLからWindowsエミュレーターを直接認識できない場合は、APKのみをWindowsから読めるフォルダへコピーし、Windows版ADBで同様にインストールする。コピー時はSHA-256の一致を確認する。ソースコードやビルドディレクトリ全体を別環境に複製する必要はない。

既存のアプリと署名鍵が異なる場合は、上書きインストールに失敗することがある。特にローカルのDebug署名鍵とCIランナーの署名鍵は同じとは限らない。既存アプリのアンインストールは保存済みの設定などを失う可能性があるため、自動で行わず、インストール先を確認する。

### 4.2 CIのビルドと検証用成果物

[GitHub ActionsのWorkflow](../.github/workflows/flutter.yml) はFlutter 3.50.1 stableを指定し、lockfileに基づく依存取得、翻訳生成差分検査、解析、全テスト、整形チェックを行う。品質検証成功後のAndroid Release APK生成はmainへのPushとmain向けPRで実行する。featureブランチへのPushでは品質検証のみを実行する構成である。

成功したAndroidビルドのArtifact（保存期間14日間）から `app-release.apk` と `SHA256SUMS.txt` を取得できる。ダウンロードしたアーカイブを展開し、両ファイルがあるディレクトリで確認する例：

```bash
sha256sum -c SHA256SUMS.txt
```

Windows PowerShellでは `Get-FileHash .\app-release.apk -Algorithm SHA256` の値と `SHA256SUMS.txt` を比較する。これはファイルの一致確認であって、独立した署名による真正性の証明やアプリの安全性保証ではない。

最終配布物は、配布対象のコミット、ビルドの成功、チェックサム、実際のインストール・操作結果を別途確認してから扱う。GitHub Releasesでの配布は最終工程の予定であり、本書整理時点で公開済みとは扱わない。

## 5. 検証実績と適用範囲

以下は開発中の実行結果と最終総合レビューによる確認結果である。現在の文書整理で新たに実行した結果ではない。

| 検証 | 確認結果・範囲 |
| --- | --- |
| Androidの開発経路 | WSLでのビルド・Windowsエミュレーターでの起動・Debug接続・Hot Reload / Hot Restartを環境構築時に確認 |
| 実API通信 | Phase 2でAndroidエミュレーターから検索・追加読み込み・0件検索・詳細取得を確認 |
| UI・追加機能 | 開発中にAndroidエミュレーターで回転・文字倍率・日本語/英語・ダークモード・Issue取得方式・ランチャー表示等を確認（すべての組み合わせではない） |
| SDK更新 | 3.50.1への更新後、全307テスト・解析・Releaseビルド・上書きインストール成功（11月24日） |
| 外観改善後 | `flutter analyze` 問題なし、全350テスト成功、Android Release APK生成成功（52.8MB） |
| CI | 開発中のPush / PRでの品質検証、Androidビルド、ArtifactダウンロードとSHA-256一致確認を報告済み |
| 最終総合レビュー | `8fd463c` を対象にソース・設定・履歴・既存APKを調査。独立したDart解析、67ファイルの整形検査、一部のDart動作検証9項目に成功 |
| 独立したFlutter再実行 | 最終レビュー環境ではWSLプロセス起動が `Wsl/E_ACCESSDENIED` となり、全350件のFlutterテスト、エミュレーター操作、Releaseビルドの再実行は未実施 |

最終配布対象コミットのmainのCI・CI生成APKそのもののインストールと動作は、最終配布前に別途確認する。過去のCI成功・ローカルAPKの動作と混同しない。

未検証・対象外として区別する事項：

- iOSはDeployment Targetを15.0に設定し、アイコンや表示名の設定も行っているが、iOS動作検証環境がなく、ビルド・実行・画面表示は未確認。Macを所有していない場合の公式課題のレビュー対象外の扱いは、提出時に事実に即して申告する。
- 物理Android端末、対象OSすべて、TalkBack / VoiceOverでの全画面操作は未検証。
- WindowsネイティブのFlutter開発経路は、Dart起動拒否の詳細な原因が未特定のため、検証済みとしない。
- Web・デスクトップ用の構成・動作は今回の検証対象外。
- Android Release APKにはFlutterの `NOTICES.Z` と一部AndroidX等のLICENSEファイルが存在することを確認済み。ただし、その存在確認だけで全依存関係の再配布条件を満たしたとは判断しない。

---

## 6. 環境構築時の履歴（2026-11-18、Issue #1）

確認日：2026-11-18。対象ブランチ：`feature/1-setup-flutter`。

本書はIssue #1時点の初期カウンターアプリと環境の検証記録。Issue #3の段階1ではRiverpodを追加し、カウンター画面を最小起動表示へ整理した。当時のRiverpod導入と基礎確認の結果は[Riverpod導入と基礎確認](riverpod-basics.md)を参照する。

Issue #3の段階5で行った検索・詳細アプリのAndroid実操作とローカル最終検証は、[スケルトン最終検証記録](skeleton-final-verification.md)に分けて記録する。以下はIssue #1当時の記録である。記述中の「今回」「現在」「未実装」「次の段階」等は、特に断りがない限り2026-11-18の作業時点を指す。現行の環境・仕様・検証結果は前半と現行設計書を参照する。

### 開発環境の選択

- 作業リポジトリ：`$HOME/projects/flutter/yumemi-flutter-codecheck`
- 編集・Git・依存解決・解析・テスト・Androidビルド：WSL2 / Ubuntu 24.04。
- Flutter SDK：`$HOME/develop/flutter`（3.50.0 stable）。同梱Dart：3.14.0。
- Android SDK：`$HOME/Android/Sdk`。Platform 36、Build Tools 36.0.0、NDK 28.2.13676358、Platform Tools 37.0.1。
- Java：WSLのOpenJDK 17.0.21.0.3。
- Windows：Android Studio 2026.2.2系、Android Emulator 37.2.13、ADB 37.0.1。SDKは`%LOCALAPPDATA%\Android\Sdk`。
- 仮想端末：`Medium_Phone_API_37.0`（x86_64）。確認時のADB識別子は`emulator-5554`。

Windows版Dartは実起動時に「アプリケーション制御ポリシーによってこのファイルがブロックされました」となり、実行できなかった。ポリシーを変更せずWSL版を使用する。WindowsのADBとエミュレーターは実行可能。Windows側でFlutterを実行したり、ソースを複製してビルドしたりする構成にはしない。

### SDKの使い分け

今回の実行シェルでは`flutter`・`dart`がWindows側を指していた。WSLでの実行時は、次のようにWSL用SDKを明示する。以下の環境変数はそのターミナル内だけの設定で、ユーザーのシェル設定ファイルは変更していない。

```bash
export PATH="$HOME/develop/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
command -v flutter dart
flutter --version
```

Androidの診断では、空の`HTTP_PROXY`・`HTTPS_PROXY`をSDK管理ツールが解釈できず失敗した。今回の診断とSDK管理コマンドに限り、空のプロキシ変数を`env -u`で除外して再実行した。OSやユーザーの永続設定は変更していない。

### 初期アプリの取り込み

別フォルダ`yumemi_app`の初期カウンターアプリから、`lib/`・`test/`・`android/`・`ios/`・`.metadata`・`analysis_options.yaml`・`pubspec.yaml`・`pubspec.lock`を選択して取り込んだ。生成物・キャッシュ・元のGit管理情報・ローカルSDK設定・元の資料はコピーしていない。既存のルート`.gitignore`とPRテンプレートは維持した。READMEは環境の現状に合わせて更新した。

アプリ名は既存の`yumemi_app`、Androidの識別子は`com.example.yumemi_app`を維持している。検索・詳細の骨組みやRiverpodはまだ実装していない。

### Material Designについての見直し

[公式課題](https://github.com/yumemi-inc/flutter-engineer-codecheck#デザイン)は「マテリアルデザインに準拠すること」を要求し、import先は指定していない。

[Flutter公式material_ui](https://github.com/flutter/packages/tree/main/packages/material_ui)はMaterial Designの公式ライブラリ。現在のSDKの`packages/flutter/lib/material.dart`には`material_ui`への移行を案内する非推奨指定があり、SDKの生成テンプレートも`material_ui`を使用している。

このため以前の「独自UIライブラリを避けて標準Materialへ切り替える」という理解を訂正し、初期サンプルの`material_ui`を維持する。`pubspec.yaml`・`pubspec.lock`は元のサンプルと同一。新しいアプリ用パッケージは追加していない。

### 実行した確認

1. WSLのDartを直接実行：3.14.0として正常起動。
2. WindowsのDartを直接実行：アプリケーション制御ポリシーで起動拒否。
3. WSLの`flutter doctor -v`：Flutterは正常。Android SDKとJDKを認識。SDKの一部ライセンス未同意、Chrome・Linuxデスクトップ向けツールの不足を検出。
4. 元サンプルの`flutter analyze --no-pub`：問題なし。
5. 取り込み先で`flutter pub get --offline --enforce-lockfile`：既存キャッシュだけで成功。依存設定・lockfileの変更なし。
6. 取り込み先で`flutter test --no-pub test/widget_test.dart`：1件成功。
7. 取り込み先で`flutter analyze --no-pub`：問題なし。
8. Androidのオフラインビルド：最初はSDK用CMake 3.22.1不足で失敗。ユーザーの許可を受け、既存WSL Android SDKへ`cmake;3.22.1`だけを追加。システム全体へのインストールは行っていない。
9. WSLの`flutter build apk --debug --no-pub --target-platform android-x64`：成功。`build/app/outputs/flutter-apk/app-debug.apk`を生成。SDKの自動追加は無効にして実行した。
10. Windowsの既存仮想端末を起動し、ADBが`emulator-5554`を`device`として認識。起動完了プロパティは`1`。
11. Windows ADBでAPKをインストール：`Success`。`am start -W`で`Status: ok`。スクリーンショットを目視し、初期カウンター画面・値0・加算ボタンの表示を確認した。

実行時には上記のWSL用SDK・Android SDKを環境変数で指定した。ビルドには既存Gradle 9.5.0・AGP 9.3.1を使用。テンプレート由来のAGP/Kotlin関連の非推奨警告は残しており、隠す設定やビルド構成の移行は行っていない。

### Android上での実行方法

#### WSLからの直接Debug実行（追加検証済み）

今回の環境ではWSLの`.wslconfig`に`networkingMode=mirrored`が設定され、WSLのLinux ADBからWindowsエミュレーターを認識できた。Windows側ADBクライアントの`server-status`もWSLのLinux ADBサーバーを返した。設定を変更せず、次の方法でDebug実行できることを確認した。別のネットワーク構成でも同様に動くとは断定しない。

```bash
export PATH="$HOME/develop/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
"$ANDROID_HOME/platform-tools/adb" devices -l
flutter --no-version-check run --debug --no-pub --device-id emulator-5554 --host-vmservice-port=0
```

検証時は`ORG_GRADLE_PROJECT_android.builder.sdkDownload=false`もプロセス内で設定し、SDKの自動追加を無効にした。`--host-vmservice-port=0`で空いているポートを選び、VM Serviceの既定の認証を維持した。`--disable-service-auth-codes`や外部アドレスへバインドする設定は使わない。

起動後、ターミナルの`r`でHot Reload、`R`でHot Restart、`q`でアプリとDebugセッションを終了する。依存設定やアプリの初期化処理の変更など、Hot Reloadだけでは反映されない場合はHot Restartを使う。

#### APKを介した実行（前回確認済みの代替手順）

WSLでAPKをビルドし、Windowsから読める検証用フォルダへAPKだけをコピーする。今回のコピー先は`%USERPROFILE%\project\flutter\issue-1-validation\app-debug.apk`。コピー前後のSHA-256一致を確認した。ソースコードや`.dart_tool`・`build`全体は共有しない。

Windows PowerShellで、起動済みエミュレーターへ次のようにインストール・起動する。

```powershell
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
& $adb devices -l
$apk = Join-Path $env:USERPROFILE 'project\flutter\issue-1-validation\app-debug.apk'
& $adb -s emulator-5554 install -r $apk
& $adb -s emulator-5554 shell am start -W -n com.example.yumemi_app/.MainActivity
```

`emulator-5554`は起動時に変わる可能性があるため、毎回`devices`で確認する。デバッグAPKのインストール先はエミュレーターで、実機の確認はしていない。

### 追加検証：ライセンス・Debug・Hot Reload・Hot Restart

確認日：2026-11-18。Issue [#1](https://github.com/snow-naka/yumemi-flutter-codecheck/issues/1)の本文を読み取り、完了条件と照合した。Issue自体は更新していない。

#### Android SDKとライセンス

`android/local.properties`の`sdk.dir`、診断時の`ANDROID_HOME`、`flutter doctor -v`が、いずれも`$HOME/Android/Sdk`を示すことを確認した。WSL用FlutterとDartをPATHの先頭へ指定すると、Flutter SDK自体の診断は正常だった。

SDK管理ツールは「8件中7件が未同意」と報告した。未同意対象は次のとおり。

- `android-googletv-license`
- `android-googlexr-license`
- `android-sdk-arm-dbt-license`
- `android-sdk-preview-license`
- `google-gdk-license`
- `microxr-sysimage-license`
- `mips-android-sysimage-license`

対象名を確認するため一覧の閲覧にだけ進み、7件の`Accept?`にはすべて`n`を送信した。確認前後の`licenses/`内ファイルのSHA-256一覧が同一で、同意内容は変更していない。

インストール済みのPlatform Tools、Build Tools 36.0.0、Platform 36、NDK 28.2.13676358、CMake 3.22.1の`package.xml`は、いずれも`android-sdk-license`を参照している。このライセンスは今回の未同意7件には含まれなかった。追加SDK向けの未同意と、現在使う構成のビルド・Debug成功を区別する。全7件への同意が今回の実行に必要だったとは判断しない。

同意操作が必要な場合は、ユーザー自身がWSLの対話ターミナルで以下を実行し、各対象の条文を確認して判断する。自動同意のパイプは使わない。

```bash
export PATH="$HOME/develop/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  "$HOME/develop/flutter/bin/flutter" --no-version-check doctor --android-licenses
```

最後の`env -u`は今回診断を妨げた空のプロキシ値への対応。この環境での手順であり、実際にプロキシ接続を必要とする別環境へ無条件に適用しない。操作後は同じ環境指定で`flutter doctor -v`を再実行する。今回、利用許諾への同意は行っていない。

#### 端末認識とDebug接続

- Linux版ADBの`devices -l`が`emulator-5554`を`device`として認識。
- WSLの`flutter doctor -v`も同じAndroidエミュレーター（Android 17 / API 37 / x86_64）を認識。
- WSLからの`flutter run --debug --no-pub`でビルド・インストール・起動・ファイル同期に成功し、対話コマンドを利用できた。
- 認証付きDart VM Serviceへの接続に成功。URLの認証用コードは資料へ記載しない。
- `ss`でADBサーバー、ADBのVM Service転送、FlutterのVM Service/DDSのホスト側待受を確認。いずれも`127.0.0.1`に限定されていた。ポート番号は実行ごとに変わる。
- `adb -a`、`0.0.0.0`へのバインド、ルーターのポート転送、Windowsファイアウォール・アプリケーション制御ポリシーの変更は行っていない。

#### Hot ReloadとHot Restart

1. 初期画面の加算ボタンを押し、カウンター1の表示を確認。
2. 検証用に`lib/main.dart`の画面タイトルだけを一時変更。
3. `r`を送信。1ライブラリを392msでHot Reloadでき、タイトルが変更されてもカウンターは1のまま保持された。
4. `main.dart`を検証前のバイト列へ復元し、SHA-256一致を確認。
5. `R`を送信。1,442msでHot Restartでき、元のタイトルとカウンター0の表示を確認。
6. `q`でDebugセッションとアプリを終了。検証用のコード変更は残していない。VM Serviceのホスト側待受が終了したことを確認し、終了後に残った検証用ADB転送だけを個別解除した。ADBサーバーはループバック待受のまま維持した。

各段階の画面はスクリーンショットを目視した。今回の検証でHot Reload・Hot Restartの接続失敗は起きず、ADBやVM Serviceの外部公開による回避も不要だった。最初の起動コマンドで真偽フラグへ値を渡したCLIエラーが1回あったが、認証無効化フラグを取り除き、既定の認証を維持して再実行した。

#### Windows版Dartの影響

Windows版Dartがアプリケーション制御ポリシーで拒否される現象は前回確認済み。ただし、どのセキュリティ機能・規則が拒否したかの詳細は未特定で、特定製品や機能の問題と断定しない。

今回、Linux版Dart・Flutter・GradleでAndroidのビルド、Debug起動、Hot Reload、Hot Restartまで成功したため、このWSL開発経路にはWindows版Dartを必要としない。Windows側は既存エミュレーターとADBを使う。WSLでWindows側SDKを誤って選ぶと影響し得るため、上記のPATH指定を続ける。WindowsネイティブでFlutter開発する経路の問題まで解消したとは扱わない。

#### Issue #1の完了条件の評価

| Issueの完了条件 | 評価 | 根拠・残課題 |
| --- | --- | --- |
| Flutter SDKとDartのバージョンを確認できる | 達成 | WSL Flutter 3.50.0 / Dart 3.14.0を確認 |
| Android開発に必要な環境が正常である | 達成（既知の制約あり） | ビルド・直接Debug・Hot Reload・Hot Restartは成功。今回不要な追加SDK向け7件の未同意警告は、ユーザー判断で既知の制約として維持。全ライセンス同意済みとは記録しない |
| Androidエミュレーターまたは実機を認識できる | 達成 | WSLのADBとFlutterがWindowsエミュレーターを認識 |
| Flutterの初期アプリが起動する | 達成 | WSLからのDebug起動と表示を確認 |
| flutter analyzeが成功する | 達成 | コミット前に`flutter analyze --no-pub`を再実行し、問題なし。検証用コード変更は完全復元 |
| flutter testが成功する | 達成 | コミット前に`flutter test --no-pub`で全テストを再実行し、1件成功。テストは変更せず |
| 既存README・設計資料を維持できている | 達成 | 既存資料を保持し、環境に応じた更新を残している。ルート.gitignoreとPRテンプレートも維持 |

2026-11-18、ユーザーはIssue #1に必要な機能面の検証を完了したと判断した。上記7条件は今回の開発範囲で満たしている。今回使わない追加SDK向けの未同意7件は既知の制約として維持し、追加同意や診断警告の消去を完了条件に加えない。Windows版Dartの起動拒否も未解決だが、検証済みWSL開発経路の妨げにはならない。Draft PRでレビューし、mainへのマージ前はIssueをCloseしない。

### 既知の制約と今回の対象外

- 未同意7件は今回の開発に不要な追加SDK向けとして維持する。将来それらを使う場合の確認手順は上記。今回、追加同意・ライセンスファイルの書き換えは行わない。
- Windows版Dartの起動拒否の詳細な規則は未特定。WSL版SDKを明示し、Windowsのセキュリティ機能は変更しない。
- Chrome・Linuxデスクトップは今回のAndroid確認の対象外で、不足ツールを追加していない。
- iOS・実機のビルドと起動は未検証。今回のAndroidエミュレーターでの成功と分ける。
- Riverpodの導入と基礎確認、検索・詳細の実装は次の段階。READMEの段階0にはRiverpodの基礎確認も含まれるため、Issue #1と段階0全体の完了を同一視しない。

検証時の一時的なソース変更は復元済み。環境構築の初期アプリ・設定・関連文書を`feature/1-setup-flutter`へコミットし、Issue #1に対応するDraft PRでレビューする。追加ライセンス同意・セキュリティ設定変更・検索や詳細の実装・mainへのマージは今回行わない。

## 7. SDK更新の履歴（2026-11-24）

公式課題の最新安定版使用方針に合わせ、WSL側のFlutter SDKを更新した。

| 項目 | 更新前 | 更新後 |
|---|---|---|
| Flutter | 3.50.0 | 3.50.1 |
| Dart | 3.14.0 | 3.14.0 |
| Framework revision | ab2912035e | ae9b586f34 |
| Channel | stable | stable |

### 検証結果（SDK更新時点）

- `flutter pub get --enforce-lockfile`：成功
- `flutter gen-l10n`：成功、生成コードの差分なし
- `flutter analyze`：問題なし
- `flutter test`：全307件成功
- Android Release APKのビルド：成功（52.7MB）
- Androidエミュレーターへの上書きインストール：成功

アプリ本体のソースコードや依存パッケージを変更することなく、SDKを更新できた。

GitHub ActionsのFlutter SDK指定も3.50.1へ変更した。

### Android開発環境

- 最小対応Android API：24
- Target SDK：36
- Compile SDK：36
- Java：OpenJDK 17
- Gradle：9.5.0

Android SDKの一部ライセンスに関する警告は残っていたが、Releaseビルドは成功した。このSDK更新の記録では、別途の追加ライセンス承認や追加の環境変更は行っていない。

Release APKは開発用のDebug署名鍵を使用しており、正式なストア配布用ではなく検証用の成果物として扱う。

以上はSDK更新作業時点の結果である。その後のIssue数取得方式・外観改善などの検証結果は第5節および[AI利用記録](ai-notes.md)を参照する。

## 8. 関連資料

- [README](../README.md)：現在の機能・利用方法・最終検証結果
- [現行設計書](architecture.md)：現在の仕様と設計判断
- [AI利用記録](ai-notes.md)：開発中の判断・レビュー・検証履歴
- [Riverpod導入と基礎確認](riverpod-basics.md)：導入当時の互換性・基礎APIの検証
- [スケルトン最終検証記録](skeleton-final-verification.md)：Phase 1でのAndroid操作・最小CIの検証
