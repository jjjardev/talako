import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/theme_provider.dart';
import '../providers/customers_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/transactions_provider.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';
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
          Card(
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: Text(themeProvider.isDarkMode ? 'Dark theme active' : 'Light theme active'),
                  value: themeProvider.isDarkMode,
                  onChanged: (_) => themeProvider.toggleTheme(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.takeout_dining_outlined),
                  title: const Text('Owner Took Stock'),
                  subtitle: const Text('Log personal consumption'),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => const OwnerUseSheet(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: const Text('Personal Use Log'),
                  subtitle: const Text('What you consumed yourself'),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PersonalUseLogScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.assessment_outlined),
                  title: const Text('Monthly Store Report'),
                  subtitle: const Text('Sales, spoilage, top sellers'),
                  onTap: () => _showMonthlyReport(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Settled Debts'),
                  subtitle: const Text('View fully paid customers'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettledDebtsScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                  subtitle: const Text('Replace with a .db file'),
                  onTap: () => _importRawDb(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMonthlyReport(BuildContext context) async {
    final now = DateTime.now();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MonthlyReportSheet(month: now),
    );
  }

  Future<void> _exportJsonBackup(BuildContext context) async {
    try {
      final data = await DatabaseHelper.instance.exportBackup();
      if (data == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
        }
        return;
      }
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
      final file = File('${dir.path}/talako_backup_$stamp.json');
      await file.writeAsString(jsonString);

      if (context.mounted) {
        await Share.shareXFiles([XFile(file.path)], subject: 'TalaKo Backup');
      }
    } catch (e, s) {
      logError("settings", e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importJsonBackup(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Backup'),
        content: const Text('This will replace ALL current data. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final file = File(result.files.first.path!);
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      if (!data.containsKey('items') || !data.containsKey('customers')) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid backup file')));
        }
        return;
      }

      await DatabaseHelper.instance.importBackup(data);

      if (context.mounted) {
        context.read<CustomersProvider>().loadCustomers();
        context.read<TransactionsProvider>().loadActiveTransactions();
        context.read<InventoryProvider>().loadInventory();        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored successfully')));
      }
    } catch (e, s) {
      logError("settings", e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _exportRawDb(BuildContext context) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final srcPath = await dbHelper.getDbFilePath();
      final srcFile = File(srcPath);
      if (!await srcFile.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No database file found')));
        }
        return;
      }

      await dbHelper.checkpoint();

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${dir.path}/talako_backup_$timestamp.db';
      await srcFile.copy(destPath);

      if (context.mounted) {
        await Share.shareXFiles([XFile(destPath)], subject: 'TalaKo Database Backup');
      }
    } catch (e, s) {
      logError("settings", e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importRawDb(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Database'),
        content: const Text('This will replace ALL current data. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.close();

      final srcFile = File(result.files.first.path!);
      final destPath = await dbHelper.getDbFilePath();
      await srcFile.copy(destPath);

      if (context.mounted) {
        context.read<CustomersProvider>().loadCustomers();
        context.read<TransactionsProvider>().loadActiveTransactions();
        context.read<InventoryProvider>().loadInventory();        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database restored successfully')));
      }
    } catch (e, s) {
      logError("settings", e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
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
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m - 1];

  Widget _reportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_monthName(widget.month.month)} ${widget.month.year} Report',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _reportRow('Sales recorded', formatCurrency(r['sales'] as double)),
                _reportRow('Collected', formatCurrency(r['collected'] as double)),
                _reportRow('Personal use', formatCurrency(r['owner_use'] as double)),
                _reportRow('Spoilage loss', formatCurrency(r['spoilage'] as double)),
                const Divider(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Text('Top sellers', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    topItems.isEmpty ? 'No sales recorded this month yet.' : '  $topItems',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share report'),
                  onPressed: () => Share.share('''
${_monthName(widget.month.month)} ${widget.month.year} Store Report

Sales recorded: ${formatCurrency(r['sales'] as double)}
Collected: ${formatCurrency(r['collected'] as double)}
Personal use: ${formatCurrency(r['owner_use'] as double)}
Spoilage loss: ${formatCurrency(r['spoilage'] as double)}

Top sellers:
  $topItems''', subject: 'TalaKo Monthly Report'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
