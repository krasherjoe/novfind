# Roadmap: novfind

## Overview

novfindは、42の日本語小説サイトを横断検索するAndroid Flutterアプリ。キーワード登録→ワンタップ検索→共有シートでReaderアプリにURLを渡す、という一連の流れを提供する。Phase 1→9で段階的に構築し、最高リスクのスクレイピングエンジン（Phase 5）を早期に隔離プロトタイプしてからUIを構築する。

## Phases

- [ ] **Phase 1: Flutter Scaffold** - プロジェクト作成、ディレクトリ構造、モデル定義
- [ ] **Phase 2: Android Platform Config** - NetworkSecurityConfig/INTERNET/package visibility設定
- [ ] **Phase 3: Environment & Dependencies** - .env読み込み、pubspec依存関係
- [ ] **Phase 4: Keyword Management** - キーワードCRUD + SharedPreferences永続化
- [ ] **Phase 5: Scraping Engine Prototype** - Google検索スクレイピングの隔離プロトタイプ（最高リスク）
- [ ] **Phase 6: Search Execution & States** - キーワード選択→検索実行、ローディング/エラー/空状態UI
- [ ] **Phase 7: Results Display** - 検索結果のタイトル+URL一覧表示、pull-to-refresh
- [ ] **Phase 8: Source Site Labels** - 各結果に取得元サイト名ラベル表示
- [ ] **Phase 9: Share Integration** - 結果タップ→Android共有シート→任意アプリにURL共有

## Phase Details

### Phase 1: Flutter Scaffold
**Goal**: Android向けFlutterプロジェクトがコンパイル可能な状態でセットアップされる
**Mode**: mvp
**Depends on**: Nothing (first phase)
**Requirements**: BASE-01
**Success Criteria** (what must be TRUE):
  1. `flutter build apk --debug` がエラーなく成功する
  2. 推奨パッケージがpubspec.yamlに宣言され、`flutter pub get` が成功する（dio, html, share_plus, flutter_riverpod, shared_preferences, flutter_dotenv, go_router）
  3. lib/以下にデータ層・UI層・モデルのディレクトリ構造が作成されている
  4. 基本モデルクラス（Keyword, SearchResult, SiteConfig）が定義されている
**Plans**: TBD

### Phase 2: Android Platform Config
**Goal**: Androidアプリがネットワークアクセスと他アプリ連携に必要な設定を備える
**Mode**: mvp
**Depends on**: Phase 1
**Requirements**: BASE-02, BASE-03, BASE-04
**Success Criteria** (what must be TRUE):
  1. INTERNETパーミッションがAndroidManifest.xmlに宣言されている
  2. Android 9+のNetworkSecurityConfigが設定され、全HTTPS接続が許可されている
  3. Android 11+の`<queries>`宣言により共有シートがACTION_SENDを処理するアプリを検出できる
  4. Androidエミュレータ/実機でアプリが起動し、ネットワーク権限が正しく機能している
**Plans**: TBD

### Phase 3: Environment & Dependencies
**Goal**: アプリ設定と外部パッケージ依存関係が整う
**Mode**: mvp
**Depends on**: Phase 1
**Requirements**: BASE-05
**Success Criteria** (what must be TRUE):
  1. .envファイルから42サイトのsite:演算子OR結合クエリが読み込まれる
  2. 全依存関係が `flutter pub get` でエラーなく解決される
  3. 環境変数が未設定の場合のフォールバック処理が機能する（空リストを返す等）
  4. クエリ文字列長が確認可能で、分割戦略の要否判断ができる
**Plans**: TBD

### Phase 4: Keyword Management
**Goal**: ユーザーが検索キーワードをアプリ内で登録・管理できる
**Mode**: mvp
**Depends on**: Phase 3
**Requirements**: KW-01, KW-02, KW-03, KW-04
**Success Criteria** (what must be TRUE):
  1. ユーザーはキーワードをテキスト入力から追加できる
  2. ユーザーは登録済みキーワードの一覧をスクロール可能なリストで表示できる
  3. ユーザーはキーワードを削除できる（スワイプまたは削除ボタン）
  4. アプリ再起動後もSharedPreferencesに保存されたキーワードが復元される
**Plans**: TBD
**UI hint**: yes

### Phase 5: Scraping Engine Prototype
**Goal**: Google検索スクレイピングが単体で動作し、結果（タイトル・URL）が正しくパースされることを検証する
**Mode**: mvp
**Depends on**: Phase 3
**Requirements**: SRCH-02
**Success Criteria** (what must be TRUE):
  1. .envのsite:クエリとキーワードを結合したGoogle検索URLが正しく構築される
  2. Google SERPのHTMLからタイトルとURLが抽出される（クラス名非依存のセレクタ使用）
  3. 42サイトのクエリが長すぎる場合、適切なグループに分割して複数リクエストを送信する
  4. スクレイピング失敗時のエラー種別（network / CAPTCHA / empty / parse error）が分類される
  5. 単体テストでUser-Agent設定・リトライ・レート制限遅延が検証されている
**Plans**: TBD

### Phase 6: Search Execution & States
**Goal**: ユーザーがキーワードを選択して検索を実行し、結果が得られるまでの状態（ローディング・エラー・空）を確認できる
**Mode**: mvp
**Depends on**: Phase 4, Phase 5
**Requirements**: SRCH-01, SRCH-03, SRCH-04, SRCH-05
**Success Criteria** (what must be TRUE):
  1. ユーザーはキーワード一覧から任意のキーワードをタップして検索を開始できる
  2. 検索中はインジケータ（CircularProgressIndicator等）が表示される
  3. ネットワークエラー・スクレイピング拒否等が発生した場合、ユーザーに理解可能なエラーメッセージが表示される
  4. 検索結果が0件の場合、「結果が見つかりませんでした」等の空状態メッセージが表示される
**Plans**: TBD
**UI hint**: yes

### Phase 7: Results Display
**Goal**: 検索結果がタイトルとURLの一覧としてスクロール可能に表示され、pull-to-refreshで再取得できる
**Mode**: mvp
**Depends on**: Phase 6
**Requirements**: RES-01, SRCH-06
**Success Criteria** (what must be TRUE):
  1. 検索結果がタイトルとURLを含むスクロール可能なリストで表示される
  2. タイトルはタップ可能なテキストとして表示される（後続Phaseで共有アクションに発展）
  3. ユーザーはリストを下に引く（pull-to-refresh）ことで再検索を実行できる
**Plans**: TBD
**UI hint**: yes

### Phase 8: Source Site Labels
**Goal**: 各検索結果に取得元のサイト名が表示され、結果がどのサイトからのものかひと目で分かる
**Mode**: mvp
**Depends on**: Phase 7
**Requirements**: RES-02
**Success Criteria** (what must be TRUE):
  1. 各結果に取得元サイト名（syosetu.com / kakuyomu.jp / aozora.gr.jp 等）がラベルとして表示される
  2. サイト名はURLのドメインから自動抽出される
  3. 未知のドメインの場合もドメインそのものがフォールバック表示される
**Plans**: TBD
**UI hint**: yes

### Phase 9: Share Integration
**Goal**: 結果タップでAndroid共有シートが開き、URLを任意のアプリに渡せる
**Mode**: mvp
**Depends on**: Phase 7
**Requirements**: RES-03, SHARE-01, SHARE-02
**Success Criteria** (what must be TRUE):
  1. 検索結果のアイテムをタップするとAndroid標準共有シートが開く
  2. 共有シートには結果のタイトルとURLがテキストとして含まれる
  3. 共有シートから任意のアプリ（Chrome, Firefox, Readerアプリ等）にURLを渡せる
  4. Android 11/12/13/14の実機で共有が機能することを確認済み
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Flutter Scaffold | 0/0 | Not started | - |
| 2. Android Platform Config | 0/0 | Not started | - |
| 3. Environment & Dependencies | 0/0 | Not started | - |
| 4. Keyword Management | 0/0 | Not started | - |
| 5. Scraping Engine Prototype | 0/0 | Not started | - |
| 6. Search Execution & States | 0/0 | Not started | - |
| 7. Results Display | 0/0 | Not started | - |
| 8. Source Site Labels | 0/0 | Not started | - |
| 9. Share Integration | 0/0 | Not started | - |
