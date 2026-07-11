# Technology Stack

**Project:** novfind — Flutter Android novel search aggregator
**Researched:** 2026-07-11
**Overall confidence:** HIGH

## Recommended Stack

### Core Framework
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter | >=3.44.0 | Cross-platform UI framework | Android v1, Dart 3.12+, stable, excellent Android support |
| Dart | >=3.12.0 | Language | Required by Flutter 3.44+, sound null safety, pattern matching |

### HTTP Client (Scraping Engine)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| dio | ^5.10.0 | HTTP requests (Google scraping) | Interceptors for User-Agent/headers, Duration-based timeouts, CancelToken, mature ecosystem |

### HTML Parsing (Scraping Engine)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| html | ^0.15.6 | Parse Google search results HTML | Official dart-lang package, HTML5 spec compliant, querySelector API, 6M+ weekly downloads |

### URL Sharing
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| share_plus | ^13.2.0 | Android share sheet (ACTION_SEND) | Flutter Favorite, wraps Android Intent, `SharePlus.instance.share(ShareParams(uri: ...))` |

### State Management
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| flutter_riverpod | ^3.3.2 | Reactive state management | Async-safe, compile-time safety, separates logic from UI, official stable release, Flutter Favorite |

### Local Storage
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| shared_preferences | ^2.5.5 | Persist search keywords | Simple key-value (keywords are strings), Flutter Favorite, zero boilerplate, Android SharedPreferences/DataStore backend |

### Build & Env
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| flutter_dotenv | ^5.x | Load site query from .env | Keep 42-site OR query separate from code, simple key-value config |
| lint | ^2.x | Dart lint rules | Enforce consistent code style |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| HTTP client | dio 5.10.0 | `http` 1.6.0 | `http` package lacks native interceptor chain; for scraping we need User-Agent rotation, retry logic, request/response logging — dio's interceptor architecture makes this clean; `http` would require wrapping Client manually |
| HTTP client | dio 5.10.0 | `dio` 4.x | 4.x uses int-based timeouts (deprecated), less mature API surface |
| State management | Riverpod 3.3.2 | Provider | Provider is unmaintained (deprecated by author), lacks async support, testability |
| State management | Riverpod 3.3.2 | BLoC | Higher boilerplate, less ergonomic for simple state like keyword list + async search |
| Local storage | shared_preferences 2.5.5 | Hive 4.0.0-dev.2 | Hive 4.0 is still in dev (pre-release), requires TypeAdapter code generation for structured data. Keywords are plain strings — overkill. |
| Local storage | shared_preferences 2.5.5 | drift (SQLite) | Full relational DB for a list of strings is inappropriate |
| HTML parsing | html 0.15.6 | flutter_html | `flutter_html` renders HTML to widgets (not what we need). We need DOM-parsing for data extraction. |
| URL launch | share_plus 13.2.0 | url_launcher 6.3.2 | We share URLs (not open them in-browser). `url_launcher` opens URLs, `share_plus` sends them via ACTION_SEND. Different intent. |
| Background work | `compute` (Flutter built-in) | flutter_workmanager | No background polling needed. User-initiated search only. `compute()` is sufficient for offloading HTML parsing from main isolate. |

## Installation

```yaml
# pubspec.yaml
environment:
  sdk: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter
  # HTTP — scraping
  dio: ^5.10.0
  # HTML parsing — scraping
  html: ^0.15.6
  # URL sharing
  share_plus: ^13.2.0
  # State management
  flutter_riverpod: ^3.3.2
  # Local keyword storage
  shared_preferences: ^2.5.5
  # Environment config
  flutter_dotenv: ^5.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

## Version Verification

All versions verified from official pub.dev / documentation pages as of 2026-07-11:

| Package | Verified Version | Source | Confidence |
|---------|-----------------|--------|------------|
| Flutter | 3.44.0 | Flutter docs (breaking-changes/3-13-deprecations page) | HIGH |
| Dart | 3.12.0 | Flutter docs (migrate-to-built-in-kotlin page) | HIGH |
| dio | 5.10.0 | pub.dev/dio (published 11 days ago) | HIGH |
| html | 0.15.6 | pub.dev/html | HIGH |
| share_plus | 13.2.0 | pub.dev/share_plus (published 14 days ago) | HIGH |
| flutter_riverpod | 3.3.2 | pub.dev/flutter_riverpod (published 30 days ago) | HIGH |
| shared_preferences | 2.5.5 | pub.dev/shared_preferences (published 3 months ago) | HIGH |
| flutter_dotenv | 5.2.1 | pub.dev/flutter_dotenv | MEDIUM |

## Key Rationale

### Why dio over http
Google actively detects and blocks automated scraping. `dio`'s interceptor chain lets us:
1. Add a realistic desktop/mobile User-Agent on every request
2. Add retry logic with exponential backoff on 429/503
3. Log requests/responses during development
4. All cleanly separated in `interceptors` rather than mixed into business logic

```dart
// Example: user-agent interceptor
dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) {
    options.headers['User-Agent'] = 
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36';
    return handler.next(options);
  },
));
```

### Why share_plus over url_launcher
The requirement is to "share URLs via Android share sheet" — this is `ACTION_SEND`, not `ACTION_VIEW`. `share_plus` wraps the Share icon / share sheet flow. `url_launcher` opens URLs in browsers, which is a different gesture.

### Why Riverpod (stable 3.x) over BLoC
- Keyword list + search state is simple: ~4 providers (keywords, search query, results, loading state)
- Riverpod's `AsyncNotifier` handles loading/error/data states natively
- No boilerplate event classes
- Code-generation (`@riverpod`) is optional — can start without it

### Why shared_preferences over Hive
- Keywords are a list of strings — the simplest possible data model
- `shared_preferences` has `setStringList` / `getStringList` built in
- Hive requires: TypeAdapter generation, box opening, manual schema management
- The `SharedPreferencesAsync` API (available since 2.3.0) provides non-blocking reads

## What NOT to use

| Library | Reason |
|---------|--------|
| `flutter_html` | Renders HTML → widgets (wrong purpose). Use `html` for parsing. |
| `url_launcher` | Opens URLs in browser. Use `share_plus` for sharing. |
| `provider` | Unmaintained, replaced by Riverpod. |
| `get_it` + `bloc` | Overengineered for this scale. Riverpod covers DI + state management. |
| `flutter_secure_storage` | Keywords are not secrets. No encryption needed. |
| `sqflite` / `drift` | Relational DB for string lists is disproportionate. |
| `http` | Missing interceptor chain. Dio is the standard for non-trivial HTTP. |
| Python/JS backend | The entire app runs on-device in Flutter. No server needed for scraping. |

## Sources

- Flutter 3.44.0 + Dart 3.12.0: https://docs.flutter.dev/release/breaking-changes/3-13-deprecations
- dio 5.10.0: https://pub.dev/packages/dio (official docs, README)
- html 0.15.6: https://pub.dev/packages/html (dart-lang official package)
- share_plus 13.2.0: https://pub.dev/packages/share_plus (API docs, README)
- flutter_riverpod 3.3.2: https://pub.dev/packages/flutter_riverpod
- shared_preferences 2.5.5: https://pub.dev/packages/shared_preferences
- Flutter compute isolates: https://docs.flutter.dev/cookbook/networking/background-parsing
