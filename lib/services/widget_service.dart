import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetService {
  static const _widgetName = 'NovfindWidget';

  static Future<void> initialize() async {
    HomeWidget.registerBackgroundCallback(backgroundCallback);
  }

  static Future<void> updateWidget() async {
    final prefs = await SharedPreferences.getInstance();
    final historyRaw = prefs.getStringList('searchHistory') ?? [];
    final keywordsRaw = prefs.getStringList('keywords') ?? [];

    // Get recent searches (up to 5)
    final recentSearches = historyRaw
        .take(5)
        .map((s) {
          try {
            return _parseJsonField(s, 'keyword') ?? '...';
          } catch (_) {
            return '...';
          }
        })
        .toList();

    // Count keywords
    final keywordCount = keywordsRaw.length;
    final historyCount = historyRaw.length;

    await HomeWidget.saveWidgetData<String>('title', 'novfind');
    await HomeWidget.saveWidgetData<String>('subtitle', '$keywordCount keywords');
    await HomeWidget.saveWidgetData<String>('searches', '$historyCount searches');
    await HomeWidget.saveWidgetData<String>('recent1', recentSearches.length > 0 ? recentSearches[0] : '');
    await HomeWidget.saveWidgetData<String>('recent2', recentSearches.length > 1 ? recentSearches[1] : '');
    await HomeWidget.saveWidgetData<String>('recent3', recentSearches.length > 2 ? recentSearches[2] : '');
    await HomeWidget.saveWidgetData<String>('recent4', recentSearches.length > 3 ? recentSearches[3] : '');
    await HomeWidget.saveWidgetData<String>('recent5', recentSearches.length > 4 ? recentSearches[4] : '');

    await HomeWidget.updateWidget(
      name: _widgetName,
      androidName: 'AppWidgetProvider',
    );
  }

  static String? _parseJsonField(String jsonStr, String field) {
    // Simple JSON field extraction without dart:convert
    final key = '"$field":"';
    final start = jsonStr.indexOf(key);
    if (start == -1) return null;
    final valueStart = start + key.length;
    final end = jsonStr.indexOf('"', valueStart);
    if (end == -1) return null;
    return jsonStr.substring(valueStart, end);
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    // Handle widget tap - open app
    await HomeWidget.saveWidgetData<String>('action', 'opened');
  }
}
