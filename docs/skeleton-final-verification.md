# 段階5：CI整備・Android実操作・最終検証

> **履歴資料（2026-11-25整理）**：2026年11月18日のIssue #3・段階5におけるスケルトンの最終検証・初期CIの履歴資料です。 本文の仕様・未実装・未検証・今後の作業・Gitの状態などは当時の記録であり、現在の状態を示すものではありません。現行の機能・利用方法は[README](../README.md)、現行の技術設計は[architecture.md](architecture.md)を参照してください。個人環境のパスは一般化しています。

2026-11-18、Issue #3。対象は`feature/3-skeleton`、基準コミットは`686462ad16aad83e0ded05e306fd313cd7974aea`（段階4）。初回のローカル検証後、ユーザーの許可を受けて段階5をコミット・Pushし、Draft PR #4を作成した。GitHub Actionsの結果は末尾に追記する。mainへのマージ・Issueの更新は行っていない。

## 対象コードとログ

アプリ・テスト・依存設定は段階4から変更していない。`lib/`・`test/`のDart20ファイルと`pubspec.yaml`・`pubspec.lock`・`analysis_options.yaml`、計23件を検証対象としてハッシュ照合した。

- コードマニフェストのSHA-256：`ad8fe81229f65b8a2104530c5f40a9db3c7a4d0de918508ccee1a6c8473063ba`（段階4と一致）。各ファイルのSHA-256と相対パスをパス順に並べたUTF-8・LFの一覧。
- CI設定：`.github/workflows/flutter.yml`。SHA-256：`67739d2ed8a0269fa6a1f87b21778e21b2497391a5d756b71c5bd8ee2f50c9e6`。
- ローカル保存先：`log/issue3/step5/20261118-192114+0900/`。ルート`.gitignore`の`/log/`で全体を除外する。ログ・スクリーンショット・XML・JSON・PR本文案はGitへ登録しない。
- `code-sha256.txt`に対象コード、`local-verification.json`にローカル実行コマンド・時刻・終了コード・ログハッシュ、`workflow-validation.json`にCI設定の確認結果、`android-verification.json`にAndroidの検証結果とAPKハッシュを記録した。
- 既存の段階2〜4のログ9件は上書きせず、作業前とのハッシュ一致を確認した。

## Androidでの実操作

既存のWSL Flutter 3.50.0 / Dart 3.14.0、Android SDK `$HOME/Android/Sdk`を利用した。[環境構築時の手順](environment.md)を引き継ぎ、Windowsの既存AVD `Medium_Phone_API_37.0`を起動し、WSLのADBで`emulator-5554`、API 37 / x86_64、起動完了`1`を確認した。SDK追加・ライセンスへの追加同意・Windowsセキュリティ設定変更は行っていない。

WSLから以下のDebug APKビルドに成功した（18.6秒）。SDKの自動追加は無効にし、依存取得は行わない。

```bash
env PATH=$HOME/develop/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  ANDROID_HOME=$HOME/Android/Sdk \
  'ORG_GRADLE_PROJECT_android.builder.sdkDownload=false' \
  $HOME/develop/flutter/bin/flutter --no-version-check build apk \
    --debug --no-pub --target-platform android-x64

$HOME/Android/Sdk/platform-tools/adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
$HOME/Android/Sdk/platform-tools/adb -s emulator-5554 shell am start -W -n com.example.yumemi_app/.MainActivity
```

インストールは`Success`、起動は`Status: ok`。アプリへの入力・選択・戻る操作はWSLのADB経由で実行し、実画面のスクリーンショットとuiautomatorのXMLを保存した。FlutterのWidgetテストだけによる確認とは分ける。今回はAPKを介した起動で、`flutter run`の接続・Hot Reloadの再検証は行っていない。

| 操作 | 確認結果 | 主な画面・XML記録 |
| --- | --- | --- |
| 起動 | 未検索の入力案内を表示 | `02-search-initial.*` |
| `example`で検索 | flutter-sample / riverpod-sampleの2件を表示 | `04-search-results.*` |
| 入力欄を未送信の`draft`へ編集 | 送信済み検索語は`example`、2件の一覧を維持 | `05-search-draft.png`、`07-return-preserved.xml` |
| flutter-sampleを選択 | Star120・Watcher8・Fork12・Open Issue＋PR7の詳細を表示 | `06-detail-success.*` |
| 戻る | 入力`draft`・送信語`example`・2件の一覧を保持 | `07-return-preserved.*` |
| riverpod-sampleを選択 | 初回は詳細失敗、再試行ボタン、言語未指定を表示。未取得の件数は0表示しない | `08-detail-failure.*` |
| 詳細の再試行 | 詳細だけ成功し、取得済みの各件数0を表示 | `09-detail-retry-success.*` |
| 再試行後に戻る | 入力`draft`・送信語`example`・元の一覧を保持 | `10-return-after-retry.*` |
| `empty`で検索 | 正常0件を表示 | `11-search-empty.*` |
| `incomplete`で検索 | 2件の一覧と不完全な結果の注意を表示 | `12-search-incomplete.*` |
| `error`で検索 | 検索失敗と再試行ボタンを表示 | `13-search-error.*` |

通常Fakeは2件で一覧を大きくスクロールしないため、非ゼロのスクロール位置保持、短時間の取得中表示、二重送信防止、破棄後の応答の競合は自動テストの検証を根拠とする。Android実操作でこれらをすべて再現したとは扱わない。

検証用AVDは`-no-snapshot-save`で起動し、終了後は今回のアプリを停止した。エミュレーターへの終了要求は`KO: unknown command`となり、終了確認時にも端末が稼働していたため、そのまま残している。強制終了は行っていない。ホストへのVM Service転送は使わず、ADBの転送一覧は前後とも空。ADBサーバーは既存手順どおりループバック接続を使用した。実機・iOSは未検証。

WSLの制限付き実行ではADBの待受開始が拒否されたため、許可された通常環境で再実行した。Windows PowerShellに渡る`PATHEXT`が`.CPL`のみだったため、端末一覧の取得時にはそのプロセス内だけ`.EXE`等を補った。永続設定は変更しておらず、Windows版Dartの既知の起動拒否の原因を特定・解消したとは扱わない。

## 最小CI

[Workflow](../.github/workflows/flutter.yml)はUbuntu 24.04の1ジョブで、以下を順に実行する。

1. `actions/checkout@v6`でソースを取得する。権限は`contents: read`、認証情報の永続化は無効。
2. `subosito/flutter-action@v2`でローカルに合わせFlutter **3.50.0 stable**を用意する。最新版への自動追従はしない。
3. SDKバージョンを表示し、`flutter pub get --enforce-lockfile`でlockfileの依存を取得する。
4. `flutter analyze --no-pub`、`flutter test --no-pub --reporter expanded`、`dart format --output=none --set-exit-if-changed lib test`を実行する。

`main`・`feature/**`へのPushと、`main`向けPRで起動する。現在のブランチのPushだけでも試せ、PRではmainとの組み合わせを確認できる。タイムアウトは15分。まず解析・テスト・整形に絞り、Androidビルド・エミュレーター・配布・追加パッケージ・独自のキャッシュ設定は増やしていない。通常のGitHubホストランナーで、SDKとlockfileで指定した既存依存を取得する構成。

ローカルでは既存のPyYAMLでYAMLを読み取り、イベント・SDK指定・Actionsの入力名を確認し、各runコマンドを`bash -n`で構文確認した。公式Flutterタグ3.50.0と、Action実装が利用する現行の配布マニフェストの両方で、ローカルSDKのコミット`ab2912035e160d9cad6306df307576da6128ebdb`、Flutter3.50.0 / Dart3.14.0との一致を確認した。

初回のローカル検証時点ではGitHub Actions自体は未実行だった。その後のPush・PR実行でSDKセットアップ・lockfileによる依存取得も成功した。ローカル確認とGitHubでの確認を分け、対象コミットとRun URLは末尾に記録する。

配布情報の初回確認では旧パスのURLへアクセスしてHTTP404となった。Action v2の`setup.sh`を読み取り、現在の`https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`で上記の配布情報を確認できた。旧URLの失敗と、現行URLでの成功はローカルログに分けて残す。CI設定の取得先を独自に変更する必要はなかった。

確認元：[checkout v6定義](https://raw.githubusercontent.com/actions/checkout/v6/action.yml)、[flutter-action v2定義](https://raw.githubusercontent.com/subosito/flutter-action/v2/action.yaml)、[SDK取得処理](https://raw.githubusercontent.com/subosito/flutter-action/v2/setup.sh)、[Flutter 3.50.0タグ](https://github.com/flutter/flutter/tree/3.50.0)。取得した定義と確認結果はローカルログにも保存した。

## ローカル最終検証

2026-11-18 19:29:55〜19:30:04 JST、上記と同じコードで実行した。PATHはビルド例と同じWSL SDK指定。次の表の`flutter`は`$HOME/develop/flutter/bin/flutter --no-version-check`、`dart`は`$HOME/develop/flutter/bin/cache/dart-sdk/bin/dart`を表す。完全なコマンドと開始終了時刻は`local-verification.json`に保存した。

| コマンド | 結果 | 終了コード | ローカルログ |
| --- | --- | --- | --- |
| `flutter --version --machine` | Flutter3.50.0 / Dart3.14.0 | 0 | `sdk-version.json` |
| `flutter pub get --offline --enforce-lockfile` | 既存キャッシュで成功、依存ファイル変更なし | 0 | `pub-get-offline.log` |
| `flutter test --no-pub --reporter expanded` | 既存35件＋詳細12件、全47件成功 | 0 | `test-results.log` |
| `flutter analyze --no-pub` | No issues found | 0 | `analyze-results.log` |
| `dart format --output=none --set-exit-if-changed lib test` | 全20ファイル、0 changed | 0 | `format-results.log` |

## Issue #3の完了条件との照合

[Issue #3](https://github.com/snow-naka/yumemi-flutter-codecheck/issues/3)の本文を今回読み取り、7条件と照合した。Issueのチェック欄は変更していない。

| 完了条件 | 判定 | 根拠 |
| --- | --- | --- |
| 検索中・結果あり・0件・不完全結果・失敗を確認できる | 達成 | 検索Controller・WidgetテストとAndroidの結果・0件・不完全結果・失敗表示 |
| 検索中の二重送信が防止される | 達成 | Controllerとボタン・キーボード送信の既存自動テスト |
| 詳細画面で取得中・成功・失敗・明示的な再試行を確認できる | 達成 | 完了制御テスト、Androidの成功・失敗・再試行 |
| 詳細から戻った際に検索語・結果一覧・スクロール位置が保持される | 達成 | 長い一覧の非ゼロ位置を含むWidgetテスト。Androidでは送信語・未送信入力・一覧の保持を確認 |
| Fakeを使用した自動テストが成功する | 達成 | 全47件成功、GatewayはFakeのまま |
| flutter analyzeとflutter testが成功する | 達成 | 上記の再実行はいずれも終了コード0 |
| CIで解析・テストを実行できる | 達成 | Push・PRで実行され、解析・全47テスト・整形が成功。対象コミット・Run URLは末尾を参照 |

ローカルの6条件に加え、GitHubでのCI成功により7条件を確認した。Phase 1の機能・検証の条件を満たし、Draft PRでのレビューとmainへの取り込みは未完了として分ける。IssueはOpenのまま維持する。

## 既知の課題・今回の対象外

検索で想定外の例外後にSearchLoadingが残る問題は[検索記録](search-skeleton.md)のとおり未解決。自動再試行は暫定無効で、[詳細記録のPhase 2検討事項](detail-skeleton.md#phase-2の検討事項未決定)にある要求共有・キャッシュと期限・再表示時の取得条件・実HTTPキャンセル・レート制限・実画像表示は未決定のまま。古い応答が現在の詳細画面を誤って上書きしない安全条件を維持する。

実GitHub APIのGateway、レート制限処理、追加機能、実機・iOSは今回実装・検証していない。アプリはFakeで動作し、Issue本文・CI定義・SDKタグの照合に用いた読み取り通信とは分けて記録する。

## レビュー後のPush・PR確認手順（初回検証時の計画）

1. 今回のCIと関連資料の差分をレビューし、許可後に段階5としてコミットする。アプリ・依存ファイル・ログを追加する変更はない。
2. `git push -u origin feature/3-skeleton`を実行する。Push時のWorkflowを`gh run list --workflow flutter.yml --branch feature/3-skeleton`で選び、`gh run watch <run-id> --exit-status`で完了を確認する。失敗時は`gh run view <run-id> --log-failed`を読む。
3. 今回の確認時点で、このブランチにOpenのPRはない。作成前に再確認し、あれば既存PRを利用する。なければ下記のDraft PRを作る。本文案はローカルに用意し、PushでのCI結果を追記してから使用する。

```bash
gh pr create --draft --base main --head feature/3-skeleton \
  --title 'feat: implement Fake repository search and detail skeleton' \
  --body-file log/issue3/step5/20261118-192114+0900/pr-body.md
```

4. `gh pr checks <PR番号> --watch`でPR側の解析・全テスト・整形の成功も確認する。mainとの組み合わせと対象コミットを確認し、結果・URLを検証記録とPRへ反映する。CI成功後もレビュー完了とマージは別の判断とする。

本文案はPRテンプレートの目的・変更内容と理由・検証・AI利用に沿い、Issue #3全体の段階1〜5とPhase 2への持ち越しを説明する。初回検証時にはPR・コメントの投稿やIssueのCloseは行わず、その後の承認により以下のGitHub検証へ進んだ。


## GitHub Actionsの実行確認（2026-11-18追記）

ユーザーの承認後、段階5の5ファイルを`6140119be6287f0c00b041b14ad5bb708d8606c3`（`ci: add Flutter checks and record skeleton validation`）にコミットし、`feature/3-skeleton`をoriginへPushした。[Draft PR #4](https://github.com/snow-naka/yumemi-flutter-codecheck/pull/4)はmain向けで、本文の`Closes #3`によりIssue #3と関連づけた。PRはDraft、IssueはOpen、mainは未変更。

| イベント | 対象headコミット | 結果 |
| --- | --- | --- |
| [Push Run 44296940825](https://github.com/snow-naka/yumemi-flutter-codecheck/actions/runs/44296940825) | `6140119be6287f0c00b041b14ad5bb708d8606c3` | success |
| [PR Run 44297054048](https://github.com/snow-naka/yumemi-flutter-codecheck/actions/runs/44297054048) | `6140119be6287f0c00b041b14ad5bb708d8606c3` | success |

どちらもGitHubホストランナーでSDKセットアップ、固定依存取得、解析、全47テスト、整形20ファイル・0 changedの成功を実ログで確認した。CI失敗やテストの無効化は発生していない。CLIの`gh run watch --exit-status`も両実行で終了コード0だった。

実行情報と取得したログは`log/issue3/step5/20261118-204100+0900-github/`へ新規保存した。既存のローカル検証ログは維持し、新しいログも`/log/`によりGit管理対象外。

この結果追記は資料だけの変更で、アプリ・テスト・依存設定・Workflowは上記の検証対象と同一。資料更新コミットもPushし、その最新headに対するCI・Draft状態・残存変更はPR本文とローカルの`publication.json`へ記録する。コミット内に自身のコミットIDを含めるための追加更新は行わない。
