# 段階4：詳細画面と画面遷移

2026-11-18、Issue #3。段階2のGateway・Fakeと段階3の検索を利用し、検索結果の選択から詳細表示、手動再試行、一覧へ戻る操作を実装した。レビュー後に最終検証を行い、段階4の実装・テスト・関連資料を一つの目的でコミットする。実通信・CI・依存関係変更・Push・PR作成は対象外。

## 部品と状態の流れ

| ファイル | 責務 |
| --- | --- |
| `lib/features/detail/repository_detail_provider.dart` | `RepositoryKey`ごとの非同期取得。`FutureProvider.autoDispose.family`で取得中・成功・失敗を公開 |
| `lib/features/detail/repository_detail_screen.dart` | 選択時の概要、取得状態、成功時の詳細、明示的な再試行を表示 |
| `lib/features/search/search_screen.dart` | 選択した概要を引数にして詳細画面をpush。検索画面をスタックに維持 |

```text
SearchScreen ─ watch → SearchController ─ read ─┐
                                              ├→ githubRepositoryGatewayProvider → Fake
RepositoryDetailScreen ─ watch → 詳細Provider ─ watch ─┘
                                  ↑ RepositoryKeyごと
```

共通の取得窓口だけを参照し、検索Providerと詳細Providerは互いの状態に依存しない。詳細の完了・失敗・再試行は検索を更新せず、新しい検索も既存の詳細を再取得しない。Gatewayを外側のProviderScopeから差し替える既存構成を維持した。

画面の`ref.watch(repositoryDetailProvider(key))`が取得を開始し、`AsyncValue`の変化で画面が再描画される。検索とは異なり、操作履歴を含む独自4状態は追加せず、1件の非同期取得をFutureProviderで表す。同じ値のキーは同じProviderを共有し、異なるキーは独立する。

## 表示と再試行

- 取得中・失敗時は、選択時の名前・所有者・言語と代替アイコンを表示する。未取得の件数を0にせず、成功後にStar数・Watcher数・Fork数・Open Issue＋PR数を表示する。
- 成功後は名前・言語なども詳細応答の概要でそろえる。言語nullは「未指定」、取得済みの数値0は0として表示する。
- ApiFailureは利用者向け説明を表示する。その他の例外は通信エラーへ変換せず、詳細処理の問題として表示する。内部例外の文字列は表示しない。
- 失敗時の「再試行」で対象の詳細Providerだけを`ref.invalidate`する。購読中なので再取得が始まり、取得中表示へ戻る。待機中は再試行ボタンを表示しない。
- 再取得中にAsyncValueが前の値を保持していても、`isLoading`を優先し、前のエラーや件数を表示し続けない。
- アプリ全体の暫定設定に加え、詳細Providerにも`retry: (retryCount, error) => null`を設定する。外部ScopeでGatewayだけを差し替えても詳細の自動再試行は無効。

Fakeでは画像取得も行わず、ローカルの代替アイコンを使う。

## 戻る操作と生存期間

Navigator.pushで検索画面を残すため、TextEditingControllerの入力、SearchStateの送信済み検索語・結果、ScrollControllerの位置を保持できる。戻る操作は検索を呼ばない。詳細の情報で検索結果を書き換えない。

詳細Providerは最後の購読がなくなるとautoDisposeされる。通常は戻るアニメーション終了後に詳細画面が破棄され、その後Providerも破棄される。取得中に離れても、破棄後の応答は再表示した画面へ反映しない。FakeのFutureそのものをキャンセルする機構は追加していない。

一覧から開く際にも、選んだキーの詳細Providerだけをinvalidateする。autoDisposeの処理前に開き直す場合も含め、開くたびに取得する方針を明示する。検索状態は無効化しない。永続キャッシュやアプリ終了後の復元は設けない。

## 検証

FakeのdetailHandlerをCompleterで制御し、実時間の待機や外部通信を使わず、取得中・成功・失敗・破棄後の完了を確認する。通常のFakeシナリオによる検索→詳細失敗→手動再試行→戻る操作も確認する。

WSLの既存Flutter 3.50.0 / Dart 3.14.0で実行した。SDKの起動は`/home/snow_/develop/flutter/bin/flutter --no-version-check`を使用し、依存取得は`--no-pub`で行わない。

| コマンド | 結果 |
| --- | --- |
| `flutter test --no-pub test/detail/repository_detail_provider_test.dart` | 5件成功 |
| `flutter test --no-pub test/detail/repository_detail_screen_test.dart` | 7件成功 |
| `flutter test --no-pub --reporter expanded` | 既存35件＋詳細12件、全47件成功 |
| `flutter test --no-pub --reporter expanded test/detail` | 存在確認APIの修正後も12件成功 |
| `flutter analyze --no-pub` | 問題なし |

Providerテストでは、値が等しいキーによる要求共有、異なるキーの成功・失敗の分離、購読終了後の破棄、再取得中に古い成功が完了する場合、別の詳細取得中に古い失敗が完了する場合、詳細取得中の新しい検索を確認した。検索と詳細の状態・呼び出し回数を両方向で検証する。

Widgetテストでは、検索結果からの選択・取得中の概要表示、詳細応答での表示更新、失敗と手動再試行、自動再試行の無効化、戻る際の送信語・未送信入力・同一の検索状態・スクロール位置の保持、取得中と成功後の破棄・再表示、想定外例外の表示、通常Fakeでの失敗→成功と数値0・言語nullを確認した。

追加テストの初回実行では、遷移アニメーションの完了前に画面と破棄状態を確認して失敗した。表示準備中の詳細画面から遷移のAnimationを取得し、上限付きで完了を待つ補助処理へ整理した。通常Fakeの非同期再試行も完了後に表示を検証する。期待する状態や値は変更していない。解析で指摘されたテスト内の非推奨な`container.exists`は、導入済みRiverpodの実装を確認して`container.read(provider.exists)`へ置き換えた。

既存35件のテストファイル、pubspec.yaml・pubspec.lock、既存のローカルログは作業前とのハッシュ一致を確認した。ログ本体は変更せず、Git管理の対象にも追加していない。

### レビュー後の最終検証（2026-11-18）

最終変更後のコード全体に対し、19:08:22〜19:08:30（JST）に以下を再実行した。以前の全体実行と部分再実行を合わせた判定とは分け、この実行では同一のコードに対して全テスト・解析・整形チェックをそろえた。コード・テストの追加修正はなく、チェック中およびチェック後も以下の対象と一致することを確認する。

- 作業ブランチ：`feature/3-skeleton`。基準コミット：`98c9a0d47d3e48d58f1bc4bcd382dd470bb75fb7`（段階3）。この基準に段階4の変更を加えた作業ツリーを検証し、本記録と同じコミットに収める。
- 対象：`lib/`・`test/`配下の全Dartファイル20件と、`pubspec.yaml`・`pubspec.lock`・`analysis_options.yaml`の計23件。段階4のコード変更は詳細Provider・詳細画面・検索画面と詳細テスト2件。
- 対象の照合方法：相対パス順に並べた各ファイルの`SHA-256  相対パス`を1行ずつ記したUTF-8・LFのマニフェストを作成。マニフェスト自体のSHA-256は`ad8fe81229f65b8a2104530c5f40a9db3c7a4d0de918508ccee1a6c8473063ba`。
- 環境：既存のWSL用SDK。PATHは`/home/snow_/develop/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`。依存取得・依存設定変更は行っていない。

| 実行コマンド | 結果 | 終了コード | ローカルログ名 |
| --- | --- | --- | --- |
| `/home/snow_/develop/flutter/bin/flutter --no-version-check test --no-pub --reporter expanded` | 既存35件＋詳細12件、全47件成功 | 0 | `test-results.log` |
| `/home/snow_/develop/flutter/bin/flutter --no-version-check analyze --no-pub` | No issues found | 0 | `analyze-results.log` |
| `/home/snow_/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib test` | 20ファイル確認、変更必要なし（0 changed） | 0 | `format-results.log` |

詳細ログのローカル保存先：`log/issue3/step4/20261118-190738+0900-final/`。同フォルダの`code-sha256.txt`に対象23件のハッシュ、`verification.json`にコマンド・開始終了時刻・終了コード・ログハッシュ・対象コードの一致確認を記録した。コミット確定後は、そのIDとコミット内の対象コードとの照合結果も同JSONへ記録する。

全ログ・マニフェスト・JSONはルート`.gitignore`の`/log/`によりGit管理対象外。既存の段階2・3のログ4件は上書きせず、内容のハッシュ一致を確認した。

## 手元での確認と残る作業

起動後に`flutter`を検索して選ぶと、Star数120・Watcher数8の成功例を確認できる。`riverpod`を検索して選ぶと、そのFakeインスタンスでの最初の詳細取得は失敗し、「再試行」で数値0・言語未指定の詳細を確認できる。入力途中の別の語を残したまま詳細を開き、戻ると未送信の入力と元の結果を確認できる。

エラー種別ごとの再試行可否・回数・間隔・レート制限への対応はPhase 2まで未確定。現段階の詳細は明示的な手動再試行だけを提供する。Open Issue＋PRというFakeの項目を維持し、実通信でのIssue数の意味・取得方法の判断は保留する。

## Phase 2の検討事項（未決定）

Issue #3では、詳細画面を開くたびに新規取得する方式を暫定採用する。同じキーを同時に購読する間はFutureProviderが取得を共有するが、画面を開き直す操作では対象をinvalidateし、永続キャッシュは持たない。以下は実通信実装時に比較・検証する論点であり、現段階で方式を変更・確定しない。

| 論点 | Phase 2で確認・判断する内容 |
| --- | --- |
| 同一リポジトリの取得中リクエストの再利用 | 閉じてすぐ開き直した場合や複数の参照元がある場合に、未完了要求を共有するか新規発行するか。共有するなら要求の所有者・生存期間と、誰がキャンセルできるかを決める |
| 取得済みデータのキャッシュと有効期限 | キャッシュの要否、キー、保存場所、保持期間、上限、成功データと失敗の扱いを検討する。期限切れ時に旧データを表示しながら更新するかも判断する。アプリ終了後の永続化を採用したことにはしない |
| 詳細画面を開き直す際の再取得条件 | 毎回取得、未取得・期限切れのみ取得、利用者の更新操作などを比較する。キャッシュの鮮度、取得中要求の有無、認証条件の変更をどう扱うか明確にし、一覧を勝手に再検索しない条件を維持する |
| 画面を閉じた際の実HTTP要求のキャンセル | 採用するHTTPクライアントのキャンセル手段、Provider破棄との連携、要求共有時に他の参照先が残る場合の扱いを確認する。現在の古い応答の無視と実際の通信停止は別であり、HTTPキャンセルは未実装 |
| GitHub APIのレート制限と通信回数 | 同じ詳細の連続開閉・複数参照・再試行時の要求数を比較する。利用可能なレート制限情報と待機時間をどう反映するか検討し、キャッシュや要求共有による削減効果と鮮度の両方を評価する。キャンセルしても既に送信した要求の消費枠が戻るとは仮定しない |
| オーナーアイコンの実画像表示 | `avatarUrl`を表示に利用する方法、読込中・取得失敗時の代替アイコン、画像のキャッシュ・通信回数・テスト方法を検討する。画像だけの失敗で検索・詳細全体を失敗にしない。現在はローカルアイコンのみ |

**今後も維持する安全条件：古い取得結果が、現在表示中の詳細画面を誤って上書きしないこと。** キャンセルの成否だけに依存せず、破棄後の応答、同じリポジトリの旧要求が新要求より遅れて完了する場合、別リポジトリへの移動後の完了でも守る。Phase 2で要求共有・キャッシュを導入する場合も、既存の完了タイミング制御テストを維持し、採用方式に応じた検証を追加する。

[検索で想定外の例外が起きた後の状態と復帰](search-skeleton.md#未解決事項想定外の例外後の状態と復帰)は未解決のまま。今回の詳細Providerのエラー処理によって検索Controllerの問題が解消したとは扱わない。

Androidエミュレーター・実機での今回の画面操作は未実行。実通信・CIも未実装であり、READMEのPhase 1全体の完了とは区別する。
