import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import 'app_logger.dart';

class BackupService {
  static const _lastBackupKey = 'last_backup_at';
  static const _dismissedKey = 'backup_banner_dismissed_at';

  static String _stamp(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  static Future<File> exportJsonBackup() async {
    final data = await DatabaseHelper.instance.exportBackup();
    if (data == null) throw Exception('No data to export');
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/talako_backup_${_stamp(DateTime.now())}.json');
    await file.writeAsString(jsonString);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
    return file;
  }

  static Future<File> exportRawDb() async {
    final helper = DatabaseHelper.instance;
    final src = File(await helper.getDbFilePath());
    if (!await src.exists()) throw Exception('No database file found');
    await helper.checkpoint();
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        File('${dir.path}/talako_backup_${DateTime.now().millisecondsSinceEpoch}.db');
    await src.copy(dest.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
    return dest;
  }

  static Future<void> importJsonFile(String path) async {
    final file = File(path);
    final jsonString = await file.readAsString();
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    await DatabaseHelper.instance.importBackup(data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
  }

  /// Picks a JSON backup and imports it. Returns an error message, or null.
  static Future<String?> pickAndImportJson() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = (result == null || result.files.isEmpty) ? null : result.files.first.path;
    if (path == null) return null;
    try {
      if (path.toLowerCase().endsWith('.db')) {
        await DatabaseHelper.instance.restoreRawDatabase(path);
      } else {
        await importJsonFile(path);
      }
      return null;
    } catch (e, s) {
      logError('import-json', e, s);
      return 'Import failed: $e';
    }
  }

  static Future<String?> pickAndRestoreRawDb() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = (result == null || result.files.isEmpty) ? null : result.files.first.path;
    if (path == null) return null;
    try {
      if (!path.toLowerCase().endsWith('.db')) {
        return 'Choose a .db database file';
      }
      await DatabaseHelper.instance.restoreRawDatabase(path);
      return null;
    } catch (e, s) {
      logError('restore-raw-db', e, s);
      return 'Restore failed: $e';
    }
  }

  static Future<DateTime?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastBackupKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> markBackedUp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
  }

  static Future<bool> shouldShowBanner() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedRaw = prefs.getString(_dismissedKey);
    final dismissed = dismissedRaw == null ? null : DateTime.tryParse(dismissedRaw);
    if (dismissed != null &&
        DateTime.now().difference(dismissed).inDays < 7) {
      return false;
    }
    final last = await lastBackupAt();
    if (last == null) return true;
    return DateTime.now().difference(last).inDays >= 30;
  }

  static Future<void> dismissBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, DateTime.now().toIso8601String());
  }
}
