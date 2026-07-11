import 'package:flutter/material.dart';

class StatusDot extends StatelessWidget {
  final ValueNotifier<bool> notifier;
  final String tooltip;
  final VoidCallback? onTap;

  const StatusDot({
    required this.notifier,
    required this.tooltip,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, active, _) {
        return GestureDetector(
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.green : Colors.grey.shade700,
              ),
            ),
          ),
        );
      },
    );
  }
}
