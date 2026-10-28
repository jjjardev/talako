import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../utils/app_logger.dart';
import '../utils/backup_service.dart';

class RecoveryScreen extends StatefulWidget {
  final VoidCallback onRetry;

  const RecoveryScreen({super.key, required this.onRetry});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;

  Future<void> _exportCorrupt() async {
    setState(() => _busy = true);
    try {
      final srcPath = await DatabaseHelper.instance.getDbFilePath();
      final src = File(srcPath);
      if (!await src.exists()) throw Exception('Database file not found');
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final dest = File('${dir.path}/talako_corrupt_$stamp.db');
      await src.copy(dest.path);
      await Share.shareXFiles([XFile(dest.path)],
          subject: 'TalaKo Corrupt Database');
    } catch (e, s) {
      logError('recovery-export', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final error = await BackupService.pickAndRestoreRawDb();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Database recovery')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 72, color: Colors.orange.shade700),
              const SizedBox(height: 16),
              const Text('TalaKo could not open the database',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'The database file was not deleted. Export a copy for '
                'safekeeping, then restore a known-good .db backup.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCorrupt,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Export corrupt database'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore from backup'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
