import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../providers/customers_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/app_logger.dart';
import '../utils/backup_service.dart';
import '../utils/currency_format.dart';
import 'owner_use_sheet.dart';
import 'personal_use_log_screen.dart';
import 'settled_debts_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Appearance'),
          Card(
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined)),
                  ],
                  selected: {themeProvider.themeMode},
                  onSelectionChanged: (s) =>
                      themeProvider.setThemeMode(s.first),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section('Record'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.takeout_dining_outlined),
                  title: const Text('Personal use'),
                  subtitle: const Text('Log personal consumption'),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => const OwnerUseSheet(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: const Text('Personal use log'),
                  subtitle: const Text('What you consumed yourself'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PersonalUseLogScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.assessment_outlined),
                  title: const Text('Monthly Summary'),
                  subtitle: const Text(
                      'Sales, collected, personal use, spoilage, net, top sellers'),
                  onTap: () => _showMonthlyReport(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section('Data'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Settled Debts'),
              subtitle: const Text('View fully paid customers'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettledDebtsScreen())),
            ),
          ),
          const SizedBox(height: 16),
          _section('Backup'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Export Backup (JSON)'),
                  subtitle: const Text('Save and share database as JSON'),
                  onTap: () => _exportJsonBackup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import Backup (JSON)'),
                  subtitle: const Text('Restore from JSON file'),
                  onTap: () => _importJsonBackup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Export Raw Database'),
                  subtitle: const Text('Save and share a copy of the database'),
                  onTap: () => _exportRawDb(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Import Raw Database'),
                  subtitle: const Text('Validate and replace with a .db file'),
                  onTap: () => _importRawDb(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section('About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('TalaKo'),
              subtitle: Text('Version 2.16.0 · Offline only'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Future<void> _showMonthlyReport(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MonthlyReportSheet(month: DateTime.now()),
    );
  }

  Future<void> _exportJsonBackup(BuildContext context) async {
    try {
      final file = await BackupService.exportJsonBackup();
      if (context.mounted) {
        await Share.shareXFiles([XFile(file.path)], subject: 'TalaKo Backup');
      }
    } catch (e, s) {
      logError('settings', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importJsonBackup(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.path;
    if (path == null || !context.mounted) return;

    final confirmed = await _confirmReplace(context);
    if (confirmed != true || !context.mounted) return;

    try {
      final file = File(path);
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      await DatabaseHelper.instance.importBackup(data);
      await BackupService.markBackedUp();
      if (!context.mounted) return;
      context.read<CustomersProvider>().loadCustomers();
      context.read<TransactionsProvider>().loadActiveTransactions();
      context.read<InventoryProvider>().loadInventory();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')));
    } catch (e, s) {
      logError('settings', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _exportRawDb(BuildContext context) async {
    try {
      final file = await BackupService.exportRawDb();
      if (context.mounted) {
        await Share.shareXFiles([XFile(file.path)],
            subject: 'TalaKo Database Backup');
      }
    } catch (e, s) {
      logError('settings', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importRawDb(BuildContext context) async {
    String? path;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      path = (result == null || result.files.isEmpty)
          ? null
          : result.files.first.path;
    } catch (e, s) {
      logError('settings', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('File picker failed: $e')));
      }
      return;
    }
    if (path == null || !context.mounted) return;
    if (!path.toLowerCase().endsWith('.db')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a .db database file')));
      return;
    }

    final confirmed = await _confirmReplace(context);
    if (confirmed != true || !context.mounted) return;

    try {
      await DatabaseHelper.instance.restoreRawDatabase(path);
      await BackupService.markBackedUp();
      if (!context.mounted) return;
      context.read<CustomersProvider>().loadCustomers();
      context.read<TransactionsProvider>().loadActiveTransactions();
      context.read<InventoryProvider>().loadInventory();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database restored successfully')));
    } catch (e, s) {
      logError('settings', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<bool?> _confirmReplace(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
            'This will replace ALL current data. The file is validated first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _MonthlyReportSheet extends StatefulWidget {
  final DateTime month;

  const _MonthlyReportSheet({required this.month});

  @override
  State<_MonthlyReportSheet> createState() => _MonthlyReportSheetState();
}

class _MonthlyReportSheetState extends State<_MonthlyReportSheet> {
  late final Future<Map<String, dynamic>> _report =
      context.read<InventoryProvider>().monthlyReport(widget.month);

  String _monthName(int m) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ][m - 1];

  Widget _reportRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _report,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final r = snap.data!;
          final topItems = (r['top_items'] as List)
              .map((row) => '${row['order_count']}x ${(row['norm_name'] as String)}')
              .join('\n  ');
          final cash = r['cash_sales'] as int? ?? 0;
          final net = r['net'] as int? ?? 0;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_monthName(widget.month.month)} ${widget.month.year} Summary',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _reportRow('Sales recorded', formatCurrency(r['sales'] as int)),
                _reportRow('Cash sales', formatCurrency(cash)),
                _reportRow('Collected', formatCurrency(r['collected'] as int)),
                _reportRow(
                    'Personal use', formatCurrency(r['owner_use'] as int)),
                _reportRow(
                    'Spoilage loss', formatCurrency(r['spoilage'] as int)),
                const Divider(height: 20),
                _reportRow('Net', formatCurrency(net), bold: true),
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Top sellers',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    topItems.isEmpty
                        ? 'No sales recorded this month yet.'
                        : '  $topItems',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share summary'),
                  onPressed: () => Share.share('''
${_monthName(widget.month.month)} ${widget.month.year} Monthly Summary

Sales recorded: ${formatCurrency(r['sales'] as int)}
Cash sales: ${formatCurrency(cash)}
Collected: ${formatCurrency(r['collected'] as int)}
Personal use: ${formatCurrency(r['owner_use'] as int)}
Spoilage loss: ${formatCurrency(r['spoilage'] as int)}
Net: ${formatCurrency(net)}

Top sellers:
  $topItems''', subject: 'TalaKo Monthly Summary'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
