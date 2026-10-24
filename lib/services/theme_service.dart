import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _themeKey = 'preferredThemeMode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_themeKey) ?? 'dark';
      switch (value) {
        case 'light':
          _mode = ThemeMode.light;
          break;
        case 'dark':
          _mode = ThemeMode.dark;
          break;
        default:
          _mode = ThemeMode.dark;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = m == ThemeMode.light
          ? 'light'
          : m == ThemeMode.dark
              ? 'dark'
              : 'system';
      await prefs.setString(_themeKey, s);
    } catch (_) {}
  }

  Future<void> toggleDark() async {
    if (_mode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}
