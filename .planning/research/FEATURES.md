# Feature Landscape

**Domain:** Mobile search aggregator for Japanese web novels (Android)
**Researched:** 2026-07-11
**Mode:** Ecosystem (Project Research)

## Context

novfind is NOT a novel reader — it replaces the manual workflow of:

1. Copying a giant `site:syosetu.com OR site:kakuyomu.jp OR ...` query from `.env`
2. Pasting it into Google Search
3. Appending a keyword by hand
4. Scanning results for relevant URLs
5. Manually sharing URLs to reader apps

The app automates steps 1–3 and streamlines step 5 via Android Share Sheet.

## Table Stakes

Features users expect. Missing these = app feels broken or useless.

| # | Feature | Why Expected | Complexity | Notes |
|---|---------|--------------|------------|-------|
| 1 | **Keyword CRUD** — create, rename, delete search keywords | Core interaction; without this the app has no input | Low | Free-text input, no validation beyond non-empty |
| 2 | **Keyword list display** — see all registered keywords at a glance | Must know what you have | Low | Simple list with edit/swipe-delete |
| 3 | **One-tap search execution** — tap keyword → runs search across all 42 sites | Primary action; replaces paste-to-Google workflow | Medium | Calls Google Search with `keyword + site:...` query |
| 4 | **Search results list** — titles + URLs + source site name | Must see what you found | Medium | Parsed from Google SERP (title, URL, snippet) |
| 5 | **Android Share Sheet on result tap** — tap result → system share picker | Core value prop: get URL into reader apps | Medium | `Intent.ACTION_SEND` with `text/plain` URL |
| 6 | **Loading state** during search — spinner/progress indicator | Users need to know search is running | Low | Critical: Google scraping is slow (2–10s) |
| 7 | **Error state** — failed search, no results, network error | Without this, app feels broken | Low | Differentiate "no results" from "search failed" |
| 8 | **Empty state** — no keywords registered yet, no results yet | Onboarding cue | Low | First-launch guidance |
| 9 | **Source-site label on results** — show which of the 42 sites each result comes from | Users need to know where a link goes | Low | Parse URL domain → human-readable site name |
| 10 | **Pull-to-refresh or re-search** — re-run same keyword search | Stale results need refresh | Low | Standard mobile pattern |

**Complexity legend:** Low = <1 day, Medium = 2–5 days, High = 1+ weeks

## Differentiators

Features that set novfind apart from "just bookmarks + manual Google search."

| # | Feature | Value Proposition | Complexity | Notes |
|---|---------|-------------------|------------|-------|
| D1 | **42-site cross-search in one tap** | Eliminates the copy-paste of the 42-site OR query | Medium | The entire reason the app exists |
| D2 | **Multi-keyword search (AND combination)** — select 2+ keywords → search for both | Find novels across multiple themes/characters | Medium | `keyword1 keyword2 site:...` — Google AND is implicit space |
| D3 | **Source-site toggles/filters** — include/exclude specific sites before search | User may want to search only syosetu.com + kakuyomu.jp | Medium | UI: toggle chips or checkboxes per site |
| D4 | **Result deduplication** — same novel title appearing from multiple sites → collapse or rank | Syosetu cross-posts to multiple sites; deduped results are cleaner | Medium-High | Fuzzy title matching; show source-site badge group |
| D5 | **Copy URL to clipboard** — long-press or secondary action on result | Quick copy without opening share sheet | Low | Context action on result row |
| D6 | **Open in browser** — secondary action alongside share | Sometimes user just wants to preview | Low | Standard `Intent.ACTION_VIEW` |
| D7 | **Search presets** — save keyword + site-filter combinations as named presets | "I always search syosetu for isekai fantasy" | Medium | Named configs, reusable |
| D8 | **Quick-search widget** — home screen widget with favorite keyword | Power-user pattern: search without opening app | High | Android App Widget; needs separate research |
| D9 | **Recent searches** — list of last N searches with results cached | Retry without re-searching | Low | In-memory or local DB |
| D10 | **Favorite/bookmark results** — save individual results for later | "I'll read this later" — common reading workflow | Low | Local-only, no sync needed |
| D11 | **Result ranking by site priority** — user can set order (e.g., syosetu → kakuyomu → aozora) | Control over which sites' results appear first | Low | Per-site weight or drag-to-order |
| D12 | **Dark mode** — better reading experience at night | Standard for content-focused apps | Low | Flutter `ThemeMode.dark` |
| D13 | **Search within results** — filter displayed results by keyword | Found 100 results from "異世界" → narrow to "転生" | Low | Client-side text filter |
| D14 | **Result count per site** — show "(12)" badge next to each site name | "Syosetu has 12 results, Kakuyomu has 3" | Low | Group results by domain, count |

## Anti-Features

Features to explicitly NOT build. These conflict with the app's focused value proposition.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **In-app browser / WebView** | Duplicates reader app functionality; adds WebView complexity (cookies, cache, permissions) | Open in browser or share to reader |
| **Content reader / novel display** | 42 sites have different layouts; maintaining a reader is a full-time project | Rely on Android Share Sheet + reader apps |
| **Download / offline reading** | Requires fetching and storing copyrighted content | Not the app's job |
| **User authentication / login** | No backend; no need for user accounts | Everything is local |
| **Analytics / user tracking** | Simple tool doesn't need behavioral data | Optional crash reporting only (e.g., Sentry opt-in) |
| **Push notifications** | No server; no real-time events | No trigger for notifications |
| **Social features** (comments, ratings, sharing lists) | Adds complexity with no clear value for a search tool | Not applicable |
| **Writing/publishing tools** | Different product category entirely | Not applicable |
| **Google Custom Search API** (paid API) | Cost-prohibitive, query limits, requires billing | Web scraping (current plan) |
| **Search history stored on device** (as persistent log) | Privacy concern; user may not want permanent history | Recent searches (in-memory, session-only) |
| **EPUB/PDF export** | Requires content fetching + conversion | Not the app's job |
| **iOS support in v1** | Half the work for zero validated users | Android only; reconsider post-validation |

## Feature Dependencies

```
Keyword CRUD ───────────────────────────── Basic table stakes
    │
    ├── Keyword list display
    │
    ├── One-tap search execution ────────────────── D1 (core differentiator)
    │       │
    │       ├── Multi-keyword search (AND) ──────── D2
    │       │
    │       ├── Source-site toggles ─────────────── D3 (needs site list UI)
    │       │
    │       └── Search presets ──────────────────── D7 (needs both keyword + filter)
    │
    └── Search results
            │
            ├── Results list ───────────────────── Table stakes
            │       │
            │       ├── Source-site labels ──────── Table stakes
            │       ├── Deduplication ───────────── D4
            │       ├── Result ranking ──────────── D11
            │       ├── Search within results ───── D13
            │       └── Result count per site ───── D14
            │
            ├── Share Sheet on tap ──────────────── Table stakes
            ├── Copy URL ───────────────────────── D5
            ├── Open in browser ────────────────── D6
            │
            ├── Loading state ──────────────────── Table stakes
            ├── Error state ────────────────────── Table stakes
            ├── Empty state ────────────────────── Table stakes
            ├── Pull-to-refresh ────────────────── Table stakes
            │
            ├── Recent searches ────────────────── D9
            │
            └── Favorite/bookmark results ──────── D10
```

### Build Order Dependencies

```
Phase 1: MVP (Validation)
  Keyword CRUD → Keyword List → One-tap Search → Results List → Share Sheet
  └─ These are the bare minimum to validate the core value prop

Phase 2: Basic UX
  Loading/Error/Empty states → Pull-to-refresh → Source-site labels → Open in browser → Copy URL

Phase 3: Power Search
  Multi-keyword search → Source-site toggles → Recent searches → Favorite/bookmark

Phase 4: Polish
  Dark mode → Result ranking → Deduplication → Search within results → Result count per site

Phase 5: Advanced
  Search presets → Widget
```

## UI Pattern Recommendations (from mobile search/aggregator pattern analysis)

### Keyword Management
```
[Search icon] "キーワード" (screen title)
━━━━━━━━━━━━━━━━━━━━━━━━
[TextField: 新しいキーワード] [＋]
━━━━━━━━━━━━━━━━━━━━━━━━
異世界転生                    ▶ (tap to search)
  └─ syosetu.com (12) | kakuyomu.jp (3) | ...
━━━━━━━━━━━━━━━━━━━━━━━━
TS衛生                          ▶
━━━━━━━━━━━━━━━━━━━━━━━━
逆行もの                        ▶
━━━━━━━━━━━━━━━━━━━━━━━━
[Long-press → Edit / Delete]
━━━━━━━━━━━━━━━━━━━━━━━━
```

### Search Results
```
[← Back] "異世界転生" (searching...)
━━━━━━━━━━━━━━━━━━━━━━━━
[Filter: All 42 sites ▼] [Dedup: ON]
━━━━━━━━━━━━━━━━━━━━━━━━
異世界転生したらチート能力が     ⚡syosetu.com
┌─────────────────────────────┐
│ 転生先で無双する主人公の物語    │
└─────────────────────────────┘
[Share ↗] [Open 🌐] [Copy 📋] [❤️]
━━━━━━━━━━━━━━━━━━━━━━━━
転生したらスライムだった件        ⚡kakuyomu.jp
...
━━━━━━━━━━━━━━━━━━━━━━━━
[23 results] [Load more]
```

## Sources

- **Project context analysis**: PROJECT.md, .env (42-site query)
- **Android Share Sheet pattern**: Android `Intent.ACTION_SEND` documentation (HIGH confidence)
- **Google Search scraping pattern**: Common mobile search aggregator architecture (MEDIUM confidence — needs verification of Google's anti-scraping posture)
- **Japanese novel ecosystem**: syosetu.com, kakuyomu.jp, aozora.gr.jp are the top 3 novel sites in Japan; 42 sites total from `.env`
- **Competitor landscape**: Play Store has novel *readers* but no dedicated cross-site *search aggregator* for Japanese web novels (HIGH confidence — this is a validated gap)
- **Mobile UX patterns**: Standard CRUD-list + search-results pattern used by all search/aggregator apps (HIGH confidence)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Table stakes | HIGH | Based on standard search app patterns |
| Differentiators | MEDIUM | Unvalidated — actual user needs may differ; ship Phase 1 to validate |
| Anti-features | HIGH | Consistent with PROJECT.md scope constraints |
| Dependencies | HIGH | Logical build-order analysis |
| Competitor landscape | MEDIUM | Novel readers are well-documented; no direct search aggregator competitor found |
| Google scraping viability | LOW | Flagged — needs verification in Phase 0/1 research |
