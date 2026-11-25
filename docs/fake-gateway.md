# 段階2：データ型とFake Gateway

> **履歴資料（2026-11-25整理）**：2026年11月18日のIssue #3・段階2におけるデータ型・Fake Gatewayの実装と検証の履歴資料です。 本文の仕様・未実装・未検証・今後の作業・Gitの状態などは当時の記録であり、現在の状態を示すものではありません。現行の機能・利用方法は[README](../README.md)、現行の技術設計は[architecture.md](architecture.md)を参照してください。

2026-11-18、Issue #3。本書は段階2時点の取得窓口とFakeの検証記録。後続の検索画面・Controller・状態は[段階3の記録](search-skeleton.md)を参照する。詳細Providerは未実装。

## 構成と責務

- `lib/models/repository_models.dart`：識別情報・概要・詳細・検索結果。FlutterとRiverpodに依存しない。`RepositoryKey`はid・owner・nameによる値の比較とhashCodeを持ち、別インスタンスでも同じキーとして扱える。`SearchPage.items`は入力一覧をコピーし変更不可にしている。
- `lib/models/api_failure.dart`：`ApiFailure`例外。現段階は仮の通信失敗と対象取得不可の2分類、利用者向けメッセージ、任意のHTTPステータスだけを持つ。HTTP変換・レート制限・再試行時刻などはPhase 2の設計時に拡張する。
- `lib/data/github_repository_gateway.dart`：検索と詳細取得の共通契約。成功はデータ、想定する失敗は例外を返す。空結果を失敗の代用にしない。
- `lib/data/fake_github_repository_gateway.dart`：実通信なしで結果と失敗を再現する。検索・詳細のハンドラーを指定すれば既定動作を差し替えられる。
- `lib/providers.dart`：本番用の`githubRepositoryGatewayProvider`を定義し、初期状態ではFakeを提供する。学習用カウンターProviderはここには含めず、`test/riverpod_basics_test.dart`内に限定する。

`main()`がMyAppの外側にProviderScopeを置く。MyApp自身はScopeを作らないので、テスト側から同じ取得窓口をoverrideできる。検索・詳細用Providerは、後続の段階でこの窓口に依存させる。

## Fakeの既定シナリオ

`FakeGitHubRepositoryGateway()`は既定で300ms待つ。検索はpage=1、perPage=30を既定とし、ページ内の件数と総件数を区別する。pageは1以上、perPageは1〜100を受け付け、範囲外はプログラム側の引数不正として扱う。

| 検索語 | 結果 |
| --- | --- |
| flutter | flutter-sampleが1件。詳細はStar 120、Watcher 8で、取り違えを検出できる |
| riverpod | riverpod-sampleが1件。言語null、Star/Fork等は0。詳細は初回だけ失敗し、次の明示的な呼び出しで成功 |
| example | 両方のリポジトリ。ページ分割も確認できる |
| empty・一致しない語 | 正常な空一覧 |
| incomplete | 不完全フラグ付きの結果。ページを超えるとitemsは空でもtotalCountと不完全フラグは保持 |
| error | 仮の検索失敗をApiFailureとして通知 |

これらはFake専用の再現規約で、GitHub検索の仕様ではない。空の検索語もFakeでは空一覧だが、後続の検索Controllerは空入力でGatewayを呼ばない方針を維持する。

詳細の識別情報が仮データに存在しない場合は、取得不可のApiFailureを返す。失敗をダミー詳細や件数0へ変換しない。Fakeが保持する初回失敗の回数はインスタンスごとに独立し、自動で再取得する処理はない。

仮データのavatarUrlは空文字として、後続の画面では代替アイコンを表示する前提。URLから画像を取得する処理はない。`openIssueAndPullRequestCount`はFake内でOpen Issue＋PRを表す値とするが、実通信時の課題解釈・最終表示ラベルの判断を確定したわけではない。

## テストで差し替える方法

`ProviderScope`の`overrides`へ`githubRepositoryGatewayProvider.overrideWithValue(fake)`を指定する。`test/data/gateway_provider_test.dart`で、MyAppの外側から注入した同じインスタンスを取得でき、内側に別のScopeが作られないことを確認した。

Fakeの`searchHandler`・`detailHandler`を指定した場合は、既定の待機とシナリオを使わず、そのハンドラーへ入力を渡す。`Completer`を返すハンドラーにより、テストが成功・失敗・完了タイミングを制御できる。テストで実時間の300msを待つ必要はない。

## 検証

WSL用Flutter SDKを使用して、以下を実行した。

| コマンド | 結果 |
| --- | --- |
| `flutter test --no-pub test/data` | 段階2の限定テスト11件成功 |
| `flutter test --no-pub` | 全17件成功 |
| `flutter analyze --no-pub` | 問題なし |

キーの値比較、Star/Watcherの区別、ページと総件数、不完全な空結果、nullと0、型付き失敗、初回詳細失敗と再取得、独立したFakeの状態、取得待機の制御、検索一覧の変更防止、外部Scopeからの注入を確認した。

詳細ログのローカル保存先は、リポジトリ直下からの相対パスで`log/issue3/step2/`。保管済みの`test-results.log`は全17件成功、`analyze-results.log`は解析問題なしという上記結果と一致する。これらはローカルの検証記録として保持し、GitHubには登録しない。ルートの`.gitignore`の`/log/`で、拡張子にかかわらず`log/`以下を除外する。ログ本体は編集・削除していない。

新しい依存パッケージは追加していない。実通信・画像通信・実際のレート制限・自動再試行の詳細設計は行っていない。
