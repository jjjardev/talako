import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/database_helper.dart';
import 'demo/demo_seeder.dart';
import 'providers/customers_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/transactions_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';

/// Demo entry — side-by-side install (`com.talako.app.demo`, `TalaKo Demo`).
/// Same codebase, separate DB (`talako_demo.db`), preset local data, no internet.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Isolate demo from prod: different file on disk, different prefs namespace
  // (prefs is per package, so com.talako.app.demo already isolates,
  // but we also keep DB name distinct for clarity when testing prod+demo together).
  DatabaseHelper.databaseName = 'talako_demo.db';

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('theme_mode') ?? true;
  const requiredVersion = 3;
  final storedVersion = prefs.getInt('onboarding_version') ?? 0;
  final demoVersion = prefs.getInt('demo_version') ?? 0;

  // Seed once per install (or after demo_version bump).
  if (demoVersion < DemoSeeder.demoVersion) {
    await DemoSeeder.seed();
    await prefs.setInt('demo_version', DemoSeeder.demoVersion);
    // Skip onboarding for instant demo showcase — comment next line to keep tutorial.
    await prefs.setInt('onboarding_version', 999);
  }

  final showOnboarding = (prefs.getInt('onboarding_version') ?? storedVersion) < requiredVersion;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(isDark: isDark)),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => TransactionsProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
      ],
      child: TalaKoDemoApp(showOnboarding: showOnboarding),
    ),
  );
}

class TalaKoDemoApp extends StatelessWidget {
  final bool showOnboarding;

  const TalaKoDemoApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: 'TalaKo Demo',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00897B),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
            ),
            cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
          ),
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00897B),
              brightness: Brightness.light,
            ),
          ),
          home: showOnboarding ? const OnboardingScreen() : const MainShell(),
        );
      },
    );
  }
}
