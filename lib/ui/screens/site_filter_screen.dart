import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/search_query_service.dart';
import '../../data/services/site_label_service.dart';
import '../../models/site_config.dart';
import '../../app_service.dart' show restartIce;
import '../../providers/connection_status.dart' show isIceOnline, isSshConfigured;
import '../../providers/site_filter_provider.dart';
import '../widgets/status_dot.dart';

class SiteFilterScreen extends ConsumerWidget {
  const SiteFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabledAsync = ref.watch(siteFilterProvider);
    final queryAsync = ref.watch(searchQueryProvider);

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
            const Text('検索対象サイト'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => ref.read(siteFilterProvider.notifier).setAllEnabled(),
            child: const Text('すべて有効'),
          ),
        ],
      ),
      body: disabledAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (disabled) {
          return queryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (query) {
              final config = SiteConfig.fromEnv(query);
              final sites = config.sites;
              return _buildSiteList(context, ref, sites, disabled);
            },
          );
        },
      ),
    );
  }

  Widget _buildSiteList(
      BuildContext context, WidgetRef ref, List<String> sites, Set<String> disabled) {
    final enabledCount = sites.length - disabled.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$enabledCount / ${sites.length} サイト有効',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: sites.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final domain = sites[index];
              final isEnabled = !disabled.contains(domain);
              return ListTile(
                leading: Icon(
                  isEnabled ? Icons.check_circle : Icons.cancel,
                  color: isEnabled ? Colors.green : Colors.grey,
                ),
                title: Text(SiteLabelService.getLabel(domain)),
                subtitle: Text(
                  domain,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Switch(
                  value: isEnabled,
                  onChanged: (_) =>
                      ref.read(siteFilterProvider.notifier).toggle(domain),
                ),
                onTap: () =>
                    ref.read(siteFilterProvider.notifier).toggle(domain),
              );
            },
          ),
        ),
      ],
    );
  }
}
