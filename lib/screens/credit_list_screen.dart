import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customers_provider.dart';
import '../widgets/customer_tile.dart';
import 'customer_detail_screen.dart';

class CreditListScreen extends StatefulWidget {
  const CreditListScreen({super.key});

  @override
  State<CreditListScreen> createState() => _CreditListScreenState();
}

class _CreditListScreenState extends State<CreditListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomersProvider>().loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (query) {
                context.read<CustomersProvider>().setSearch(query);
              },
            ),
          ),
          Expanded(
            child: Consumer<CustomersProvider>(
              builder: (context, provider, _) {
                if (provider.summaries.isEmpty) {
                  return const Center(child: Text('No customers with active utang'));
                }
                return ListView.builder(
                  itemCount: provider.summaries.length,
                  itemBuilder: (context, index) {
                    final s = provider.summaries[index];
                    return CustomerTile(
                      name: s.customer.name,
                      balance: s.balance,
                      hasOverdue: s.hasOverdue,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerDetailScreen(customer: s.customer),
                          ),
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) => provider.loadCustomers());
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}