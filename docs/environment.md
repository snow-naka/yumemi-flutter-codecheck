# 開発環境と環境構築の検証記録

確認日：2026-11-18。対象ブランチ：`feature/1-setup-flutter`。

## 開発環境の選択

- 作業リポジトリ：`/home/snow_/projects/flutter/yumemi-flutter-codecheck`
- 編集・Git・依存解決・解析・テスト・Androidビルド：WSL2 / Ubuntu 24.04。
- Flutter SDK：`/home/snow_/develop/flutter`（3.50.0 stable）。同梱Dart：3.14.0。
- Android SDK：`/home/snow_/Android/Sdk`。Platform 36、Build Tools 36.0.0、NDK 28.2.13676358、Platform Tools 37.0.1。
- Java：WSLのOpenJDK 17.0.21.0.3。
- Windows：Android Studio 2026.2.2系、Android Emulator 37.2.13、ADB 37.0.1。SDKは`C:\Users\snow_\AppData\Local\Android\Sdk`。
- 仮想端末：`Medium_Phone_API_37.0`（x86_64）。確認時のADB識別子は`emulator-5554`。

Windows版Dartは実起動時に「アプリケーション制御ポリシーによってこのファイルがブロックされました」となり、実行できなかった。ポリシーを変更せずWSL版を使用する。WindowsのADBとエミュレーターは実行可能。Windows側でFlutterを実行したり、ソースを複製してビルドしたりする構成にはしない。

## SDKの使い分け

今回の実行シェルでは`flutter`・`dart`がWindows側を指していた。WSLでの実行時は、次のようにWSL用SDKを明示する。以下の環境変数はそのターミナル内だけの設定で、ユーザーのシェル設定ファイルは変更していない。

```bash
export PATH="/home/snow_/develop/flutter/bin:$PATH"
export ANDROID_HOME="/home/snow_/Android/Sdk"
command -v flutter dart
flutter --version
```

Androidの診断では、空の`HTTP_PROXY`・`HTTPS_PROXY`をSDK管理ツールが解釈できず失敗した。今回の診断とSDK管理コマンドに限り、空のプロキシ変数を`env -u`で除外して再実行した。OSやユーザーの永続設定は変更していない。

## 初期アプリの取り込み

別フォルダ`yumemi_app`の初期カウンターアプリから、`lib/`・`test/`・`android/`・`ios/`・`.metadata`・`analysis_options.yaml`・`pubspec.yaml`・`pubspec.lock`を選択して取り込んだ。生成物・キャッシュ・元のGit管理情報・ローカルSDK設定・元の資料はコピーしていない。既存のルート`.gitignore`とPRテンプレートは維持した。READMEは環境の現状に合わせて更新した。

アプリ名は既存の`yumemi_app`、Androidの識別子は`com.example.yumemi_app`を維持している。検索・詳細の骨組みやRiverpodはまだ実装していない。

## Material Designについての見直し

[公式課題](https://github.com/yumemi-inc/flutter-engineer-codecheck#デザイン)は「マテリアルデザインに準拠すること」を要求し、import先は指定していない。

[Flutter公式material_ui](https://github.com/flutter/packages/tree/main/packages/material_ui)はMaterial Designの公式ライブラリ。現在のSDKの`packages/flutter/lib/material.dart`には`material_ui`への移行を案内する非推奨指定があり、SDKの生成テンプレートも`material_ui`を使用している。

このため以前の「独自UIライブラリを避けて標準Materialへ切り替える」という理解を訂正し、初期サンプルの`material_ui`を維持する。`pubspec.yaml`・`pubspec.lock`は元のサンプルと同一。新しいアプリ用パッケージは追加していない。

## 実行した確認

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

## Android上での実行方法

### WSLからの直接Debug実行（追加検証済み）

今回の環境ではWSLの`.wslconfig`に`networkingMode=mirrored`が設定され、WSLのLinux ADBからWindowsエミュレーターを認識できた。Windows側ADBクライアントの`server-status`もWSLのLinux ADBサーバーを返した。設定を変更せず、次の方法でDebug実行できることを確認した。別のネットワーク構成でも同様に動くとは断定しない。

```bash
export PATH="/home/snow_/develop/flutter/bin:$PATH"
export ANDROID_HOME="/home/snow_/Android/Sdk"
/home/snow_/Android/Sdk/platform-tools/adb devices -l
flutter --no-version-check run --debug --no-pub --device-id emulator-5554 --host-vmservice-port=0
```

検証時は`ORG_GRADLE_PROJECT_android.builder.sdkDownload=false`もプロセス内で設定し、SDKの自動追加を無効にした。`--host-vmservice-port=0`で空いているポートを選び、VM Serviceの既定の認証を維持した。`--disable-service-auth-codes`や外部アドレスへバインドする設定は使わない。

起動後、ターミナルの`r`でHot Reload、`R`でHot Restart、`q`でアプリとDebugセッションを終了する。依存設定やアプリの初期化処理の変更など、Hot Reloadだけでは反映されない場合はHot Restartを使う。

### APKを介した実行（前回確認済みの代替手順）

WSLでAPKをビルドし、Windowsから読める検証用フォルダへAPKだけをコピーする。今回のコピー先は`C:\Users\snow_\project\flutter\issue-1-validation\app-debug.apk`。コピー前後のSHA-256一致を確認した。ソースコードや`.dart_tool`・`build`全体は共有しない。

Windows PowerShellで、起動済みエミュレーターへ次のようにインストール・起動する。

```powershell
$adb = 'C:\Users\snow_\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb devices -l
& $adb -s emulator-5554 install -r 'C:\Users\snow_\project\flutter\issue-1-validation\app-debug.apk'
& $adb -s emulator-5554 shell am start -W -n com.example.yumemi_app/.MainActivity
```

`emulator-5554`は起動時に変わる可能性があるため、毎回`devices`で確認する。デバッグAPKのインストール先はエミュレーターで、実機の確認はしていない。

## 追加検証：ライセンス・Debug・Hot Reload・Hot Restart

確認日：2026-11-18。Issue [#1](https://github.com/snow-naka/yumemi-flutter-codecheck/issues/1)の本文を読み取り、完了条件と照合した。Issue自体は更新していない。

### Android SDKとライセンス

`android/local.properties`の`sdk.dir`、診断時の`ANDROID_HOME`、`flutter doctor -v`が、いずれも`/home/snow_/Android/Sdk`を示すことを確認した。WSL用FlutterとDartをPATHの先頭へ指定すると、Flutter SDK自体の診断は正常だった。

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
export PATH="/home/snow_/develop/flutter/bin:$PATH"
export ANDROID_HOME="/home/snow_/Android/Sdk"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  /home/snow_/develop/flutter/bin/flutter --no-version-check doctor --android-licenses
```

最後の`env -u`は今回診断を妨げた空のプロキシ値への対応。この環境での手順であり、実際にプロキシ接続を必要とする別環境へ無条件に適用しない。操作後は同じ環境指定で`flutter doctor -v`を再実行する。今回、利用許諾への同意は行っていない。

### 端末認識とDebug接続

- Linux版ADBの`devices -l`が`emulator-5554`を`device`として認識。
- WSLの`flutter doctor -v`も同じAndroidエミュレーター（Android 17 / API 37 / x86_64）を認識。
- WSLからの`flutter run --debug --no-pub`でビルド・インストール・起動・ファイル同期に成功し、対話コマンドを利用できた。
- 認証付きDart VM Serviceへの接続に成功。URLの認証用コードは資料へ記載しない。
- `ss`でADBサーバー、ADBのVM Service転送、FlutterのVM Service/DDSのホスト側待受を確認。いずれも`127.0.0.1`に限定されていた。ポート番号は実行ごとに変わる。
- `adb -a`、`0.0.0.0`へのバインド、ルーターのポート転送、Windowsファイアウォール・アプリケーション制御ポリシーの変更は行っていない。

### Hot ReloadとHot Restart

1. 初期画面の加算ボタンを押し、カウンター1の表示を確認。
2. 検証用に`lib/main.dart`の画面タイトルだけを一時変更。
3. `r`を送信。1ライブラリを392msでHot Reloadでき、タイトルが変更されてもカウンターは1のまま保持された。
4. `main.dart`を検証前のバイト列へ復元し、SHA-256一致を確認。
5. `R`を送信。1,442msでHot Restartでき、元のタイトルとカウンター0の表示を確認。
6. `q`でDebugセッションとアプリを終了。検証用のコード変更は残していない。VM Serviceのホスト側待受が終了したことを確認し、終了後に残った検証用ADB転送だけを個別解除した。ADBサーバーはループバック待受のまま維持した。

各段階の画面はスクリーンショットを目視した。今回の検証でHot Reload・Hot Restartの接続失敗は起きず、ADBやVM Serviceの外部公開による回避も不要だった。最初の起動コマンドで真偽フラグへ値を渡したCLIエラーが1回あったが、認証無効化フラグを取り除き、既定の認証を維持して再実行した。

### Windows版Dartの影響

Windows版Dartがアプリケーション制御ポリシーで拒否される現象は前回確認済み。ただし、どのセキュリティ機能・規則が拒否したかの詳細は未特定で、特定製品や機能の問題と断定しない。

今回、Linux版Dart・Flutter・GradleでAndroidのビルド、Debug起動、Hot Reload、Hot Restartまで成功したため、このWSL開発経路にはWindows版Dartを必要としない。Windows側は既存エミュレーターとADBを使う。WSLでWindows側SDKを誤って選ぶと影響し得るため、上記のPATH指定を続ける。WindowsネイティブでFlutter開発する経路の問題まで解消したとは扱わない。

### Issue #1の完了条件の評価

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

## 既知の制約と今回の対象外

- 未同意7件は今回の開発に不要な追加SDK向けとして維持する。将来それらを使う場合の確認手順は上記。今回、追加同意・ライセンスファイルの書き換えは行わない。
- Windows版Dartの起動拒否の詳細な規則は未特定。WSL版SDKを明示し、Windowsのセキュリティ機能は変更しない。
- Chrome・Linuxデスクトップは今回のAndroid確認の対象外で、不足ツールを追加していない。
- iOS・実機のビルドと起動は未検証。今回のAndroidエミュレーターでの成功と分ける。
- Riverpodの導入と基礎確認、検索・詳細の実装は次の段階。READMEの段階0にはRiverpodの基礎確認も含まれるため、Issue #1と段階0全体の完了を同一視しない。

検証時の一時的なソース変更は復元済み。環境構築の初期アプリ・設定・関連文書を`feature/1-setup-flutter`へコミットし、Issue #1に対応するDraft PRでレビューする。追加ライセンス同意・セキュリティ設定変更・検索や詳細の実装・mainへのマージは今回行わない。
