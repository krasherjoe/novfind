import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IceStatus { online, offline }
enum SshStatus { configured, unconfigured }

final iceStatus = ValueNotifier<IceStatus>(IceStatus.offline);
final sshStatus = ValueNotifier<SshStatus>(SshStatus.unconfigured);

// Derived boolean notifiers for StatusDot (always valid, never recreated)
final isIceOnline = ValueNotifier<bool>(false);
final isSshConfigured = ValueNotifier<bool>(false);

void _syncIceStatus() {
  isIceOnline.value = iceStatus.value == IceStatus.online;
}

void _syncSshStatus() {
  isSshConfigured.value = sshStatus.value == SshStatus.configured;
}

// Initialize listeners (call once at startup)
void initConnectionStatus() {
  _syncIceStatus();
  _syncSshStatus();
  iceStatus.addListener(_syncIceStatus);
  sshStatus.addListener(_syncSshStatus);
}

Future<void> updateSshStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.containsKey('ssh_config');
  final hasKey = prefs.containsKey('ssh_key');
  sshStatus.value =
      (hasConfig || hasKey) ? SshStatus.configured : SshStatus.unconfigured;
}
