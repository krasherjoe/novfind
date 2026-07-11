import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/google_search_service.dart';
import '../../models/search_result.dart';
import '../../providers/search_provider.dart';

class SearchResultsScreen extends ConsumerWidget {
  final String keyword;

  const SearchResultsScreen({required this.keyword, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider(keyword));

    return Scaffold(
      appBar: AppBar(
        title: Text(keyword),
        centerTitle: true,
      ),
      body: resultsAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('検索中...'),
            ],
          ),
        ),
        error: (error, _) {
          String message;
          if (error is SearchException) {
            message = switch (error.type) {
              SearchErrorType.network => 'ネットワークエラーが発生しました',
              SearchErrorType.captcha => 'CAPTCHA認証が必要です\nしばらく待ってから再試行してください',
              SearchErrorType.empty => '結果が見つかりませんでした',
              SearchErrorType.parse => '検索結果の解析に失敗しました',
              SearchErrorType.timeout => 'タイムアウトしました\n電波の良い場所で再試行してください',
            };
          } else {
            message = 'エラーが発生しました: $error';
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(searchResultsProvider(keyword)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('再試行'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (results) {
          if (results.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64),
                  SizedBox(height: 16),
                  Text('結果が見つかりませんでした'),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(searchResultsProvider(keyword).future),
            child: ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  title: Text(
                    result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result.sourceDomain,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.share, size: 20),
                  onTap: () => _shareResult(context, result),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _shareResult(BuildContext context, SearchResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} を共有します')),
    );
  }
}
