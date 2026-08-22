import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/theme_provider.dart';
import '../providers/customers_provider.dart';
import '../providers/transactions_provider.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';
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
      final file = File('${dir.path}/talako_backup.json');
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored successfully')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database restored successfully')));
      }
    } catch (e, s) {
      logError("settings", e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }
}