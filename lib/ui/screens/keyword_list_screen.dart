import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/keyword.dart';
import '../../models/preset.dart';
import '../../providers/keywords_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/search_history_provider.dart';
import '../../app_service.dart' show restartIce;
import '../../providers/connection_status.dart';
import '../../providers/theme_provider.dart' show themeNotifier, toggleTheme;
import '../widgets/status_dot.dart';

class KeywordListScreen extends ConsumerStatefulWidget {
  const KeywordListScreen({super.key});

  @override
  ConsumerState<KeywordListScreen> createState() => _KeywordListScreenState();
}

class _KeywordListScreenState extends ConsumerState<KeywordListScreen> {
  final _selectedIds = <String>{};

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _searchSelected() {
    if (_selectedIds.isEmpty) return;
    final keywords = ref.read(keywordsProvider).asData?.value ?? [];
    final texts = keywords.where((k) => _selectedIds.contains(k.id)).map((k) => k.text);
    final query = texts.join(' ');
    ref.read(searchHistoryProvider.notifier).addEntry(query);
    _selectedIds.clear();
    context.go('/search/${Uri.encodeComponent(query)}');
  }

  @override
  Widget build(BuildContext context) {
    final keywordsAsync = ref.watch(keywordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(
              notifier: ValueNotifier(sshStatus.value == SshStatus.configured),
              tooltip: sshStatus.value == SshStatus.configured ? 'SSH configured' : 'SSH not configured',
              onTap: restartIce,
            ),
            StatusDot(
              notifier: ValueNotifier(iceStatus.value == IceStatus.online),
              tooltip: iceStatus.value == IceStatus.online ? 'ICE API running' : 'ICE API stopped',
              onTap: restartIce,
            ),
            const Text('novfind'),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _searchSelected,
              tooltip: 'AND検索 (${_selectedIds.length}個)',
            ),
            IconButton(
              icon: const Icon(Icons.developer_mode),
              onPressed: () => context.go('/ice'),
              tooltip: 'ICE Debug',
            ),
            IconButton(
              icon: const Icon(Icons.bookmark),
              onPressed: () => _showPresetDialog(context),
              tooltip: 'プリセット',
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => context.go('/sites'),
              tooltip: 'サイトフィルター',
            ),
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
                return ListView.builder(
                  itemCount: keywords.length,
                  itemBuilder: (context, index) {
                    final keyword = keywords[index];
                    final selected = _selectedIds.contains(keyword.id);
                    return _KeywordTile(
                      key: ValueKey(keyword.id),
                      keyword: keyword,
                      selected: selected,
                      onDelete: () => ref.read(keywordsProvider.notifier).removeKeyword(keyword.id),
                      onToggleSelect: () => _toggleSelect(keyword.id),
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

  void _showPresetDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Consumer(
          builder: (context, ref, _) {
            final presetsAsync = ref.watch(presetProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('プリセット', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                presetsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (presets) {
                    if (presets.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('プリセットがありません\nキーワードを選択して保存できます'),
                      );
                    }
                    return Column(
                      children: presets.map((preset) {
                        return ListTile(
                          title: Text(preset.name),
                          subtitle: Text(preset.query, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => ref.read(presetProvider.notifier).deletePreset(preset.id),
                          ),
                          onTap: () {
                            ref.read(searchHistoryProvider.notifier).addEntry(preset.query);
                            Navigator.of(ctx).pop();
                            context.go('/search/${Uri.encodeComponent(preset.query)}');
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                if (_selectedIds.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showSavePresetDialog(context);
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('選択中をプリセット保存'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context) {
    final keywords = ref.read(keywordsProvider).asData?.value ?? [];
    final texts = keywords.where((k) => _selectedIds.contains(k.id)).map((k) => k.text);
    final query = texts.join(' ');
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('プリセット名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例: 異世界転生'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(presetProvider.notifier).addPreset(name, query);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
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
  final VoidCallback onToggleSelect;
  final bool selected;

  const _KeywordTile({
    required this.keyword,
    required this.onDelete,
    required this.onToggleSelect,
    required this.selected,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      selected: selected,
      leading: IconButton(
        icon: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank),
        onPressed: onToggleSelect,
      ),
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
      onTap: onToggleSelect,
      onLongPress: () {
        ref.read(searchHistoryProvider.notifier).addEntry(keyword.text);
        context.go('/search/${Uri.encodeComponent(keyword.text)}');
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }
}
