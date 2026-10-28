import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/database_helper.dart';
import 'providers/customers_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/transactions_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/recovery_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final themeMode = ThemeProvider.loadMode(prefs);
  const requiredVersion = 4;
  final storedVersion = prefs.getInt('onboarding_version') ?? 0;
  final showOnboarding = storedVersion < requiredVersion;
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(initialMode: themeMode)),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => TransactionsProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
      ],
      child: TalaKoApp(showOnboarding: showOnboarding),
    ),
  );
}

class TalaKoApp extends StatelessWidget {
  final bool showOnboarding;

  const TalaKoApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: 'TalaKo',
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
          home: _DatabaseGate(showOnboarding: showOnboarding),
        );
      },
    );
  }
}

class _DatabaseGate extends StatefulWidget {
  final bool showOnboarding;

  const _DatabaseGate({required this.showOnboarding});

  @override
  State<_DatabaseGate> createState() => _DatabaseGateState();
}

class _DatabaseGateState extends State<_DatabaseGate> {
  late Future<void> _open;

  @override
  void initState() {
    super.initState();
    _open = DatabaseHelper.instance.database;
  }

  void _retry() {
    setState(() {
      _open = DatabaseHelper.instance.database;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _open,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return RecoveryScreen(onRetry: _retry);
        }
        return widget.showOnboarding
            ? const OnboardingScreen()
            : const MainShell();
      },
    );
  }
}
