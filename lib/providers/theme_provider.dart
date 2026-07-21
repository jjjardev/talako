import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_mode';
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider({bool isDark = true}) : _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.dark) {
      _themeMode = ThemeMode.light;
      await prefs.setBool(_key, false);
    } else {
      _themeMode = ThemeMode.dark;
      await prefs.setBool(_key, true);
    }
    notifyListeners();
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;
}
