import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IceStatus { online, offline }
enum SshStatus { configured, unconfigured }

final iceStatus = ValueNotifier<IceStatus>(IceStatus.offline);
final sshStatus = ValueNotifier<SshStatus>(SshStatus.unconfigured);

final isIceOnline = ValueNotifier<bool>(false);
final isSshConfigured = ValueNotifier<bool>(false);

void _syncIceStatus() {
  isIceOnline.value = iceStatus.value == IceStatus.online;
}

void _syncSshStatus() {
  isSshConfigured.value = sshStatus.value == SshStatus.configured;
}

void initConnectionStatus() {
  _syncIceStatus();
  _syncSshStatus();
  iceStatus.addListener(_syncIceStatus);
  sshStatus.addListener(_syncSshStatus);
}

Future<void> updateSshStatus() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final sshDir = Directory('${dir.path}/.ssh');
    final configFile = File('${sshDir.path}/config');
    final keyFile = File('${sshDir.path}/id_ed25519');

    final configExists = await configFile.exists();
    final keyExists = await keyFile.exists();

    sshStatus.value =
        (configExists || keyExists) ? SshStatus.configured : SshStatus.unconfigured;
  } catch (_) {
    sshStatus.value = SshStatus.unconfigured;
  }
}
