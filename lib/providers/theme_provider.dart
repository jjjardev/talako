import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_mode';
  static const String _modeKey = 'theme_mode_name';
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider({bool isDark = true, ThemeMode? initialMode})
      : _themeMode = initialMode ?? (isDark ? ThemeMode.dark : ThemeMode.light);

  static ThemeMode loadMode(SharedPreferences prefs, {bool fallbackDark = true}) {
    final stored = prefs.getString(_modeKey);
    if (stored != null) {
      for (final mode in ThemeMode.values) {
        if (mode.name == stored) return mode;
      }
    }
    final legacy = prefs.getBool(_key);
    if (legacy != null) return legacy ? ThemeMode.dark : ThemeMode.light;
    return fallbackDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    if (mode != ThemeMode.system) {
      await prefs.setBool(_key, mode == ThemeMode.dark);
    }
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
