import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../utils/app_logger.dart';
import '../utils/backup_service.dart';
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
      icon: Icons.payments_outlined,
      title: 'Money',
      body:
          'Track credit sales and payments in one place. Partial payments are supported.\n\nAll amounts are stored to the centavo.',
    ),
    _PageData(
      icon: Icons.inventory_2_outlined,
      title: 'Shelf',
      body:
          'Tap items to mark them Well Stocked, Running Low, or Out of Stock.\n\nNo counting - a 30-second scan is enough.',
    ),
    _PageData(
      icon: Icons.shopping_basket_outlined,
      title: 'Shopping',
      body:
          'Mark items Running Low or Out and the Shopping List builds itself.\n\nShare it before heading to the market.',
    ),
    _PageData(
      icon: Icons.backup_outlined,
      title: 'Backup',
      body:
          'Your data stays on this device. Export a JSON or raw database backup regularly.\n\nRestore it here on a new phone.',
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
    await prefs.setInt('onboarding_version', 4);
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

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.path;
    if (path == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore a backup?'),
        content: const Text(
            'This replaces the empty database with the selected backup.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (path.toLowerCase().endsWith('.json')) {
        final jsonString = await File(path).readAsString();
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        await DatabaseHelper.instance.importBackup(data);
      } else if (path.toLowerCase().endsWith('.db')) {
        await DatabaseHelper.instance.restoreRawDatabase(path);
        await DatabaseHelper.instance.database;
      } else {
        throw Exception('Choose a TalaKo .json or .db backup');
      }
      await BackupService.markBackedUp();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')));
      await _completeOnboarding();
    } catch (e, s) {
      logError('onboarding-restore', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
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
                        Icon(page.icon,
                            size: 96, color: theme.colorScheme.primary),
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
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        if (i == 0 || i == _pages.length - 1) ...[
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _restoreBackup,
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text('Restore a backup'),
                          ),
                        ],
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
                  Row(children: List.generate(_pages.length, _buildDot)),
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
