import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utils/date_format.dart';

class SettledDebtsScreen extends StatefulWidget {
  const SettledDebtsScreen({super.key});

  @override
  State<SettledDebtsScreen> createState() => _SettledDebtsScreenState();
}

class _SettledDebtsScreenState extends State<SettledDebtsScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _settledCustomers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _settledCustomers = await _db.getSettledCustomers();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settled Debts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _settledCustomers.isEmpty
              ? const Center(child: Text('No settled debts yet'))
              : ListView.builder(
                  itemCount: _settledCustomers.length,
                  itemBuilder: (context, index) {
                    final item = _settledCustomers[index];
                    return ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(item['name'] as String),
                      subtitle: Text('Last cleared: ${formatDateShort(item['last_cleared'] as String)}'),
                    );
                  },
                ),
    );
  }
}