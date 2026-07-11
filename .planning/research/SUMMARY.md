# Project Research Summary

**Project:** novfind — Flutter Android novel search aggregator
**Domain:** Mobile search aggregator for Japanese web novels (Android)
**Researched:** 2026-07-11
**Confidence:** MEDIUM-HIGH

## Executive Summary

novfind is an Android Flutter app that replaces a manual workflow — copying a 42-site `site:` OR query from `.env`, pasting it into Google Search, appending a keyword, scanning results, and manually sharing URLs to reader apps. The app automates the query assembly and search execution, and streamlines the sharing step via Android Share Sheet. Experts build this type of app using MVVM + Repository architecture with Riverpod for state management, dio for HTTP (with interceptor-based User-Agent/retry handling), and the `html` package for DOM parsing of Google SERP results.

The recommended approach is a phased build: start with project foundation and keyword CRUD (low-risk, establishes the data model), then build the scraping engine (the highest-risk component — Google actively blocks automated requests), then wire up the search results UI and share integration to complete the MVP. The core technical risk is Google's anti-scraping posture: HTML structure changes without notice, rate limiting/CAPTCHA, and bot detection via User-Agent fingerprinting. Mitigations include class-name-independent HTML selectors, randomized request delays, proper User-Agent setting, exponential backoff on 429 responses, and a graceful fallback UI when scraping fails.

A secondary but critical risk is Android platform configuration: `INTERNET` permission, `NetworkSecurityConfig` for HTTPS, and `<queries>` declarations for package visibility on Android 11+ must be set correctly from the start to avoid silent failures in production. The app has no backend, no authentication, and no novel content storage — it is purely a search orchestration + URL sharing tool, which keeps the security surface small but makes the Google scraping reliability the single point of failure.

## Key Findings

### Recommended Stack

**Core framework:** Flutter 3.44.0+ / Dart 3.12.0+ — stable, excellent Android support, sound null safety.

**Key packages (all verified from pub.dev, HIGH confidence):**

| Technology | Version | Purpose | Rationale |
|------------|---------|---------|-----------|
| dio | ^5.10.0 | HTTP client for scraping | Interceptor chain for User-Agent, retry, logging — critical for Google scraping |
| html | ^0.15.6 | HTML DOM parsing | Official dart-lang package, querySelector API, HTML5 spec compliant |
| share_plus | ^13.2.0 | Android share sheet | Wraps `Intent.ACTION_SEND`, Flutter Favorite, mature API |
| flutter_riverpod | ^3.3.2 | State management | Async-native (`AsyncValue`), compile-safe, no boilerplate — right-sized for ~4 providers |
| shared_preferences | ^2.5.5 | Local keyword storage | Built-in `setStringList`/`getStringList`, zero boilerplate for flat string data |
| flutter_dotenv | ^5.2.1 | Environment config | Keep 42-site query separate from code |
| go_router | (latest) | Declarative routing | Deep-linkable, parameter parsing, Flutter team recommended |

**What NOT to use:** `provider` (unmaintained), `bloc` (overengineered), `flutter_html` (renders HTML, doesn't parse), `url_launcher` for sharing (opens browser, not share sheet), `hive`/`drift` (relational DB overkill for string lists), `flutter_secure_storage` (keywords are not secrets).

### Expected Features

**Must have (table stakes) — all LOW-MEDIUM complexity:**
- Keyword CRUD (create, rename, delete) — core interaction
- Keyword list display — at-a-glance view
- One-tap search execution — the primary action, replaces paste-to-Google
- Search results list (title + URL + source-site label)
- Android Share Sheet on result tap — core value prop
- Loading/Error/Empty states — essential for scraper reliability UX
- Pull-to-refresh / re-search — stale results refresh
- Source-site label on each result — shows which of 42 sites

**Should have (differentiators):**
- **D1 — 42-site cross-search in one tap** (MEDIUM complexity, core differentiator, the entire reason the app exists)
- D2 — Multi-keyword search (AND combination)
- D3 — Source-site toggles/filters before search
- D4 — Result deduplication (fuzzy title matching for cross-posted novels)
- D5 — Copy URL to clipboard
- D6 — Open in browser (secondary action)
- D7 — Search presets (keyword + filter combinations)
- D9 — Recent searches (in-memory, session-only)
- D10 — Favorite/bookmark results
- D11 — Result ranking by site priority
- D12 — Dark mode
- D13 — Search within results (client-side text filter)
- D14 — Result count per site badge

**Anti-features (explicitly NOT building):** In-app browser/WebView, content reader, download/offline, user auth, analytics, push notifications, social features, EPUB/PDF export, iOS v1, Google Custom Search API (paid).

**Build order dependencies:** Keyword CRUD → Search Execution → Results List → Share Sheet form the critical path for MVP validation. All differentiators depend on the core search+share flow being complete first.

### Architecture Approach

**Pattern:** MVVM with Repository pattern (Flutter's official app architecture guide recommendation).

**Major components:**

1. **Models (domain layer)** — `Keyword`, `SearchResult`, `SiteConfig` — pure Dart data classes, no logic
2. **KeywordRepository** — CRUD for keywords via `SharedPreferencesAsync`, single source of truth
3. **GoogleSearchService** — HTTP GET to Google, HTML parse via `package:html`, extract title/URL/snippet — the riskiest component
4. **ShareService** — Wraps `share_plus` `SharePlus.instance.share()` for Android share sheet
5. **ViewModels** (Riverpod providers) — `KeywordList`, `SearchResults`, `AddKeyword` — hold state, expose commands
6. **Views** (Flutter widgets) — `KeywordListScreen`, `SearchResultScreen`, `AddKeywordSheet` — minimal logic, delegate to ViewModels

**Key patterns:**
- Repository as single source of truth (never access SharedPreferences/HTTP from views)
- ViewModel commands (`Future<void>` functions exposed to views)
- Error handling via Riverpod `AsyncValue.when(data:error:loading:)` in every screen
- Dependency injection via Riverpod `ProviderContainer` overrides in tests
- `go_router` for declarative navigation with path parameters

**Project structure:** Feature-based UI grouping (`lib/ui/<feature>/view_models/`, `lib/ui/<feature>/widgets/`), type-based data grouping (`lib/data/repositories/`, `lib/data/services/`).

### Critical Pitfalls

1. **Google HTML structure changes break parsing (CRITICAL).** Google changes SERP CSS classes/IDs without notice — sometimes multiple times per month. Fixed CSS selectors will break silently, returning zero results. **Mitigation:** Use class-name-independent selectors (`<h3>` headings, stable `data-*` attributes, embedded JSON data), centralize parsing logic in testable units, add CI tests to detect structure changes, provide fallback UI.

2. **Google rate limiting / IP blocking (CRITICAL).** 42-site queries trigger excessive requests from one IP. Flutter's default `Dart/<version>` User-Agent is instantly detected as a bot. **Mitigation:** Set modern browser User-Agent, enforce 2-5s random delays between requests, implement exponential backoff on 429/403, cache identical queries, show user guidance against rapid searches.

3. **42 `site:` operator query too long / URL exceeds limits (CRITICAL).** The combined `site:syosetu.com OR site:kakuyomu.jp OR ...` query from `.env` can exceed URL length limits (~8KB), causing Google to reject or silently truncate the query. **Mitigation:** Split 42 sites into groups (e.g., 7 sites × 6 groups), send multiple requests, merge + deduplicate results client-side.

4. **Android 11+ package visibility blocks share sheet (MODERATE).** Without `<queries>` declaration in `AndroidManifest.xml`, `share_plus` cannot detect apps that handle `ACTION_SEND` on Android 11+. **Mitigation:** Add `<queries>` for `android.intent.action.SEND` with `text/plain` MIME type — do NOT use `QUERY_ALL_PACKAGES`.

5. **User-Agent not set → bot detection (MODERATE).** Flutter default `Dart/<version>` User-Agent guarantees Google blocking. **Mitigation:** Set modern browser User-Agent via dio `BaseOptions.headers` from day one of implementation.

6. **dispose後的 setState エラー (MODERATE).** If user navigates away during search, widget may call `setState` after disposal. **Mitigation:** Use dio `CancelToken`, check `mounted` guard, rely on Riverpod lifecycle management instead of `StatefulWidget.setState`.

## Implications for Roadmap

### Suggested Phase Structure

#### Phase 1: Project Foundation & Android Scaffold
**Rationale:** Every other phase depends on the project being set up correctly. Android platform config (INTERNET permission, NetworkSecurityConfig) must be in place before any HTTP requests are made. This phase has zero external risk and establishes patterns.
**Delivers:** Flutter project scaffold, models (`Keyword`, `SearchResult`, `SiteConfig`), Android manifest config, dependency declaration in `pubspec.yaml`, `.env` loading, directory structure.
**Addresses:** Foundation work for all features.
**Avoids:** Pitfall #4 (NetworkSecurityConfig) — set up correctly from the start.
**Stack used:** Flutter scaffold, flutter_dotenv.
**Research flag:** STANDARD — well-documented Flutter project setup patterns. No need for `/gsd-plan-phase --research-phase`.

#### Phase 2: Keyword Management (Input Half)
**Rationale:** Keywords are the user's primary input. This phase establishes the data layer (KeywordRepository with SharedPreferences) and the first screen (KeywordListScreen). It's self-contained, low-risk, and gives the user something to interact with immediately. The keyword CRUD can be tested independently of the scraping engine.
**Delivers:** Keyword CRUD (add/list/delete), KeywordListScreen, AddKeywordSheet, SharedPreferences persistence, Riverpod provider setup for keyword state.
**Addresses:** Table stakes #1 (Keyword CRUD), #2 (Keyword list display).
**Avoids:** Pitfall #9 (keyword UX abandonment) — start with clean CRUD, expand in later phases.
**Stack used:** shared_preferences, flutter_riverpod.
**Research flag:** STANDARD — CRUD + list is a solved Flutter pattern. No research-phase needed.

#### Phase 3: Scraping Engine (Highest Risk)
**Rationale:** This is the most technically risky component and should be built and tested in isolation before any UI is wired to it. The GoogleSearchService must handle: 42-site query splitting, User-Agent configuration, timeout settings, retry logic, CAPTCHA detection, and resilient HTML parsing. Building this standalone allows aggressive testing without UI complexity.
**Delivers:** GoogleSearchService with query builder (42-site split strategy), dio HTTP client with interceptor chain, HTML parser with class-name-independent selectors, result deduplication logic, error type classification (network vs captcha vs empty).
**Addresses:** Table stakes #3 (one-tap search execution — backend half), #9 (source-site labeling — parsing).
**Avoids:** Pitfall #1 (HTML structure changes — resilient selectors), #2 (rate limiting — delays + backoff), #3 and #15 (query length — site splitting strategy), #7 (User-Agent — set from start), #14 (timeout — configured), #12 (cookie management — dio_cookie_manager consideration).
**Stack used:** dio, html, flutter_dotenv (site config loading).
**Research flag:** **NEEDS DEEP RESEARCH** — `/gsd-plan-phase --research-phase` required. Specifically needs investigation of:
- Current Google SERP HTML structure and stable selectors
- Google's tolerance for automated requests from Android IP ranges
- Whether `dio_cookie_manager` + `jar` is needed for session persistence
- Whether splitting into 6 groups × 7 sites is the right granularity

#### Phase 4: Search Results UI + Share Integration (MVP Complete)
**Rationale:** With the scraping engine working, wire it to the UI. This phase connects the keyword list (Phase 2) to the search service (Phase 3) and adds the share action. After this phase, the end-to-end MVP flow works: keyword → search → results → share.
**Delivers:** SearchResultScreen with loading/error/empty states, SearchResultViewModel, ShareService with share_plus integration, pull-to-refresh, source-site labels on results, result tap → Android share sheet.
**Addresses:** Table stakes #4 (results list), #5 (share sheet), #6 (loading state), #7 (error state), #8 (empty state), #10 (pull-to-refresh), #9 (source-site labels). Differentiators D5 (copy URL), D6 (open in browser).
**Avoids:** Pitfall #5 (package visibility — `<queries>` setup in Phase 1 pays off here), #6 (dispose/setState — Riverpod handles lifecycle), #8 (share_plus vs url_launcher misuse — clear separation from design), #13 (emulator testing — test on real device).
**Stack used:** share_plus, go_router.
**Research flag:** STANDARD — share_plus and go_router have well-documented APIs. However, **Android 11+ package visibility must be verified on a physical device** during testing.

#### Phase 5: Power Features & UX Polish
**Rationale:** Once the core flow is validated (Phase 4), expand the feature set. These features are independent of each other and can be built in any order. Prioritize based on user feedback from Phase 4.
**Delivers:** Multi-keyword search (D2), source-site toggles UI (D3), recent searches (D9), favorite/bookmark results (D10), dark mode (D12), search within results (D13), result count per site badge (D14), result deduplication (D4), result ranking (D11).
**Addresses:** Differentiators D2-D6, D9-D14.
**Avoids:** Pitfall #16 (dedup — implement LinkedHashSet by URL), anti-features (no in-app browser, no content reader).
**Stack used:** All existing — no new packages required except possibly `collection` for `LinkedHashSet`.
**Research flag:** STANDARD for most features. Source-site toggles (D3) needs a UI pattern decision (chips vs checkboxes vs multi-select) — could be done as part of planning without a full research phase.

#### Phase 6: Advanced Features (Post-Validation)
**Rationale:** These features only make sense if the app has proven useful (Phase 4 validated). Search presets (D7) and home screen widget (D8) are complex and should be deferred until user demand is confirmed.
**Delivers:** Search presets (save keyword + filter combinations), Android home screen widget (quick-search with favorite keyword).
**Addresses:** Differentiators D7, D8.
**Avoids:** Anti-features — no analytics, auth, or social added.
**Research flag:** **NEEDS DEEP RESEARCH for D8 (widget)** — Android App Widgets in Flutter have limited support and may need native code (`home_widget` package) or platform channels. Investigate `home_widget` vs `flutter_app_widgets` vs native `AppWidgetProvider`.

### Phase Ordering Rationale

- **Dependency-driven:** Phase 2 (keywords) and Phase 3 (scraping) are independent — they can be built in parallel if resources allow. But Phase 4 (search UX) requires both.
- **Risk isolation:** Phase 3 (scraping) is the highest risk and is isolated so it can be tested independently. If scraping proves infeasible (Google blocks everything), only Phase 3 is wasted, not the entire app.
- **Validation before polish:** Phase 4 delivers the complete MVP. Only if Phase 4 shows user engagement should Phase 5-6 be pursued.
- **Android config first:** Network permission and package visibility setup in Phase 1 prevent mysterious failures in later phases.

### Research Flags

| Phase | Needs Research? | Reason |
|-------|----------------|--------|
| Phase 1: Foundation | No | Standard Flutter setup, well-documented |
| Phase 2: Keywords | No | Solved pattern (Riverpod CRUD + SharedPreferences) |
| Phase 3: Scraping | **YES** | Google anti-scraping posture, SERP structure, rate limit thresholds |
| Phase 4: Search UI | No (test on real device) | share_plus/go_router are well-documented; physical device testing critical |
| Phase 5: Power Features | No | Standard Flutter patterns, no new packages |
| Phase 6: Advanced | **YES** (widget) | Android App Widgets in Flutter need dedicated research |

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All package versions verified from pub.dev official pages. Alternatives analysis documented. |
| Features | **MEDIUM** | Table stakes are HIGH (standard search app patterns). Differentiators are MEDIUM (unvalidated with real users). Google scraping viability is LOW — the biggest unknown. |
| Architecture | **HIGH** | Follows Flutter's official app architecture guide and case study. Pattern choices (Riverpod, Repository, MVVM) are well-established for this app scale. |
| Pitfalls | **MEDIUM** | Well-researched from scraping industry sources (Scrapfly, ScrapingBee, ScraperAPI). However, Google's actual anti-scraping posture changes frequently — prevention strategies are best-effort, not guaranteed. Android platform pitfalls are HIGH confidence. |

**Overall confidence: MEDIUM-HIGH**

The stack, architecture, and feature categorization are well-understood. The primary uncertainty is **Google scraping viability** — the app's core value proposition depends on Google not blocking the automated requests. This is a genuine risk that cannot be fully resolved in research; it must be tested empirically in Phase 3.

### Gaps to Address

- **Google scraping viability (CRITICAL GAP):** No empirical testing has been done. Phase 3 must include a spike/prototype that tests: (a) whether Google serves results to a dio client with a mobile User-Agent, (b) how many requests per minute are tolerated before blocking, (c) whether CAPTCHA is triggered, and (d) whether the HTML structure is parseable with resilient selectors. If scraping proves infeasible, the entire app concept needs re-evaluation (paid API or alternative search engine).
- **42-site query length (HIGH PRIORITY GAP):** The actual `.env` query string needs to be measured. If it exceeds URL length limits, the site-splitting strategy must be implemented from Phase 3. If it fits within limits, the simpler single-request approach can be used initially. This should be verified before Phase 3 implementation.
- **Android version fragmentation (MEDIUM GAP):** Testing plan needed for Android 11/12/13/14 across multiple device manufacturers (Samsung, Pixel, Xiaomi). The share sheet behavior varies by vendor ROM. This cannot be fully researched — it needs empirical testing.
- **User validation (MEDIUM GAP):** Features D2-D14 are best-guess differentiators. Real user feedback after Phase 4 should drive Phase 5 priorities. No assumptions should be made about which differentiators matter most.

## Sources

### Primary (HIGH confidence)
- **Flutter App Architecture Guide** — `docs.flutter.dev/app-architecture/guide` — MVVM + Repository recommendation
- **Flutter Architecture Case Study** — `docs.flutter.dev/app-architecture/case-study` — Package structure convention
- **pub.dev** — All package versions verified (dio 5.10.0, html 0.15.6, share_plus 13.2.0, flutter_riverpod 3.3.2, shared_preferences 2.5.5, flutter_dotenv 5.2.1, go_router)
- **Flutter 3.44.0 / Dart 3.12.0** — `docs.flutter.dev/release/breaking-changes/3-13-deprecations`

### Secondary (MEDIUM confidence)
- **Scrapfly — How to scrape Google (2026-04)** — `scrapfly.io/blog/posts/how-to-scrape-google` — SERP parsing strategies
- **ScrapingBee — Web scraping without getting blocked (2026-01)** — `scrapingbee.com/blog/web-scraping-without-getting-blocked` — Rate limiting, User-Agent, proxy strategies
- **ScraperAPI — Scrape Google Search Results (2026-05)** — `scraperapi.com/web-scraping/scrape-google-search-results` — Anti-blocking best practices
- **Android Security Config** — `developer.android.com/training/articles/security-config`
- **Android Package Visibility** — `developer.android.com/training/package-visibility`

### Tertiary (LOW confidence — needs validation)
- **Google scraping viability on Android** — No empirical data available. Must be tested in Phase 3 spike.
- **Competitor landscape for Japanese novel search aggregator** — No direct competitor found on Play Store (gap may be real or undiscovered).

---

*Research completed: 2026-07-11*
*Ready for roadmap: yes*
