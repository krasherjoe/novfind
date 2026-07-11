# Architecture Patterns

**Domain:** Flutter Android search aggregator app
**Researched:** 2026-07-11

## Recommended Architecture: MVVM with Repository Pattern

Flutter's official app architecture guide (https://docs.flutter.dev/app-architecture/guide) recommends MVVM with a clear separation into **UI Layer** (Views + ViewModels) and **Data Layer** (Repositories + Services). This is the right fit for novfind because:

- **Small app with clear boundaries** — 2-3 screens, well-defined data flows
- **Async-heavy** — HTTP scraping is inherently async, MVVM handles this cleanly via ViewModels
- **Testable** — Repositories and Services can be mocked independently
- **Future-proof** — Easy to add features (history, multiple search engines) without restructuring

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       UI Layer                              │
│  ┌─────────────────────┐   ┌─────────────────────────────┐  │
│  │     Views           │   │       ViewModels            │  │
│  │  (Widgets/Screens)  │──▶│  (State + Business Logic)   │  │
│  │                     │◀──│                             │  │
│  │  - KeywordListScreen│   │  - KeywordListViewModel     │  │
│  │  - SearchResultScreen│  │  - SearchResultViewModel    │  │
│  │  - AddKeywordDialog │   │  - AddKeywordViewModel      │  │
│  └─────────────────────┘   └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Data Layer                              │
│  ┌──────────────────────┐  ┌────────────────────────────┐   │
│  │    Repositories      │  │       Services             │   │
│  │  (Single source of   │  │  (External integrations)   │   │
│  │   truth)             │  │                            │   │
│  │                     │  │  - GoogleSearchService     │   │
│  │  - KeywordRepository │  │    (HTTP + HTML parse)    │   │
│  │    (local storage)   │  │  - ShareService            │   │
│  └──────────────────────┘  │    (Android intent)        │   │
│                            └────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### State Management: Riverpod

**Choice: Riverpod 3.x** (https://pub.dev/packages/riverpod)

| Why Riverpod | Details |
|---|---|
| **Async-native** | `FutureProvider` and `AsyncNotifierProvider` handle loading/error/data states automatically — perfect for search HTTP calls |
| **Compile-safe** | No runtime `ProviderNotFoundException` like plain Provider |
| **Testable** | `ProviderContainer` for overriding dependencies in tests |
| **No BuildContext dependency** | Providers can be read anywhere, not just in widget tree |
| **Code generation** | `@riverpod` annotation reduces boilerplate (riverpod_annotation + riverpod_generator) |

**Key providers for novfind:**

```dart
// -- Data providers
@riverpod
KeywordRepository keywordRepository(Ref ref) => KeywordRepository();

@riverpod
GoogleSearchService googleSearchService(Ref ref) => GoogleSearchService();

@riverpod
ShareService shareService(Ref ref) => ShareService();

// -- ViewModel providers (stateful)
@riverpod
class KeywordList extends _$KeywordList {
  @override
  Future<List<Keyword>> build() async =>
    ref.watch(keywordRepositoryProvider).loadAll();
    
  Future<void> add(Keyword keyword) async { ... }
  Future<void> remove(String id) async { ... }
}

@riverpod
class SearchResults extends _$SearchResults {
  @override
  Future<List<SearchResult>> build(String keyword) async =>
    ref.watch(googleSearchServiceProvider).search(keyword);
}
```

---

## Component Boundaries

### 1. Models (Domain Layer)

Pure Dart data classes — no dependencies, no logic.

| Model | Fields | Purpose |
|-------|--------|---------|
| `Keyword` | `id`, `text`, `createdAt` | A search keyword the user registers |
| `SearchResult` | `title`, `url`, `snippet`, `sourceSite` | One result from Google search |
| `SiteConfig` | `name`, `siteOperator` (e.g. `site:syosetu.com`), `enabled` | Which sites to include in search |

**Directory:** `lib/domain/models/`

### 2. KeywordRepository (Data Layer)

**Responsibility:** CRUD for keywords persisted locally.

- Reads/writes keywords via `SharedPreferencesAsync` (https://pub.dev/packages/shared_preferences)
- Stores keywords as JSON string list under a single key
- Provides `Stream<List<Keyword>>` via Riverpod for reactive UI updates

**Why SharedPreferences over SQLite:** The data is simple (flat list of strings, no relations, no complex queries). SQLite (via `sqflite` or `drift`) would be over-engineering for a list of keywords.

**Interface:**

```dart
class KeywordRepository {
  Future<List<Keyword>> loadAll();
  Future<void> add(Keyword keyword);
  Future<void> remove(String id);
  Future<bool> exists(String text); // prevent duplicates
}
```

**Directory:** `lib/data/repositories/`

### 3. GoogleSearchService (Data Layer / Service)

**Responsibility:** Execute Google search via HTTP scraping and parse results.

**Flow:**
1. Build URL: `https://www.google.com/search?q={keyword}+site:syosetu.com+OR+site:kakuyomu.jp+...`
2. Send HTTP GET request with appropriate User-Agent header (to avoid bot detection)
3. Parse HTML response using `package:html` (https://pub.dev/packages/html)
4. Extract result items (title, URL, snippet) from search result divs
5. Return `List<SearchResult>`

**Critical considerations:**
- Google search result HTML structure changes periodically — parsing logic must be resilient
- Rate limiting / CAPTCHA is a real risk (see PITFALLS.md)
- User-Agent rotation and request delay between queries may be needed
- Search must run in a background isolate for long queries (42 sites × keyword)

**Interface:**

```dart
class GoogleSearchService {
  Future<List<SearchResult>> search(String keyword);
  void cancel(); // abort in-flight request
}
```

**Directory:** `lib/data/services/`

### 4. ShareService (Data Layer / Service)

**Responsibility:** Open Android share sheet with a URL.

Uses `share_plus` package (https://pub.dev/packages/share_plus) which wraps `Intent.ACTION_SEND`.

```dart
class ShareService {
  Future<void> shareUrl(String url) async {
    await SharePlus.instance.share(ShareParams(text: url));
  }
}
```

**Directory:** `lib/data/services/`

### 5. ViewModels (UI Layer)

Each screen gets one ViewModel. ViewModels hold state and expose commands (callbacks) to Views.

| ViewModel | State Type | Dependencies | Responsibility |
|-----------|-----------|--------------|----------------|
| `KeywordListViewModel` | `AsyncValue<List<Keyword>>` | KeywordRepository | Load, add, delete keywords |
| `SearchResultViewModel` | `AsyncValue<List<SearchResult>>` | GoogleSearchService, KeywordRepository | Execute search using all active site: operators |
| `AddKeywordViewModel` | form validation state | KeywordRepository | Validate + persist new keyword |

**Directory:** `lib/ui/<feature>/view_models/`

### 6. Views (UI Layer)

Flutter widgets. Minimal logic — delegate to ViewModel.

| View | Route | Purpose |
|------|-------|---------|
| `KeywordListScreen` | `/` (home) | List keywords, FAB to add, swipe to delete, tap keyword to search |
| `SearchResultScreen` | `/search/:keyword` | Loading spinner → results list, each item tappable → share |
| `AddKeywordSheet` | modal bottom sheet | Text field + save button |

**Directory:** `lib/ui/<feature>/widgets/`

---

## Data Flow

### Flow 1: Keyword Registration → Search → Share (Happy Path)

```
User taps FAB
  → AddKeywordSheet opens
  → User enters "魔女", taps save
    → AddKeywordViewModel validates (non-empty, no duplicates)
      → KeywordRepository.add("魔女") → SharedPreferences
        → KeywordListScreen rebuilds via Riverpod

User taps "魔女" in list
  → Navigate to /search/魔女
    → SearchResultViewModel.build("魔女")
      → GoogleSearchService.search("魔女")
        → HTTP GET https://www.google.com/search?q=魔女+site:syosetu.com+OR+site:kakuyomu.jp+...
        → Parse HTML with package:html
        → Extract title + URL + snippet
      → Return List<SearchResult>
    → SearchResultScreen shows results

User taps a result
  → SearchResultViewModel.shareUrl(result.url)
    → ShareService.shareUrl("https://ncode.syosetu.com/n1234/")
      → SharePlus.instance.share(...) → Android share sheet opens
        → User picks Reader app → URL sent to that app
```

### Flow 2: Error States

```
Network error during search:
  GoogleSearchService throws
    → SearchResultViewModel catches → AsyncError state
      → SearchResultScreen shows error widget + retry button

Empty results (no matches):
  GoogleSearchService returns []
    → SearchResultViewModel sets empty state
      → SearchResultScreen shows "No results" message

CAPTCHA/interstitial:
  GoogleSearchService detects captcha page
    → SearchResultViewModel sets captcha state
      → SearchResultScreen shows "Search blocked, try manually" message
```

---

## Project Structure

Following Flutter's case study convention (https://docs.flutter.dev/app-architecture/case-study):

```
lib/
├── main.dart                          # App entry point
├── app.dart                           # MaterialApp with routing
│
├── ui/
│   ├── core/
│   │   ├── widgets/                   # Shared widgets (empty state, error, loading)
│   │   └── themes/                    # App theme
│   ├── keyword_list/
│   │   ├── view_models/
│   │   │   └── keyword_list_viewmodel.dart
│   │   └── widgets/
│   │       ├── keyword_list_screen.dart
│   │       └── keyword_tile.dart
│   ├── search_results/
│   │   ├── view_models/
│   │   │   └── search_result_viewmodel.dart
│   │   └── widgets/
│   │       ├── search_result_screen.dart
│   │       └── result_tile.dart
│   └── add_keyword/
│       ├── view_models/
│       │   └── add_keyword_viewmodel.dart
│       └── widgets/
│           └── add_keyword_sheet.dart
│
├── domain/
│   └── models/
│       ├── keyword.dart
│       ├── search_result.dart
│       └── site_config.dart
│
└── data/
    ├── repositories/
    │   └── keyword_repository.dart
    └── services/
        ├── google_search_service.dart
        └── share_service.dart
```

**Rationale:** UI grouped by feature (each feature = 1 View + 1 ViewModel), data grouped by type (repositories and services are reused across features). This matches Flutter's official recommendation for scalable apps (https://docs.flutter.dev/app-architecture/case-study#package-structure).

---

## Routing

Use `go_router` (https://pub.dev/packages/go_router) for declarative routing.

**Routes:**

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const KeywordListScreen()),
    GoRoute(
      path: '/search/:keyword',
      builder: (_, state) => SearchResultScreen(
        keyword: state.pathParameters['keyword']!,
      ),
    ),
  ],
);
```

**Why go_router over Navigator.pushNamed:**
- Declarative (deep-linkable by default)
- `context.go()` for navigation
- Parameter parsing built-in
- Flutter team recommended (https://docs.flutter.dev/ui/navigation#using-named-routes)

---

## Patterns to Follow

### Pattern 1: Repository as Single Source of Truth
**What:** All data access goes through repositories. Views/ViewModels never touch SharedPreferences or HTTP directly.
**When:** Any data operation.
**Why:** Swap local storage for backend later without touching UI code.

### Pattern 2: ViewModel Commands
**What:** ViewModels expose `Future<void>` functions (commands) that views call from event handlers.
**When:** Any user action that modifies state.
**Example:**
```dart
class KeywordListViewModel {
  Future<void> deleteKeyword(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.remove(id));
  }
}
```

### Pattern 3: Error Handling via AsyncValue
**What:** Riverpod's `AsyncValue` has `.when(data:, error:, loading:)` — use it in every View.
**When:** Every screen with async data.
**Why:** No missing error states. No try-catch in widgets.

### Pattern 4: Dependency Injection via Riverpod Providers
**What:** Override providers in tests with `ProviderContainer(overrides: [...])`.
**When:** All services and repositories.
**Example:**
```dart
final mockRepo = KeywordRepository();
final container = ProviderContainer(
  overrides: [keywordRepositoryProvider.overrideWithValue(mockRepo)],
);
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Business Logic in Widgets
**What:** Making HTTP calls or reading SharedPreferences inside a widget's `build` method or `onPressed`.
**Why bad:** Untestable, tightly coupled, violates separation of concerns.
**Instead:** Put logic in ViewModels, call from widgets.

### Anti-Pattern 2: StatefulWidget for App State
**What:** Using `setState` for keyword list or search results.
**Why bad:** Lost on navigation / rebuild. Not shared between screens.
**Instead:** Riverpod providers hold the state.

### Anti-Pattern 3: Hardcoding site: Operators in Widgets
**What:** Embedding the 42-site OR-query string in a widget.
**Why bad:** Change means recompiling. Can't be user-configured.
**Instead:** Load from config (`.env` or `SiteConfig` model) via a Repository.

### Anti-Pattern 4: Blocking UI During Search
**What:** Running HTTP request on main isolate without showing loading state.
**Why bad:** App appears frozen. ANR risk on Android.
**Instead:** Riverpod `AsyncValue.loading` state → show CircularProgressIndicator.

---

## Scalability Considerations

| Concern | v1 Approach | Future Approach |
|---------|-------------|-----------------|
| **Search speed** | Synchronous HTTP (single request with all site: operators) | Parallel requests per site, background isolate parsing |
| **Keyword count** | SharedPreferences string list | SQLite via drift (when >100 keywords) |
| **Google blocking** | Basic User-Agent header | Rotating User-Agents, proxy rotation, or switch to a search API |
| **Multiple search engines** | Hardcoded Google | Strategy pattern — `SearchService` interface with Google/Bing/DuckDuckGo implementations |
| **Search history** | Not stored | Add `SearchHistoryRepository` with SQLite |

---

## Build Order (Dependency Chain)

```
Phase 1: Foundation
  Models (Keyword, SearchResult, SiteConfig)
  → no dependencies, can build first
  
Phase 2: Data Layer
  KeywordRepository (requires models)
  GoogleSearchService (requires SearchResult model)
  ShareService (standalone)
  → can build in parallel after models

Phase 3: UI Layer — Keyword Management
  KeywordListViewModel (requires KeywordRepository)
  AddKeywordViewModel (requires KeywordRepository)
  KeywordListScreen, AddKeywordSheet (requires ViewModels)
  → Core user flow: add/view/delete keywords

Phase 4: UI Layer — Search + Share
  SearchResultViewModel (requires GoogleSearchService, KeywordRepository)
  SearchResultScreen (requires ViewModel)
  Share integration (requires ShareService)
  → Complete end-to-end flow

Phase 5: Polish
  Error handling, loading states, empty states
  Theme customization
  User-Agent rotation for scraping reliability
```

**Key dependency:** Search (Phase 4) cannot work without keywords (Phase 3) and the search service (Phase 2). Phases 1-2 are purely infrastructure.

---

## Sources

- **Flutter App Architecture Guide (HIGH confidence):** https://docs.flutter.dev/app-architecture/guide — Official MVVM recommendation with Views, ViewModels, Repositories, Services
- **Flutter Architecture Case Study (HIGH confidence):** https://docs.flutter.dev/app-architecture/case-study — Concrete package structure example
- **Riverpod (HIGH confidence):** https://pub.dev/packages/riverpod — State management choice, 4k likes, Flutter Favorite
- **share_plus (HIGH confidence):** https://pub.dev/packages/share_plus — Android ACTION_SEND intent, Flutter Favorite, 4k likes
- **http package (HIGH confidence):** https://pub.dev/packages/http — 8.4k likes, Dart team maintained
- **html package (HIGH confidence):** https://pub.dev/packages/html — HTML5 parser for Dart, 659 likes, Dart tools team maintained
- **shared_preferences (HIGH confidence):** https://pub.dev/packages/shared_preferences — 10.5k likes, Flutter Favorite, local key-value storage
- **go_router (HIGH confidence):** https://pub.dev/packages/go_router — Declarative routing, Flutter team recommended
