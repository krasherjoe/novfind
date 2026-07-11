import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_service.dart';
import 'providers/connection_status.dart' show initConnectionStatus, updateSshStatus;
import 'providers/theme_provider.dart';
import 'services/mattermost_debug_bridge.dart';
import 'services/watchdog_service.dart';
import 'services/widget_service.dart';
import 'ui/screens/ice_settings_screen.dart';
import 'ui/screens/keyword_list_screen.dart';
import 'ui/screens/search_results_screen.dart';
import 'ui/screens/site_filter_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadTheme();
  initConnectionStatus();
  await updateSshStatus();
  WidgetService.initialize();
  await iceApiServer.start();
  WidgetService.updateWidget();
  MattermostDebugBridge.instance.start();
  WatchdogService.instance.start();
  runApp(const ProviderScope(child: NovfindApp()));
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'keywords',
        builder: (context, state) => const KeywordListScreen(),
      ),
      GoRoute(
        path: '/ice',
        name: 'ice',
        builder: (context, state) => IceSettingsScreen(apiServer: iceApiServer),
      ),
      GoRoute(
        path: '/sites',
        name: 'sites',
        builder: (context, state) => const SiteFilterScreen(),
      ),
      GoRoute(
        path: '/search/:keyword',
        name: 'search',
        builder: (context, state) => SearchResultsScreen(
          keyword: state.pathParameters['keyword']!,
        ),
      ),
    ],
  );
});

class NovfindApp extends StatelessWidget {
  const NovfindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(goRouterProvider);
            return MaterialApp.router(
              title: 'novfind',
              routerConfig: router,
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.indigo,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
            );
          },
        );
      },
    );
  }
}
