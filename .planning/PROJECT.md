# novfind

## What This Is

Android向けFlutterアプリ。登録したキーワードで42の日本語小説サイト（syosetu.com, kakuyomu.jp, aozora.gr.jp等）を横断検索し、結果のURLをAndroid共有シート経由で任意のReaderアプリに渡す。

## Core Value

「Google検索にsite:演算子を手動で貼り付ける」を、キーワード登録→ワンタップ検索に置き換える。

## Requirements

### Validated

- ✓ FlutterプロジェクトがAPKビルド可能 — Phase 1
- ✓ 推奨パッケージ（dio, html, share_plus, flutter_riverpod, shared_preferences, flutter_dotenv, go_router）依存解決 — Phase 1
- ✓ 基本モデルクラス（Keyword, SearchResult, SiteConfig）定義 — Phase 1
- ✓ Androidプラットフォーム設定（INTERNET, NetworkSecurityConfig, package visibility） — Phase 2

### Active

- [ ] キーワードをアプリ内に登録・管理できる
- [ ] 登録キーワードで検索を実行できる
- [ ] Google検索のスクレイピングで結果（タイトル＋URL）を取得できる
- [ ] 検索結果が一覧表示される
- [ ] 結果をタップするとAndroid共有シートが開く
- [ ] 共有シートから任意のアプリにURLを渡せる

### Out of Scope

- 小説の閲覧・本文表示 — 他アプリに任せる
- iOS対応 — v1はAndroidのみ
- 検索結果の履歴保存 — 現時点では対象外
- ユーザー認証・ログイン

## Context

- 現在は`.env`の長い検索クエリ（`site:syosetu.com OR site:kakuyomu.jp OR ...`）を手動でGoogle検索に貼り付けている
- 42もの小説投稿サイト・青空文庫・ Wikisource等を対象とする
- キーワードは複数登録でき、それらを組み合わせて検索する

## Constraints

- **Platform**: Android only（Flutter）
- **Search method**: Google検索結果のWeb scraping（API非使用）
- **Sharing**: Android標準共有シート（Intent.ACTION_SEND）
- **Data source**: `.env` に定義された `site:` 演算子のOR結合クエリ

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter | クロスプラットフォームだがv1はAndroidに集中 | — Pending |
| Web scraping over API | Google Custom Search APIはコスト・クエリ制限がある | — Pending |
| URL共有のみ | コンテンツ取得・表示は専門アプリに委ねる | — Pending |

---

*Last updated: 2026-07-11 after initialization*
