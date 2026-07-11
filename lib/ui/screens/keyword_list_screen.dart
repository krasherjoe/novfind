import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KeywordListScreen extends ConsumerWidget {
  const KeywordListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('novfind'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('Keyword list - coming in Phase 4'),
      ),
    );
  }
}
