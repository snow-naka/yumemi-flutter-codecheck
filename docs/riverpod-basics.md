# Riverpod導入と基礎確認（Issue #3・段階1）

> **履歴資料（2026-11-25整理）**：2026年11月18日のIssue #3・段階1におけるRiverpod導入と基礎検証の履歴資料です。 本文の仕様・未実装・未検証・今後の作業・Gitの状態などは当時の記録であり、現在の状態を示すものではありません。現行の機能・利用方法は[README](../README.md)、現行の技術設計は[architecture.md](architecture.md)を参照してください。

確認日：2026-11-18。対象ブランチ：`feature/3-skeleton`。

## 今回の範囲

Riverpodの導入、アプリ起動時の`ProviderScope`、小さなテストによる`watch`・`read`・差し替え・自動再試行の暫定無効化を確認した。ユーザーの指示に従い、初期カウンター画面は除き、本体はタイトルだけの最小起動表示とした。カウンターはテスト内の学習例としてだけ使う。検索・詳細の画面や取得窓口、Fake、CIはまだ実装していない。

## 導入前の互換性確認と依存関係

WSL用SDKはFlutter 3.50.0 stable / Dart 3.14.0。pub.devの公開メタデータで安定版と要求SDKを確認し、追加する直接依存を提示して、ユーザーの許可を得てから導入した。

| パッケージ | 要求SDK | 判定 |
| --- | --- | --- |
| flutter_riverpod 3.5.0 | Dart ^3.12.0、Flutter >=3.0.0 | 使用中のSDKは範囲内 |
| riverpod 3.5.0 | Dart ^3.12.0 | 使用中のSDKは範囲内 |

`flutter_riverpod`の`material_ui: ^1.0.0`という依存制約も、既存の`material_ui 1.11.1`で満たせる。直接依存は`flutter_riverpod: ^3.5.0`だけを追加し、`pubspec.lock`では3.5.0に固定された。

今回新たに解決されたパッケージは次の6件。既存パッケージのバージョン変更はなかった。

| パッケージ | バージョン | 追加の理由 |
| --- | --- | --- |
| flutter_riverpod | 3.5.0 | FlutterからRiverpodを使用する直接依存 |
| riverpod | 3.5.0 | 状態管理の本体 |
| state_notifier | 1.0.0 | Riverpod側の間接依存。アプリでStateNotifierを採用するという意味ではない |
| uuid | 4.6.0 | riverpodの間接依存 |
| crypto | 3.0.8 | uuidの間接依存 |
| fixnum | 1.1.1 | uuidの間接依存 |

テストは既存の`flutter_test`を使う。`riverpod_generator`・`build_runner`・Mock用パッケージの追加や、Flutter/Dart SDKの変更はしていない。

## 小さなテストで確認したこと

実行する例は[test/riverpod_basics_test.dart](../test/riverpod_basics_test.dart)にまとめた。

テスト内の`_counterProvider`は`NotifierProvider`で、値の管理と加算操作を提供する。加算量は`_incrementAmountProvider`から取得する。この分離によって、操作と画面を変えずに依存先の差し替えを確認できる。

### watch：更新を購読する

`_WatchedCount`の`ref.watch(_counterProvider)`は、値を読み取ると同時に変化を購読する。加算後に`_WatchedCount`が再描画され、表示は0 → 1 → 2になった。

アプリの検索結果や検索中表示のように、状態変更へ追随する表示に使う。Provider同士をつなぐときにも、依存する状態の更新に追随させたい箇所で使う。

### read：その時点の値や操作対象を取得する

加算ボタンは`ref.read(_counterProvider.notifier).increment()`で操作を呼ぶ。クリックした時点でNotifierを取得すればよく、ボタン自身がカウンターの値を購読する必要はない。

比較用の`_ReadCount`は`ref.read(_counterProvider)`で表示する。状態だけを変えてもこのWidgetには購読がないため、自動再描画は起きず、表示は0のままだった。一方、新たに`read`を呼ぶと最新値1・2を取得できた。

これは`read`が初期値を固定するという意味ではない。他の理由でWidgetが再描画されれば読み直される。比較のため意図的に使った例であり、更新に追随すべき本番表示には`watch`を使う。

### override：同じProviderの依存先を差し替える

`ProviderScope(overrides: [_incrementAmountProvider.overrideWithValue(5)], ...)`にすると、同じボタン・同じNotifier・同じ表示で、1回の加算が0 → 5になった。

また、別々の`ProviderContainer.test()`では、差し替え側が5になっても通常側は初期値0のままで、通常側で加算すると1になった。差し替えと状態が別の管理領域へ漏れないことを確認した。各テストで新しい領域を作るため、テスト間で状態を共有しない。

後の検索・詳細では、同じ考え方で取得窓口をFakeやテスト用の実装へ差し替える。今回はその取得窓口自体は作っていない。

### 暫定的な自動再試行の無効化

`main()`で`MyApp`の外側に`ProviderScope(retry: (retryCount, error) => null, ...)`を配置する。`MyApp`自身はScopeを作らず、テストから外側のScopeへoverrideを渡せる。`null`は再試行までの待ち時間を返さず、自動再試行を止める指定。

テストでは本体の`main()`を起動して実際の管理領域を取得し、失敗するテスト用`FutureProvider`を購読した。失敗表示用のエラー状態になり、仮想時間を30秒進めても実行回数は1のままだった。`container.invalidate`で明示的に状態を無効化すると、2回目だけが実行された。実時間で30秒待つテストではない。

Issue #3では詳細取得の失敗表示と手動再試行を実装するが、自動再試行の無効化は暫定方針。Phase 2の実通信実装時にエラー種別・回数・間隔・レート制限への対応を含めて再検討する。今回、詳細エラー画面・手動再試行ボタン・実際のレート制限処理は実装していない。

## 検証結果

WSL用Flutterを絶対パスまたはPATHの先頭で指定して実行した。

- `flutter test --no-pub test/riverpod_basics_test.dart`：基礎確認と外部Scope注入の5件が成功。
- `flutter test --no-pub`：基礎確認・外部Scope注入5件と最小起動確認1件、計6件が成功。
- `flutter analyze --no-pub`：問題なし。
- この段階ではAndroid APKの再ビルド・エミュレーターでの再実行、CIの実行は行っていない。Issue #1の環境検証結果と分ける。

これらはAPIの挙動を確かめた記録であり、利用者の学習理解度やIssue #3全体の完成を判定するものではない。

## 次の作業

段階2で`RepositoryKey`・`RepositorySummary`・`RepositoryDetail`・`SearchPage`・`ApiFailure`と取得窓口を作り、Fakeで検索・詳細の成功・0件・不完全結果・待機・失敗を再現する。実装と対応するテストを組にして進める。今回は段階2へは進まない。

## 参照資料

- [flutter_riverpod公開メタデータ](https://pub.dev/api/packages/flutter_riverpod)
- [riverpod公開メタデータ](https://pub.dev/api/packages/riverpod)
- [Riverpod：Refs](https://riverpod.dev/docs/concepts2/refs)
- [Riverpod：Provider overrides](https://riverpod.dev/docs/concepts2/overrides)
- [Riverpod：Automatic retry](https://riverpod.dev/docs/concepts2/retry)

依存解決後には、ローカルに取得した各パッケージの`pubspec.yaml`でも要求SDKと依存関係を照合した。
