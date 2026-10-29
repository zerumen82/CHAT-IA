import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/services/theme_service.dart';

Future<void> _waitForLoad(ThemeService service) async {
  final loaded = Completer<void>();
  service.addListener(() {
    if (!loaded.isCompleted) {
      loaded.complete();
    }
  });
  await loaded.future;
}

void main() {
  test('defaults to dark mode when no preference has been saved', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ThemeService();

    await _waitForLoad(service);

    expect(service.mode, ThemeMode.dark);
    service.dispose();
  });

  test('preserves an explicitly saved light theme', () async {
    SharedPreferences.setMockInitialValues({'preferredThemeMode': 'light'});
    final service = ThemeService();

    await _waitForLoad(service);

    expect(service.mode, ThemeMode.light);
    service.dispose();
  });
}
