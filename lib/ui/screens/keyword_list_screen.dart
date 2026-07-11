import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/keyword.dart';
import '../../providers/keywords_provider.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/theme_provider.dart' show themeNotifier, toggleTheme;

class KeywordListScreen extends ConsumerWidget {
  const KeywordListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keywordsAsync = ref.watch(keywordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('novfind'),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) {
              final icon = switch (mode) {
                ThemeMode.dark => Icons.dark_mode,
                ThemeMode.light => Icons.light_mode,
                _ => Icons.brightness_auto,
              };
              return IconButton(
                icon: Icon(icon),
                onPressed: toggleTheme,
                tooltip: 'テーマ切替',
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const _SearchHistorySection(),
          Expanded(
            child: keywordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (keywords) {
                if (keywords.isEmpty) {
                  return const Center(
                    child: Text('右下の＋からキーワードを追加'),
                  );
                }
                return ReorderableListView.builder(
                  itemCount: keywords.length,
                  onReorderItem: (oldIndex, newIndex) {},
                  itemBuilder: (context, index) {
                    final keyword = keywords[index];
                  return _KeywordTile(
                    key: ValueKey(keyword.id),
                    keyword: keyword,
                    onDelete: () => ref.read(keywordsProvider.notifier).removeKeyword(keyword.id),
                  );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('キーワードを追加'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '検索キーワードを入力',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(keywordsProvider.notifier).addKeyword(text);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }
}

class _SearchHistorySection extends ConsumerWidget {
  const _SearchHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(searchHistoryProvider);

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (history) {
        if (history.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '最近の検索',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                    child: const Text('クリア', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: history.length > 10 ? 10 : history.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return ActionChip(
                      label: Text(entry.keyword, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        ref.read(searchHistoryProvider.notifier).addEntry(entry.keyword);
                        context.go('/search/${Uri.encodeComponent(entry.keyword)}');
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  },
                ),
              ),
              const Divider(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _KeywordTile extends ConsumerWidget {
  final Keyword keyword;
  final VoidCallback onDelete;

  const _KeywordTile({
    required this.keyword,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(keyword.text),
      subtitle: Text(
        '追加: ${_formatDate(keyword.createdAt)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ref.read(searchHistoryProvider.notifier).addEntry(keyword.text);
              context.go('/search/${Uri.encodeComponent(keyword.text)}');
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: () {
        ref.read(searchHistoryProvider.notifier).addEntry(keyword.text);
        context.go('/search/${Uri.encodeComponent(keyword.text)}');
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }
}
