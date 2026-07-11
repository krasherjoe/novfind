# Requirements: novfind

**Defined:** 2026-07-11
**Core Value:** 「Google検索にsite:演算子を手動で貼り付ける」を、キーワード登録→ワンタップ検索に置き換える

## v1 Requirements

### キーワード管理

- [ ] **KW-01**: ユーザーは検索キーワードをアプリに登録できる
- [ ] **KW-02**: ユーザーは登録済みキーワードの一覧を表示できる
- [ ] **KW-03**: ユーザーは登録済みキーワードを削除できる
- [ ] **KW-04**: キーワードはアプリ再起後も永続化される

### 検索実行

- [ ] **SRCH-01**: ユーザーは特定のキーワードを選択して検索を実行できる
- [ ] **SRCH-02**: 検索には`.env`のsite:演算子クエリが使用される
- [ ] **SRCH-03**: 検索中はローディングインジケータが表示される
- [ ] **SRCH-04**: 検索エラー時はユーザーに適切なエラーが表示される
- [ ] **SRCH-05**: 空の結果時はその旨が表示される
- [ ] **SRCH-06**: 検索結果はpull-to-refreshで再取得できる

### 検索結果表示

- [ ] **RES-01**: 検索結果はタイトルとURLの一覧で表示される
- [ ] **RES-02**: 各結果には取得元サイト名が表示される
- [ ] **RES-03**: 結果はタップ可能でAndroid共有シートが開く

### 共有

- [ ] **SHARE-01**: 結果タップでAndroid共有シート（ACTION_SEND）が開く
- [ ] **SHARE-02**: 共有シートから任意のアプリにURLを渡せる

### プロジェクト基盤

- [x] **BASE-01**: FlutterプロジェクトがAndroidターゲットでセットアップされる
- [x] **BASE-02**: Android 9+のNetworkSecurityConfigが設定される
- [x] **BASE-03**: Android 11+のpackage visibility（<queries>）が設定される
- [x] **BASE-04**: INTERNETパーミッションが設定される
- [x] **BASE-05**: アセットからクエリ文字列が読み込まれる

## v2 Requirements

### 機能強化

- **PWR-01**: 複数キーワードのAND検索
- **PWR-02**: 検索対象サイトのON/OFFフィルター
- **PWR-03**: お気に入り検索結果の保存
- **PWR-04**: 最近の検索履歴
- **PWR-05**: ダークモード対応
- **PWR-06**: 重複結果の除去
- **PWR-07**: 結果の並び替え
- **PWR-08**: 検索プリセット機能
- **PWR-09**: ホーム画面ウィジェット

## Out of Scope

| 機能 | 理由 |
|------|------|
| 小説本文の表示・閲覧 | 専用Readerアプリに任せる |
| iOS対応 | v1はAndroidのみ。Flutterだがスコープ外 |
| ユーザー認証・ログイン | 不要。ローカル完結 |
| アナリティクス・トラッキング | プライバシー重視、不要 |
| プッシュ通知 | 非同期的な処理がない |
| バックエンドサーバー | 全処理を端末内で完結 |
| Google Custom Search API | コストとクエリ制限のためスクレイピングを選択 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BASE-01 | Phase 1: Flutter Scaffold | Complete ✓ |
| BASE-02 | Phase 2: Android Platform Config | Complete ✓ |
| BASE-03 | Phase 2: Android Platform Config | Complete ✓ |
| BASE-04 | Phase 2: Android Platform Config | Complete ✓ |
| BASE-05 | Phase 3: Environment & Dependencies | Complete ✓ |
| KW-01 | Phase 4: Keyword Management | Pending |
| KW-02 | Phase 4: Keyword Management | Pending |
| KW-03 | Phase 4: Keyword Management | Pending |
| KW-04 | Phase 4: Keyword Management | Pending |
| SRCH-02 | Phase 5: Scraping Engine Prototype | Pending |
| SRCH-01 | Phase 6: Search Execution & States | Pending |
| SRCH-03 | Phase 6: Search Execution & States | Pending |
| SRCH-04 | Phase 6: Search Execution & States | Pending |
| SRCH-05 | Phase 6: Search Execution & States | Pending |
| RES-01 | Phase 7: Results Display | Pending |
| SRCH-06 | Phase 7: Results Display | Pending |
| RES-02 | Phase 8: Source Site Labels | Pending |
| RES-03 | Phase 9: Share Integration | Pending |
| SHARE-01 | Phase 9: Share Integration | Pending |
| SHARE-02 | Phase 9: Share Integration | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0 ✓

---

*Requirements defined: 2026-07-11*
*Last updated: 2026-07-11 after initial definition*
