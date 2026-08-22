import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class PersonalUseLogScreen extends StatefulWidget {
  const PersonalUseLogScreen({super.key});

  @override
  State<PersonalUseLogScreen> createState() => _PersonalUseLogScreenState();
}

class _PersonalUseLogScreenState extends State<PersonalUseLogScreen> {
  List<Map<String, dynamic>> _log = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final log = await context.read<InventoryProvider>().ownerUseLog();
    if (!mounted) return;
    setState(() {
      _log = log;
      _loading = false;
    });
  }

  double get _totalThisMonth {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    double sum = 0;
    for (final row in _log) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      if (date != null && date.isAfter(monthStart)) {
        sum += (row['total_amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Use Log'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Consumed this month',
                            style: TextStyle(
                                fontSize: 15, color: Colors.grey.shade800)),
                        Text(formatCurrency(_totalThisMonth),
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _log.isEmpty
                      ? Center(
                          child: Text('Nothing recorded yet',
                              style: TextStyle(color: Colors.grey.shade500)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _log.length,
                            itemBuilder: (context, i) {
                              final row = _log[i];
                              final names = (row['item_names'] as String? ?? '');
                              return ListTile(
                                leading: const Icon(Icons.takeout_dining_outlined,
                                    color: Colors.orange),
                                title: Text(names.isEmpty
                                    ? 'Stock taken'
                                    : names.replaceAll(',', ', ')),
                                subtitle: Text(formatDate(row['date'] as String)),
                                trailing: Text(
                                  formatCurrency(
                                      (row['total_amount'] as num).toDouble()),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
