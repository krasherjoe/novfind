import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/google_search_service.dart';
import '../../data/services/site_label_service.dart';
import '../../models/search_result.dart';
import '../../app_service.dart' show restartIce;
import '../../providers/connection_status.dart' show isIceOnline, isSshConfigured;
import '../../providers/search_provider.dart';
import '../widgets/status_dot.dart';

enum SortOrder { default_, title, domain }

extension SortOrderLabel on SortOrder {
  String get label {
    switch (this) {
      case SortOrder.default_:
        return 'デフォルト';
      case SortOrder.title:
        return 'タイトル順';
      case SortOrder.domain:
        return 'サイト順';
    }
  }
}

class SearchResultsScreen extends ConsumerStatefulWidget {
  final String keyword;

  const SearchResultsScreen({required this.keyword, super.key});

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  SortOrder _sortOrder = SortOrder.default_;

  List<SearchResult> _sort(List<SearchResult> results) {
    switch (_sortOrder) {
      case SortOrder.default_:
        return results;
      case SortOrder.title:
        return List.from(results)..sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.domain:
        return List.from(results)..sort((a, b) => a.sourceDomain.compareTo(b.sourceDomain));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider(widget.keyword));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(
              notifier: isSshConfigured,
              tooltip: 'SSH',
              onTap: restartIce,
            ),
            StatusDot(
              notifier: isIceOnline,
              tooltip: 'ICE',
              onTap: restartIce,
            ),
            Text(widget.keyword),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: '並び替え',
            onSelected: (order) => setState(() => _sortOrder = order),
            itemBuilder: (_) => SortOrder.values.map((order) {
              return PopupMenuItem(
                value: order,
                child: Row(
                  children: [
                    if (_sortOrder == order)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(order.label),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
        error: (error, _) => _buildErrorView(context, ref, error),
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
          final sorted = _sort(results);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(searchResultsProvider(widget.keyword).future),
            child: ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = sorted[index];
                return ListTile(
                  title: Text(
                    result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Chip(
                        label: Text(
                          SiteLabelService.getLabel(result.sourceDomain),
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ),
                    ],
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

  Widget _buildErrorView(BuildContext context, WidgetRef ref, Object error) {
    final searchUrl = (error is SearchException) ? error.searchUrl : null;
    final htmlSnippet = (error is SearchException) ? error.htmlSnippet : null;
    final isSearchException = error is SearchException;
    final errorType = isSearchException ? error.type : null;

    String userMessage;
    if (isSearchException && errorType != null) {
      userMessage = switch (errorType) {
        SearchErrorType.network => 'ネットワークエラーが発生しました',
        SearchErrorType.captcha => 'CAPTCHA認証が必要です\nしばらく待ってから再試行してください',
        SearchErrorType.empty => '結果が見つかりませんでした',
        SearchErrorType.parse => '検索結果の解析に失敗しました',
        SearchErrorType.timeout => 'タイムアウトしました\n電波の良い場所で再試行してください',
      };
    } else {
      userMessage = 'エラーが発生しました: $error';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Icon(
            isSearchException && errorType == SearchErrorType.captcha
                ? Icons.security
                : Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            userMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.invalidate(searchResultsProvider(widget.keyword)),
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
          if (isSearchException) ...[
            const SizedBox(height: 24),
            _DebugPanel(
              error: error as SearchException,
              searchUrl: searchUrl,
              htmlSnippet: htmlSnippet,
            ),
          ],
        ],
      ),
    );
  }

  void _shareResult(BuildContext context, SearchResult result) {
    SharePlus.instance.share(
      ShareParams(
        text: '${result.title} - ${result.url}',
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  final SearchException error;
  final String? searchUrl;
  final String? htmlSnippet;

  const _DebugPanel({
    required this.error,
    this.searchUrl,
    this.htmlSnippet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🔍 DEBUG',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _debugLine(context, 'Error', '${error.type}: ${error.message}'),
          if (searchUrl != null)
            _debugLine(context, 'URL', searchUrl!),
          _debugLine(context, 'h3/anchor', error.message),
          if (htmlSnippet != null) ...[
            const SizedBox(height: 8),
            Text(
              'HTML (先頭500文字):',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              htmlSnippet!,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.grey.shade300,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _debugLine(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade300,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
