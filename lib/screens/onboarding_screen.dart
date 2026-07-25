import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _PageData(
      icon: Icons.store,
      title: 'Welcome to TalaKo',
      body:
          'A simple, offline app to track your store\'s credit sales.\n\nNo internet required.',
    ),
    _PageData(
      icon: Icons.receipt_long,
      title: 'Collections Dashboard',
      body:
          'See all active debts sorted by date, oldest first.\n\nEach tile shows the full item breakdown with prices. Red = overdue (14+ days), orange = 7+ days. Tap Pay to record a payment.',
    ),
    _PageData(
      icon: Icons.add_circle_outline,
      title: 'Recording Credits',
      body:
          'Tap the + button to record a credit.\n\nType the customer name and item \u2014 suggestions appear automatically. You can add multiple items for the same customer.',
    ),
    _PageData(
      icon: Icons.settings,
      title: 'Settings & Backup',
      body:
          'View settled debts, restore backups, and toggle dark/light mode from the Settings tab.',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('onboarding_version', 2);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  void _onNext() {
    if (_isLastPage) {
      _completeOnboarding();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 96, color: theme.colorScheme.primary),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(_pages.length, _buildDot),
                  ),
                  FilledButton(
                    onPressed: _onNext,
                    child: Text(_isLastPage ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    final isActive = index == _currentPage;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String body;

  const _PageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}