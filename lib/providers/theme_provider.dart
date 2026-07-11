import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString('themeMode') ?? 'system';
  switch (value) {
    case 'light':
      themeNotifier.value = ThemeMode.light;
    case 'dark':
      themeNotifier.value = ThemeMode.dark;
    default:
      themeNotifier.value = ThemeMode.system;
  }
}

Future<void> toggleTheme() async {
  final current = themeNotifier.value;
  final next = switch (current) {
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
    ThemeMode.system => ThemeMode.light,
    _ => ThemeMode.system,
  };
  themeNotifier.value = next;
  final prefs = await SharedPreferences.getInstance();
  String str;
  switch (next) {
    case ThemeMode.light:
      str = 'light';
    case ThemeMode.dark:
      str = 'dark';
    default:
      str = 'system';
  }
  await prefs.setString('themeMode', str);
}
