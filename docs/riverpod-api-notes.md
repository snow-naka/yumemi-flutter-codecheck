# Riverpodへの対応とGitHub API整理メモ

外部仕様の調査記録日：2026-11-15  
設計方針の採用・更新日：2026-11-18  
対象：ゆめみ Flutterエンジニアコードチェック課題／README

**位置づけ：採用したスケルトン設計と、実通信前に確認するAPI仕様・候補を分けて記録する。** 2026-11-18に検索・詳細の構成と操作方針を採用し、READMEにも反映した。初期サンプルは別フォルダにあり、このリポジトリにはFlutterのコード・依存設定はまだ取り込んでいない。実装・動作検証済みではない。外部仕様は今回再調査しておらず、過去の調査記録と最新仕様の照合は実通信前に行う。

## 1. 採用した設計と残る判断

READMEの「画面 ⇄ 検索状態を管理する処理 ⇄ データ取得の窓口」は、Riverpodで実現できる。未検索・検索中・成功・失敗の区別、入力途中の文字列と送信した検索語の分離、Fakeから実通信への差し替えは維持する。

当初の追加案のうち、骨組みに関わる次の方針を採用した。Issue数の定義は引き続き未確定とする。

| 対象 | 採用方針・残る判断 |
| --- | --- |
| 検索結果 | 一覧だけでなく、総件数と結果の不完全性を保持する |
| Watcher数 | `watchers_count`を使用しない。詳細取得の`subscribers_count`を使用する |
| 詳細画面 | スケルトンから非同期のFake詳細取得を設け、取得中・成功・失敗・再試行を検索状態から独立して扱う |
| Issue数 | Openのみか、PRを含むかを表示ラベルと取得方法で一致させる。現時点では要件解釈が未確定 |
| 失敗情報 | HTTPステータス、通信失敗、応答形式不正を区別し、レート制限の待機情報も持てるようにする |

当初のREADMEは選択した情報だけで詳細を表示する案だったが、取得中・失敗も実通信前に確認するため、非同期のFake詳細取得へ拡張した。スケルトンでは実通信を行わない。UIはFlutter標準のMaterialを使い、`material_ui`からの切り替えは実装着手後に行う。

## 2. Riverpodが受け持つこと

Riverpodは、状態や依存する処理をProvider経由で取得し、状態の変更を参照先の画面へ反映する仕組み。HTTP要求・JSON変換・API固有のエラー判定を代わりに設計してくれるものではない。[R1][R2]

### 採用構成（未実装）

| 部品 | 採用方針 | 担当 |
| --- | --- | --- |
| アプリ内の状態の管理領域 | `ProviderScope` | Providerを利用できる範囲を作る |
| データ取得窓口 | `Provider<GitHubRepositoryGateway>` | Fake／実通信の実装を提供する |
| 検索制御 | `Notifier<SearchState>`＋`NotifierProvider` | 送信を受けて検索し、4状態を更新する |
| 詳細取得 | `FutureProvider.autoDispose.family` | 選択したリポジトリごとの非同期取得を行う |
| 入力途中の文字列 | 画面の`TextEditingController`等 | 未送信の入力を管理する |
| 選択した項目 | 画面遷移の引数 | 詳細へ識別情報と検索時点の概要を渡す |

上記はRiverpod 3系のガイドを参照した構成方針。検索状態は`sealed class`の4状態で表し、コード生成は使わない。現在の依存関係にRiverpodは未追加で、導入版・互換性・具体的な記法は導入前に確認する。依存関係の追加・変更前にはユーザーに確認する。[R1][R5]

### 操作の流れ

```text
検索画面
  ├─ 状態を参照する：ref.watch(searchControllerProvider)
  └─ 検索ボタン：ref.read(searchControllerProvider.notifier).search(query)
                          ↓
                   SearchController
                          ↓
               GitHubRepositoryGateway
                    ├─ Fake実装
                    └─ REST API実装
```

これは呼び分けの説明であり、そのまま実行できるコード一式ではない。`watch`は状態変化を受け取るため、`read(...notifier)`はボタン操作から処理を呼ぶために使う。[R2]

`Notifier<SearchState>`の初期値は同期的に「未検索」を返し、`search()`の中で非同期取得を待つ。Notifierのメソッドで非同期処理を行うことはできる。「通信があるから必ずAsyncNotifier」という制約ではない。[R1][R6]

`AsyncNotifier`も選べるが、その場合は標準の`AsyncValue`と独自の4状態を二重に管理しないよう設計する。今回はREADMEの状態表と対応させるため、検索は独自の`SearchState`を採用する。詳細は画面を開いたら取得するため、取得中・成功・失敗を持つ`AsyncValue`をそのまま利用しやすい。

### この課題で明示する動作

- 初期化や画面再描画だけでは検索しない。検索ボタンとキーボードの送信で実行する。再検索開始時は旧結果を非表示にし、新しい結果は先頭から表示する。
- 検索中の二重実行は、ボタンの無効化だけでなくController内部でも拒否する。
- 空白のみの入力は通信せず、既存の検索状態を維持する。
- 検索語は送信時に確定する。検索中も入力編集を許可するが再送信・別検索・利用者向けキャンセルは設けない。表示には送信済み検索語を添え、検索失敗の再試行もその語を使う。
- 検索状態は詳細へ移動しても保持し、戻るだけでは再検索しない。
- 検索画面をナビゲーションスタックに残し、入力欄・検索結果・スクロール位置を保持する。初版はアプリ終了後の状態復元を行わない。
- 詳細から離れた後の通信完了で、破棄された状態を更新しない。キャンセルまたは結果を無視する処理を用意する。

### 自動破棄と自動再試行

検索はアプリ内で1組だけ保持し、詳細へ移動したことだけで結果が失われない生存期間にする。リポジトリ別の詳細取得Providerは自動破棄を有効にし、画面を離れたら破棄する。詳細は開くたびに取得し、初版は永続キャッシュを設けない。[R3]

Riverpod 3ではProviderの計算中に例外が発生すると自動再試行の対象になる。詳細取得などでは、初版は自動再試行を無効にし、利用者の明示的な再試行にする。これはNotifierの全メソッドが自動再試行されるという意味ではない。[R4]

Fakeへの差し替えはProviderのoverrideで行う。画面と検索制御を変えずに、取得結果と待機・失敗を指定し、テストでは完了タイミングも制御する。[R7]

## 3. 利用する外部通信

| 区分 | 呼び出し | 目的・今回の位置づけ |
| --- | --- | --- |
| 基本 | `GET /search/repositories` | 検索。課題で指定されているAPI |
| 基本候補 | `GET /repos/{owner}/{repo}` | 詳細表示用。とくに実際のWatcher数を取得する |
| 画像取得 | `GET {owner.avatar_url}` | オーナー画像。上のAPIが返すURLから取得する。追加のユーザー情報APIは不要 |
| 条件付き | `GET /search/issues` | PRを除いたOpen Issue数などを表示すると決めた場合 |
| 診断用 | `GET /rate_limit` | 制限状況の手動調査等。通常画面からの定期呼び出しは不要 |

課題は検索APIを自前で呼ぶ処理を要求し、GitHub API全体を包む専用パッケージの使用を禁止している。検索・公開リポジトリ詳細は未認証で利用できるため、初版は公開情報・認証なしを提案する。[G1][G2][G3]

### 共通の要求設定案

```http
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2026-03-10
User-Agent: yumemi-flutter-codecheck
```

ベースURLは`https://api.github.com`。上記のAPIバージョンは過去の調査メモにある候補であり、今回の確定値ではない。実通信前に公式仕様と照合して対応版を固定し、無指定の既定版に依存しない。[G7]

GETの本文は送らず、検索条件はクエリへ、owner/repoはパスへ設定する。URIを作る機能でエンコードし、入力文字列を生のURLに連結しない。有効なUser-Agentが必要。[G5]

初版はAuthorizationを送らない。将来認証を追加するなら秘密情報の取得・保存・配布を別に設計し、リポジトリやログにトークンを残さない。

## 4. リポジトリ検索

### 入力

`GET /search/repositories`

| 項目 | 型・公式仕様の要点 | 初版の提案 |
| --- | --- | --- |
| `q` | 必須の文字列。キーワードと検索条件を含む | 前後空白を除いた入力。空は送らない。GitHub検索クエリとして扱う |
| `page` | 整数。既定1 | 最初は1ページ目 |
| `per_page` | 整数。既定30、最大100 | 30 |
| `sort` | 任意。stars/forks/help-wanted-issues/updated | 指定せず、既定の関連度順 |
| `order` | asc/desc。sortを指定しない場合は無視される | 指定しない |

仕様の根拠：[G2]。骨組みでは1ページ分を扱い、初回実通信は先頭30件までを出発点とする。ページングの最終対応範囲は提出前に別途決める。公式課題の合格条件を断定するものではなく、表示範囲の制限はREADMEと画面に明記する。

### 出力

HTTP 200の主な外側の項目は`total_count`、`incomplete_results`、`items`。[G2]

アプリ内では次の`SearchPage`へ変換する。

```text
SearchPage
  items: List<RepositorySummary>
  totalCount: int
  incompleteResults: bool
  page: int               // 要求時の値を保持する
  perPage: int            // 要求時の値を保持する
```

`items.length`は取得したページの件数であり、全ヒット数ではない。`incomplete_results=true`は、成功応答でも検索処理の結果が不完全な可能性を示す。[G2]

表示方針：不完全な場合は取得できた項目を表示しつつ注意を出す。0件でも「完全に検索して該当なし」と断定しない。「先頭ページしか表示していない」ことと「検索処理自体が不完全」を区別する。

### 使うフィールドとアプリ内の名前案

以下は利用する項目の対応表であり、GitHubのJSONスキーマ全体を再定義したものではない。[G2][G3][G4]

| JSON項目 | Dart側の候補 | 扱い |
| --- | --- | --- |
| `id` | `int id` | 同一リポジトリの識別 |
| `name` | `String name` | リポジトリ名 |
| `full_name` | `String fullName` | owner/repoの表示・識別補助 |
| `owner.login` | `String ownerLogin` | 詳細APIのownerへ渡す |
| `owner.avatar_url` | `String avatarUrl` | アイコン取得先 |
| `language` | `String? language` | nullを許可。例：画面では「未指定」 |
| `description` | `String? description` | 追加表示する場合のみ。nullを許可 |
| `stargazers_count` | `int starCount` | Star数 |
| `forks_count` | `int forkCount` | Fork数 |
| `open_issues_count` | `int openIssueAndPullRequestCount` | Open IssueとOpen PRを含む件数として扱い、Issueのみとは呼ばない |
| `watchers_count` | 原則モデルに取り込まない | 名前に反してStar数に対応するため |

nullと欠落、数値0と未取得を混同しない。必須情報の型が不正なら応答形式エラーにし、未知の追加フィールドは無視する案。nullableと定めた項目に値がないことを、通信失敗として扱わない。

## 5. リポジトリ詳細

### 入出力

`GET /repos/{owner}/{repo}`。入力は検索結果から得たownerとrepo（`.git`を付けない）。出力はリポジトリの情報1件。[G3]

**Watcher数はこの詳細応答の`subscribers_count`を使う。`watchers_count`と`stargazers_count`はどちらもStar数に対応する。** 検索応答だけで本来のWatcher数までそろうと仮定しない。[G3][G4]

```text
RepositoryKey
  id: int
  owner: String
  name: String

RepositoryDetail
  summary: RepositorySummary
  watcherCount: int       // subscribers_countから取得
```

`RepositoryKey`・`RepositorySummary`・`RepositoryDetail`の役割を分け、詳細は概要データと追加情報を持つ。概要モデルを継承しない。ファイルの細かな分割は実装時の分量に合わせる。詳細応答のidが選択対象と一致するかの検査は、実通信の応答処理を設計する際の確認項目とする。

### 詳細画面の状態（採用済み・未実装）

| 起きたこと | 表示・動作 |
| --- | --- |
| 項目を選んで詳細へ | タイトル等の概要は表示できる。詳細部分は取得中にする |
| 詳細取得成功 | 詳細応答の情報で表示をそろえる |
| 詳細取得失敗 | 取得失敗と再試行操作を表示。未取得の件数を0にしない |
| 再試行 | 詳細だけ再取得する。検索はやり直さない |
| 戻る | 検索状態・結果・入力欄・スクロール位置を保持し、再検索しない |

一覧の全件について先に詳細APIを呼ぶ方式にはせず、選んだ1件だけ取得する。検索と詳細の失敗を独立させ、詳細の失敗で検索結果を消さない。

## 6. Issue数の意味は、明示して決める

GitHub RESTではPRもIssueとして扱われる。`open_issues_count`を「PRを除いたIssue数」や「Close済みも含む全Issue数」として表示しない。[G3][G8]

公式課題は「Issue数」とだけ述べ、Open/ClosedやPRを含むかを明記していない。[G1] したがって、この点は仕様解釈の未確定事項として残す。

| 選択肢 | 取得方法 | 注意 |
| --- | --- | --- |
| Open Issue＋PRの件数 | 詳細応答の`open_issues_count` | 追加通信不要。画面とREADMEにPRを含むと明記する |
| PRを除くOpen Issue数 | `GET /search/issues`、q=`repo:OWNER/REPO is:issue is:open`、per_page=1 | `total_count`を使う。追加の検索枠を消費する |

後者を採る場合も`incomplete_results`を捨てず、失敗や不完全な結果を確定した0件に置き換えない。[G2] Issue一覧APIを1ページ取得して配列長を数えるだけでは、総数を取得したことにならない。

## 7. エラーと応答の扱い

### エンドポイント個別に公開されている主なステータス

| API | 公開リファレンスの一覧 |
| --- | --- |
| Search repositories | 200 / 304 / 422 / 503 |
| Get a repository | 200 / 301 / 403 / 404 |

これは、それ以外のHTTP応答や通信障害を無視してよいという意味ではない。レート制限・認証・ネットワークなどを共通処理で扱う。[G2][G3][G5]

### アプリ内の失敗分類案

| 受け取ったもの・発生したこと | 分類案 | 表示・再試行方針案 |
| --- | --- | --- |
| ネットワーク接続・名前解決等の失敗 | `network` | 接続を確認して明示再試行。原因をインターネット断と断定しない |
| アプリ側で設定した時間を超過 | `timeout` | 時間切れと表示。自動連打しない |
| 403/429＋制限を示すヘッダー・本文 | `rateLimited` | 指示された時刻・待機時間まで再送しない |
| 403で制限と確認できない | `forbidden` | アクセス拒否。権限や要求設定も疑う |
| 401 | `unauthorized` | 認証を導入した場合の設定・資格情報を確認する |
| 詳細の404 | `notFoundOrUnavailable` | 現在取得できないと表示。削除と断定しない |
| 422 | `requestRejected` | 条件不正または過剰要求等。本文に基づいて案内し、入力ミスと決めつけない |
| 500番台 | `server` | サーバー側の一時的失敗として案内。後で明示再試行 |
| 200だが不正JSON／必要な値の型不正 | `invalidResponse` | 応答を処理できない。成功・0件に変換しない |
| その他の想定外ステータス | `unexpectedHttp` | ステータスを診断用に保持して案内する |

HTTPの意味・GitHub固有の制限の根拠：[G2][G3][G5][G6][G9]。分類名と画面表示はアプリ側の提案。通信例外の具体型は、採用するHTTPライブラリに合わせて実装時に確定する。

`403`だけではレート制限と断定しない。`404`も、削除だけでなく非公開リソースにアクセスできない場合などに返り得る。[G5]

### 本文・ヘッダーから保存したい情報

```text
ApiFailure
  kind                 // 上表の分類
  httpStatus?          // HTTP応答を受け取った場合
  retryAt?             // 再試行できる時刻が判断できる場合
  rateLimitResource?   // search/coreなど、取得できる場合
  safeMessage          // アプリが利用者向けに用意する説明
  diagnosticCode?      // APIエラー詳細等。秘密を含めない
```

エラー本文は`message`、検証エラーの`errors`等を必要に応じて読む。エラー本文自体がJSONでない場合でも、HTTPステータスと利用可能なヘッダーによる分類を失わないようにする。[G5]

HTTP状態を確認する前に成功用JSONとして解析しない。外部の英語エラーメッセージを、そのまま利用者への説明や判定の唯一の根拠にしない。

### エラー扱いしないもの

- 正常に完了した0件は成功。ただし不完全フラグがある場合は注意を表示する。
- `language: null`等、許可したnullは正常データ。
- 301等のリダイレクトは移動先を確認して処理する。無制限に追わず、HTTPS・APIの想定先を守る案。[G3][G10]
- 304は条件付き要求に対するキャッシュ利用の応答であり、本文のない200として解析しない。初版は条件付き要求を使わない案。[G10]
- 画像だけが取得できない場合は代替アイコンにし、検索や詳細データ全体の失敗にしない案。
- 画面終了に伴うキャンセル・結果の無視は、利用者に通信エラーとして表示しない案。

## 8. レート制限

確認時点の公開値は、未認証の検索が10回/分、認証済みの通常検索が30回/分。詳細取得など非検索APIの未認証枠は60回/時。[G2][G6]

検索枠と非検索枠は別。実際の待機判断は応答の`x-ratelimit-*`を優先する。未認証ではアクセス元IPにひもづくので、同じネットワークの別利用者の影響もあり得る。[G6][G11]

| 応答の情報 | 扱い |
| --- | --- |
| `retry-after` | 指定された秒数が経過するまで再送しない |
| `x-ratelimit-remaining: 0` | `x-ratelimit-reset`のUTC epoch秒以降まで再送しない |
| セカンダリ制限で待機情報なし | 公式案内では少なくとも1分待つ。初版は自動再試行せず手動とする |

複数の制限情報がある場合、適用される待機条件を破らない時刻にする。画面で無効化するだけでなく、取得処理側でも早すぎる再送を防ぐ案。[G5][G10]

レート制限テストのためにGitHubへ大量アクセスしない。FakeやHTTPのモックでヘッダー・本文を再現する。

## 9. アプリ内の取得窓口

採用した取得窓口の契約。型の本体や例外クラスはまだ実装していない。

```dart
abstract interface class GitHubRepositoryGateway {
  Future<SearchPage> searchRepositories(
    String query, {
    int page = 1,
    int perPage = 30,
  });

  Future<RepositoryDetail> getRepository(RepositoryKey key);
}
```

成功時はアプリ用の型を返し、想定内の失敗は`ApiFailure`例外で統一する。空一覧やダミーの詳細情報で失敗を表現しない。

HTTP／JSON／レート制限ヘッダーの解釈は取得側に置く。Controllerは利用者の操作と状態遷移、画面は表示と入力を担当する。プログラム自体の不具合を一律に「ネットワークエラー」へ変換しない。

Fakeも両メソッドを持たせ、検索と詳細それぞれで遅延・成功・分類済み失敗を返せるようにする。これにより、実通信への差し替え前に詳細画面の待機・失敗も確認できる。

## 10. 最初のテスト観点案

以下は計画であり、まだ実行していない。

| 観点 | 確認すること |
| --- | --- |
| 未検索と空入力 | 初期表示・空送信でAPIを呼ばない。既存状態を勝手に消さない |
| 検索中 | 送信時に待機状態へ移る。二重送信でも取得は1回 |
| 成功と0件 | 結果あり・正常0件・不完全結果を区別する |
| 入力の分離 | 待機中や結果表示中の入力編集で、確定した検索語が変わらない |
| 項目対応 | Star数とWatcher数を取り違えず、nullと0を区別する |
| 失敗の分類 | 通信・時間切れ・403の区別・429・422・404・5xxを表現できる |
| レート制限 | Fakeの時刻を使い、待機中に再試行しない |
| 応答形式 | 追加の未知項目は許容し、必要項目の不正は検出する |
| 詳細 | 選択した1件だけ取得し、失敗しても検索結果を残す |
| 戻る・再表示 | 検索語・結果・入力・スクロール位置が残り、自動再検索しない。新しい検索は先頭へ戻し、詳細を開き直すと再取得する |
| ライフサイクル | 破棄後の応答で状態を更新しない。意図しない自動再試行がない |
| 画像 | アイコン失敗をデータ全体の失敗へ波及させない |

## 11. 残す決定事項と着手順

骨組みのモデル分割・失敗の伝達・検索中の入力可否・状態管理・戻る際の保持・詳細の再取得方針は採用済み。導入前にRiverpodの版・互換性と既存の実行環境を確認する。

Issue数の定義と追加検索の要否、HTTPライブラリ・タイムアウト、APIバージョン、レート制限の待機情報の保存場所は実通信前に決める。最終的なページング範囲とオプション項目は提出範囲を判断する際に決める。過去に提案したHTTPライブラリやタイムアウト等の候補は、今回の採用判断だけでは確定値にしない。

着手の指示後は、環境・Gitの初期記録・作業ブランチを確認 → 標準Materialへの切り替えとRiverpod導入 → 検索・詳細のFake窓口 → 状態と画面・往復の検証 → 実通信前の仕様照合・判断 → 実通信とHTTPエラー変換の検証、の順に進める。今回は文書のみの更新で、パッケージ追加・コード実装・解析・テストは行っていない。

## 参照資料

下記は今回参照した一次資料。リンク先の公式仕様と、このメモで提案した実装方針は区別する。実通信の成功・エラーをこのメモ作成時に試験したわけではない。

- [R1] Riverpod — Providers：`https://riverpod.dev/docs/concepts2/providers`
- [R2] Riverpod — Refs：`https://riverpod.dev/docs/concepts2/refs`
- [R3] Riverpod — Automatic disposal：`https://riverpod.dev/docs/concepts2/auto_dispose`
- [R4] Riverpod — Automatic retry：`https://riverpod.dev/docs/concepts2/retry`
- [R5] Riverpod — DO/DON'T：`https://riverpod.dev/docs/root/do_dont`
- [R6] Riverpod — From StateNotifier：`https://riverpod.dev/docs/migration/from_state_notifier`
- [R7] Riverpod — Provider overrides：`https://riverpod.dev/docs/concepts2/overrides`
- [G1] ゆめみ Flutter課題：`https://github.com/yumemi-inc/flutter-engineer-codecheck`
- [G2] GitHub — Search：`https://docs.github.com/en/rest/search/search`
- [G3] GitHub — Repositories / Get a repository：`https://docs.github.com/en/rest/repos/repos#get-a-repository`
- [G4] GitHub — Watching versus starring：`https://docs.github.com/en/rest/activity/watching`
- [G5] GitHub — Troubleshooting the REST API：`https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api`
- [G6] GitHub — Rate limits：`https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api`
- [G7] GitHub — API Versions：`https://docs.github.com/en/rest/about-the-rest-api/api-versions`
- [G8] GitHub — Issues：`https://docs.github.com/en/rest/issues/issues`
- [G9] GitHub — Authenticating：`https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api`
- [G10] GitHub — Best practices：`https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api`
- [G11] GitHub — Rate limit endpoint：`https://docs.github.com/en/rest/rate-limit/rate-limit`
