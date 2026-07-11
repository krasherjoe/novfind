# Domain Pitfalls

**Domain:** Flutter Android novel search aggregator (Google scraping + sharing)
**Researched:** 2026-07-11
**Overall confidence:** MEDIUM

---

## Critical Pitfalls

Mistakes that cause rewrites, blocking, or complete failure.

### Pitfall 1: GoogleがHTML構造を変更し、スクレイパーが全滅する

**What goes wrong:**
Google検索結果ページ（SERP）のHTML構造（CSSクラス名、ID、data属性）が予告なく変更される。固定セレクタに依存したパースロジックが突然動かなくなり、結果ゼロ・パースエラーが発生する。

**Why it happens (root cause):**
- GoogleはSERPのクラス名/IDを頻繁に変更する（クリティカルな変更は月に複数回）
- 2026年現在、AI Overviewsやリッチスニペットの追加によりレイアウトが継続的に進化している
- 固定CSSセレクタ（`.g`, `.rc`, `.yuRUbf`など歴史的に使われてきたクラス）は予告なく変更・削除される

**Consequences:**
- アプリが突然全く結果を表示できなくなる
- ユーザーからの報告で初めて気づく（サイレント障害）
- 緊急のホットフィックスが必要になる
- ユーザーの信頼を失う

**Prevention:**
- CSSクラス名/IDに依存しないパース戦略を採用する
  - `<h3>` 見出しテキストや `data-*` 属性（`data-attrid`, `data-sncf`など比較的安定した属性）を使う
  - HTML内のJSON埋め込みデータを活用する（クラス名より安定している）
- パースロジックを集中管理し、テスト可能なユニットとして分離する
- 定期的な自動テストでSERP構造の変更を検出する（CIパイプラインに組み込む）
- フォールバック表示：「結果が取得できませんでした。手動で検索してください」UIを用意する

**Detection:**
- 検索結果が常に0件になる
- パース後の結果件数が急減する
- `querySelectorAll` の結果が空になる

**Which phase should address it:**
- フェーズ「検索スクレイピング」: 堅牢なパース戦略を設計段階で決める
- フェーズ「テスト」: SERP構造変更検出テストを追加

---

### Pitfall 2: Googleのレート制限/ブロックで検索が機能しなくなる

**What goes wrong:**
同一IPからの短時間の過剰リクエストにより、GoogleがCAPTCHA表示・429応答・IPブロックの対策を発動する。アプリの検索機能が完全に使えなくなる。

**Why it happens (root cause):**
- ユーザーが頻繁に検索ボタンをタップする
- 42サイト分のsite:クエリを同時実行する設計になっている
- FlutterのHTTPクライアントがデフォルトUser-Agent（`Dart/<version>`）を使い、即座にボット判定される
- レート制限の正確な閾値は非公開だが、同一IPからの短時間での数十リクエストでフラグが立つ

**Consequences:**
- 特定ユーザーがブロックされる
- アプリが使い物にならなくなる
- ユーザーに「Googleにブロックされました」と表示するしかない

**Prevention:**
- **リクエスト間隔の強制**: 最低2〜5秒の間隔を空ける（ランダムな遅延を入れる）
- **User-Agentの設定**: モダンなブラウザのUser-Agentを設定する（`Dart/<version>` は絶対に使わない）
- **リクエスト数の制限**: 1分間に数リクエストに抑える設計にする
- **429/403レスポンスの処理**: 指数的バックオフ（exponential backoff）を実装する
- **キャッシュ**: 同じ検索クエリの結果をキャッシュして重複リクエストを避ける
- **ユーザーへの明示**: 「連続検索はお控えください」などのガイダンスを表示する

**Warning signs:**
- HTTP 429（Too Many Requests）レスポンス
- CAPTCHAページが返される
- 空のHTMLまたはエラーページが返る

**Which phase should address it:**
- フェーズ「検索スクレイピング」: レート制限制御を設計に組み込む

---

### Pitfall 3: 42サイトのsite:クエリが1リクエストに収まらず、結果が不完全またはタイムアウトする

**What goes wrong:**
42の `site:` 演算子をOR結合したクエリが長すぎるため、Googleがクエリを拒否する、URLが長すぎてエラーになる、またはタイムアウトが発生する。

**Why it happens (root cause):**
- 元の `.env` に定義された `site:syosetu.com OR site:kakuyomu.jp OR ...` が非常に長い
- HTTP GETリクエストのURL長制限（約8KB）を超える可能性がある
- Googleは過度に長いクエリを拒否することがある
- 42サイトすべての結果を1ページで取得しようとすると、Googleの返す結果数が制限される（通常10件/ページ）

**Consequences:**
- クエリが拒否され結果が0件になる
- 一部のsite:演算子が無視される
- タイムアウトによるエラーハンドリングが複雑化する

**Prevention:**
- 42サイトを分割して複数クエリにする（例: 7サイト×6グループ）
- 各グループの結果をマージ・重複除去する
- クエリ長を事前チェックする
- POSTリクエストでの検索も検討する（ただしGoogleはGETが標準）
- または、長いクエリを短縮するためにsite:演算子のグルーピング戦略を検討する

**Which phase should address it:**
- フェーズ「検索スクレイピング」: クエリ分割戦略を設計する

---

## Moderate Pitfalls

### Pitfall 4: Android 9+ でHTTPS通信がブロックされる（NetworkSecurityConfig未設定）

**What goes wrong:**
Android 9（API 28）以降、`http://` へのクリアテキスト通信がデフォルトでブロックされる。`https://` でも証明書検証に失敗するケースがある。

**Why it happens:**
- Flutterのデフォルトテンプレートには `network_security_config.xml` が含まれていない
- 開発者がAndroidのセキュリティ設定を意識せずにHTTPリクエストを行う
- Google検索はHTTPSだが、プロキシ経由やローカルテストでHTTPを使おうとする

**Prevention:**
- `AndroidManifest.xml` に `INTERNET` パーミッションを明示的に追加する
- 必要に応じて `res/xml/network_security_config.xml` で特定ドメインのみクリアテキスト許可する
- プロダクションでは全通信をHTTPSにする
- `usesCleartextTraffic="true"` を無条件に設定しない（セキュリティリスク）

**Detection:**
- Android 9+端末でのみ通信エラーが発生する
- エラーメッセージに `CLEARTEXT communication not permitted` が含まれる

**Which phase should address it:**
- フェーズ「プロジェクトセットアップ」: Android設定を初期化する

---

### Pitfall 5: Android 11+ で共有インテントの送信先アプリが検出できない

**What goes wrong:**
Android 11（API 30）以降、パッケージ可視性（package visibility）の制限により、`share_plus` や `url_launcher` が Intent を処理できるアプリを検出できない。共有シートが空になる、または特定アプリが表示されない。

**Why it happens:**
- `share_plus` や `url_launcher` は内部的に `canLaunchUrl()` や `PackageManager.queryIntentActivities()` を使用する
- Android 11+ では `<queries>` 宣言なしでは他アプリの存在を検出できない
- `share_plus` は内部的に `<queries>` を宣言しているが、特定ユースケースでは不足する可能性がある

**Prevention:**
- `AndroidManifest.xml` に適切な `<queries>` 宣言を追加する：
  ```xml
  <queries>
    <intent>
      <action android:name="android.intent.action.SEND" />
      <data android:mimeType="text/plain" />
    </intent>
  </queries>
  ```
- `QUERY_ALL_PACKAGES` はGoogle Play審査が厳しいため使用しない
- ターゲットSDKとコンパイルSDKのバージョンに注意する

**Which phase should address it:**
- フェーズ「共有インテグレーション」: Android設定を適切に行う

---

### Pitfall 6: ウィジェット破棄後に `setState()` を呼んでエラーになる

**What goes wrong:**
非同期のHTTPリクエスト中にユーザーが画面遷移すると、ウィジェットが破棄された後で `setState()` が呼ばれ、「This widget has been disposed」エラーが発生する。

**Why it happens:**
- `StatefulWidget.initState()` でHTTPリクエストを開始する
- HTTPレスポンスが返ってくる前にユーザーが別画面に移動する
- `Future.then()` のコールバック内で `setState()` を呼ぶ
- Flutterは破棄されたStateでのsetStateを禁止している

**Prevention:**
- `mounted` プロパティをチェックする: `if (mounted) setState(() { ... });`
- `CancelToken`（dio）または `AbortableRequest`（http 1.6.0）でリクエストをキャンセルする
- 状態管理にRiverpod/Blocなどのライフサイクル対応ソリューションを使う
- リクエストキャンセルを `dispose()` で行う

**Example (dio):**
```dart
final cancelToken = CancelToken();

@override
void dispose() {
  cancelToken.cancel('widget disposed');
  super.dispose();
}

Future<void> search() async {
  try {
    final response = await dio.get(url, cancelToken: cancelToken);
    if (mounted) setState(() => results = response.data);
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) return;
    // エラー処理
  }
}
```

**Which phase should address it:**
- フェーズ「検索UI」: 初期実装時にパターンを確立する

---

### Pitfall 7: User-Agent未設定でボット判定される

**What goes wrong:**
FlutterのデフォルトHTTPクライアントはUser-Agentとして `Dart/<version> (dart:io)` を送信する。これは明らかにボットであり、Googleに即座に検出・ブロックされる。

**Why it happens:**
- `dart:io HttpClient` のデフォルトUser-Agentが `Dart/<version>` である
- `package:http` の `IOClient` も同じデフォルト値を使う
- 開発者がUser-Agentの重要性に気づかない

**Prevention:**
- `dart:io HttpClient.userAgent` プロパティを設定する（`null` にするとヘッダー自体を省略）
- `package:http` では `BaseClient` を継承してUser-Agentをオーバーライドする
- `dio` では `BaseOptions.headers['User-Agent']` で一括設定する
- モダンなブラウザのUser-Agent文字列を使用する（古すぎると逆に怪しまれる）
- User-Agentは定期的に更新する（ブラウザのバージョンアップに合わせて）

**Which phase should address it:**
- フェーズ「検索スクレイピング」: HTTPクライアント設定の一環として

---

### Pitfall 8: `url_launcher` と `share_plus` の使い分けを間違える

**What goes wrong:**
- `url_launcher` で「URLをシェア」しようとする → ブラウザが開いてしまい共有シートが出ない
- `share_plus` で「URLを開く」しようとする → 共有シートは出るが「開く」操作ができない
- URLをテキストとして送ると、受信アプリが自動リンクしないケースがある

**Why it happens:**
- `url_launcher` は `ACTION_VIEW`（「開く」Intent）を使用
- `share_plus` は `ACTION_SEND`（「送る」Intent）を使用
- 両者は根本的に異なるIntentであり、目的に応じた使い分けが必要
- 開発者が「URLを他のアプリに渡す」という要件に対して適切なAPIを選べない

**Prevention:**
- **タップ → 共有シート表示**: `SharePlus.instance.share(ShareParams(text: url))` — URL文字列をテキストとして送る
- **タップ → ブラウザで開く**: `launchUrl(Uri.parse(url))` — `LaunchMode.externalApplication` で外部ブラウザ起動
- 共有と起動は明確に区別してUIに反映する（アイコンが違う、ラベルが違う）
- 一つのボタンで両方やろうとしない

**Which phase should address it:**
- フェーズ「共有インテグレーション」: 設計時に意図を確定する

---

### Pitfall 9: キーワード管理UIが実用的でなくなりユーザーが離脱する

**What goes wrong:**
キーワードの追加・編集・削除のUXが不十分で、ユーザーが継続して使わなくなる。特に42サイトの横断検索というユースケースでは、検索クエリの「調整」が頻繁に発生する。

**Why it happens (root cause):**
- キーワードの追加が面倒（毎回テキスト入力が必要）
- 複数キーワードのAND/OR組み合わせがUIで表現できない
- 検索結果が多すぎる/少なすぎる場合の調整手段がない
- キーワードの有効/無効を簡単に切り替えられない
- プリセット/テンプレート機能がない

**Consequences:**
- ユーザーがアプリを使い続けず、手動のGoogle検索に戻る
- キーワード管理の煩雑さがアプリの主要な離脱理由になる
- コア価値（「site:演算子の手動貼り付けを置き換える」）が実現できない

**Prevention:**
- **クイック追加**: キーワード入力は1タップで開始、オートフォーカス
- **トグル機能**: 各キーワードの有効/無効を簡単に切り替えられるチップUI
- **プリセット**: よく使うキーワードのテンプレート（「異世界転生」「ダンジョン」「ざまぁ」など）
- **検索結果件数の表示**: 各キーワードの結果件数をプレビュー表示
- **共有クエリの可視化**: 現在の検索クエリ（`site:A OR site:B ... keyword`）をユーザーに表示
- **一括操作**: 全選択/全解除、グループ化

**Which phase should address it:**
- フェーズ「キーワード管理UI」: UX設計の初期段階で考慮する

---

### Pitfall 10: `dart:io HttpClient` のTLS検証がAndroidで失敗する

**What goes wrong:**
特定の小説サイトの証明書が古い、または自己署名証明書を使用している場合、FlutterのデフォルトTLS検証に失敗して接続できない。ただしnovfindは「Google検索結果のURLを共有する」だけなので、実際に各小説サイトにHTTPリクエストを送るわけではない点に注意。

**Why it happens:**
- このアプリは小説サイト自体にアクセスしない（URL共有のみ）
- したがってこの問題はGoogle検索へのアクセスに限定される
- Googleの証明書は正規のCAから発行されているため通常問題にならない
- ただし、プロキシを経由する場合に証明書検証が失敗することがある

**Prevention:**
- Googleへの直接アクセスに限定する限り、デフォルトのTLS設定で問題ない
- プロキシ対応が必要な場合は `IOHttpClientAdapter` の `validateCertificate` を設定する
- 必要以上に `badCertificateCallback` を緩和しない（セキュリティリスク）

**Which phase should address it:**
- フェーズ「検索スクレイピング」: プロキシ対応のときに検討する

---

### Pitfall 11: マルチスレッド/IsolateでのHTTPクライアント共有による問題

**What goes wrong:**
検索処理をバックグラウンドIsolateで実行する場合、メインIsolateで作成したHTTPクライアントが共有できない。または、複数クエリを並列実行する際にコネクションプールが競合する。

**Why it happens:**
- DartのIsolateはメモリを共有しない
- `http.Client` / `Dio` インスタンスはIsolate間で転送できない
- 複数の検索クエリを同時に実行するとレート制限に達しやすい

**Prevention:**
- まずはメインIsolateでシンプルに実装する（Isolateの必要性は後で判断）
- 複数クエリは直列実行 + ランダム遅延で行う
- どうしても並列実行が必要な場合は `Isolate.spawn` 内で新しいHTTPクライアントを作成する
- `compute()` 関数（Flutterのユーティリティ）も検討する

**Which phase should address it:**
- フェーズ「パフォーマンス最適化」: 問題が実際に発生した時点で対応する

---

### Pitfall 12: Cookie未管理によるGoogle検索の個人化問題

**What goes wrong:**
GoogleはCookieに基づいて検索結果を個人化する。Cookieを管理しないと、毎回異なる（あるいは一貫性のない）検索結果が返ってくる。また、Cookieがないリクエストは不自然と判断されブロックされやすくなる。

**Why it happens:**
- `package:http` のデフォルトClientはCookieを保持するが永続化しない
- アプリ再起動ごとに新しいセッションとして扱われる
- 地域や言語設定が反映されず、意図しない結果が返る可能性がある

**Prevention:**
- `dio_cookie_manager` + `cookie_jar`（`PersistCookieJar`）でCookieを永続化する
- アプリ起動時の一貫性を保つ
- `Accept-Language` ヘッダーを設定して言語を明示する（`ja`）

**Which phase should address it:**
- フェーズ「検索スクレイピング」: HTTPクライアント設定に含める

---

### Pitfall 13: エミュレータでの共有テストが不十分でリリース後に問題が発覚する

**What goes wrong:**
エミュレータでは共有先アプリが少ないため、共有機能が正しく動作しているように見える。しかし実機ではアプリ一覧が表示されない、特定アプリに共有できない、などの問題が発生する。

**Why it happens:**
- AOSPエミュレータにはChrome/GmailなどのGoogleアプリがプリインストールされていない
- Google APIsイメージを使っても、プリインストールアプリのバージョンが古い
- 実機のAndroidバージョンによってパッケージ可視性の挙動が異なる
- メーカー固有のカスタマイズ（Samsung/Huawei/Xiaomiなど）でIntent解決の挙動が変わる

**Prevention:**
- Google APIsを含むエミュレータイメージを使用する
- 必ず実機（複数メーカー）でテストする
- Android 11/12/13/14でテストする
- `adb shell dumpsys package` でIntent解決の詳細を確認する
- CI/CDに実機テストを含める（Firebase Test Labなど）

**Which phase should address it:**
- フェーズ「テスト/QA」: 実機テスト計画に含める

---

### Pitfall 14: HTTPクライアントにタイムアウトを設定しない

**What goes wrong:**
ネットワークが不安定な環境で検索リクエストが無限に待機し続ける。ユーザーは「検索中」のまま操作不能になる。

**Why it happens:**
- `package:http` のデフォルトClientはタイムアウト機構を持たない
- `pub.dev` のネットワークは安定しているが、モバイル回線は不安定
- 開発者はデスクトップの安定したネットワークで開発するため気づきにくい

**Prevention:**
- `dio` の `connectTimeout` と `receiveTimeout` を設定する（推奨: 10秒/15秒）
- `package:http` を使う場合は `http.Client` のラッパーにタイムアウトを実装する
- タイムアウト発生時のエラーUIを用意する（「通信がタイムアウトしました。再試行しますか？」）
- リトライボタンを表示する

**Which phase should address it:**
- フェーズ「検索スクレイピング」: HTTPクライアント設定の一環として

---

### Pitfall 15: 大量のsite:演算子がURL長制限を超える

**What goes wrong:**
HTTP GETリクエストのURL長が制限（約8KB）を超え、リクエストが失敗する。またはGoogleが長すぎるクエリを拒否する。

**Why it happens:**
- `site:syosetu.com OR site:kakuyomu.jp OR site:aozora.gr.jp OR ...`（42サイト分）は非常に長い文字列になる
- 各 `site:` 演算子は約15〜25文字
- 42サイト × 平均20文字 = 約840文字（クエリ部分のみ）
- URL全体（`https://www.google.com/search?q=keyword+site:...`）が2000文字を超える可能性がある
- モバイルネットワークやプロキシのURL長制限に引っかかる可能性がある

**Prevention:**
- 42サイトを分割して複数リクエストにする（例: 7サイト×6グループ = 6リクエスト）
- 各グループの結果をクライアント側でマージする
- 重複除去（同一URLが複数グループでヒットした場合）を行う
- クエリ長を事前チェックして警告する

**Which phase should address it:**
- フェーズ「検索スクレイピング」: クエリ分割戦略として

---

## Minor Pitfalls

### Pitfall 16: 結果の重複除去を忘れる

42サイトを分割クエリで検索する場合、同一URLが複数グループでヒットする。重複除去（`Set` または `Map` によるURLのユニーク化）を忘れると、結果一覧に同じ小説が重複表示される。

**Prevention:** `LinkedHashSet` または `Map<String, Result>` でURLをキーにして重複を排除する。

### Pitfall 17: Googleの検索結果ページネーションを考慮しない

Googleの検索結果は1ページあたり約10件。2ページ目以降を取得しないと、実際の該当件数を過小評価する。ただしnovfindのユースケースでは「最初の数件で十分」な可能性が高い。

**Prevention:** MVPでは1ページ目のみ取得で良い。「もっと見る」機能はv2以降で検討。

### Pitfall 18: 検索結果のリンクがGoogleのリダイレクトURLになっている

スクレイピングで取得したリンクURLは `https://www.google.com/url?q=...` 形式のリダイレクトURLであることが多い。これをそのまま共有すると、受信アプリがGoogleのリダイレクトを経由する。

**Prevention:** `url` パラメータから実際のURLを抽出するか、`/url?q=` の `q=` パラメータ値をデコードして取得する。

### Pitfall 19: プロダクションのUser-Agentが古くなる

リリース時に設定したUser-Agent文字列が、ブラウザのバージョンアップに伴い数ヶ月後には「古いUser-Agent」として検出されやすくなる。

**Prevention:** User-Agentは定期的に更新する。バージョン管理し、リリースサイクルごとに確認する。

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| プロジェクトセットアップ | Android NetworkSecurityConfig未設定でHTTPSエラー (#4) | `INTERNET` パーミッション + `network_security_config.xml` をテンプレートに含める |
| 検索スクレイピング | Google HTML構造変更でパース失敗 (#1) | クラス名非依存のセレクタ + テスト自動化 |
| 検索スクレイピング | レート制限/ブロック (#2) | User-Agent設定、ランダム遅延、指数的バックオフ |
| 検索スクレイピング | クエリ長超過 / タイムアウト (#3, #14, #15) | site:演算子を分割、タイムアウト設定 |
| 検索スクレイピング | User-Agent未設定 (#7) | 開発初期から設定 |
| キーワード管理UI | UX不備で離脱 (#9) | チップUI、トグル、プリセット |
| 共有インテグレーション | share_plus/url_launcher誤用 (#8) | 要件定義時に明確化 |
| 共有インテグレーション | Android 11+ パッケージ可視性 (#5) | `<queries>` 宣言 |
| 検索UI | dispose後のsetState (#6) | CancelToken + mountedチェック |
| テスト/QA | エミュレータのみのテスト (#13) | 実機（複数メーカー）でのテスト必須 |
| パフォーマンス最適化 | IsolateでのHTTPクライアント問題 (#11) | メインIsolateで実装、必要になったらIsolate対応 |

## Sources

- Scrapfly - How to scrape Google (2026-04): `scrapfly.io/blog/posts/how-to-scrape-google`
- ScrapingBee - Web scraping without getting blocked (2026-01): `scrapingbee.com/blog/web-scraping-without-getting-blocked`
- ScraperAPI - Scrape Google Search Results (2026-05): `scraperapi.com/web-scraping/scrape-google-search-results`
- [package:http](https://pub.dev/packages/http) — Dart公式HTTPクライアント
- [package:dio](https://pub.dev/packages/dio) — 高機能HTTPクライアント
- [package:html](https://pub.dev/packages/html) — Dart HTML5パーサー
- [package:share_plus](https://pub.dev/packages/share_plus) — Flutter共有プラグイン
- [package:url_launcher](https://pub.dev/packages/url_launcher) — Flutter URL起動プラグイン
- Flutter Networking docs: `docs.flutter.dev/data-and-backend/networking`
- Android Security Config: `developer.android.com/training/articles/security-config`
- Android Package Visibility: `developer.android.com/training/package-visibility`
- Google Crawler Overview: `developers.google.com/crawling/docs/crawlers-fetchers/overview-google-crawlers`
- dart:io HttpClient API: `api.flutter.dev/flutter/dart-io/HttpClient-class.html`
