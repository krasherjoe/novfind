import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IceStatus { online, offline }
enum SshStatus { configured, unconfigured }

final iceStatus = ValueNotifier<IceStatus>(IceStatus.offline);
final sshStatus = ValueNotifier<SshStatus>(SshStatus.unconfigured);

Future<void> updateSshStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.containsKey('ssh_config');
  final hasKey = prefs.containsKey('ssh_key');
  sshStatus.value =
      (hasConfig || hasKey) ? SshStatus.configured : SshStatus.unconfigured;
}
