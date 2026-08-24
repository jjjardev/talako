import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/item.dart';
import '../providers/customers_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/transactions_provider.dart';
import '../models/stock_enums.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/snackbars.dart';

class AddCreditSheet extends StatefulWidget {
  const AddCreditSheet({super.key});

  @override
  State<AddCreditSheet> createState() => _AddCreditSheetState();
}

class _AddCreditSheetState extends State<AddCreditSheet> {
  final _db = DatabaseHelper.instance;
  final _customerController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  List<String> _customerSuggestions = [];
  List<String> _itemSuggestions = [];
  Map<String, Item> _itemsByLowerName = {};
  final List<_LineItem> _items = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items.add(_LineItem());
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final customers = await _db.getAllCustomers();
    final itemNames = await _db.getAllItemNames();
    final items = await _db.getAllItems(newestFirst: false);
    if (!mounted) return;
    setState(() {
      _customerSuggestions = customers.map((c) => c.name).toList();
      _itemSuggestions = itemNames;
      _itemsByLowerName = {for (final i in items) i.name.toLowerCase(): i};
    });
  }

  /// Exact, case-insensitive match against dishes first, then catalog items.
  void _autofillPrice(_LineItem line, String rawName) {
    if (line.priceTouched) return;
    final key = rawName.trim().toLowerCase();
    if (key.isEmpty) return;
    final price = _itemsByLowerName[key]?.price;
    if (price == null || price <= 0) return;
    line.price = price;
    line.priceController.text = _formatPlain(price);
  }

  static String _formatPlain(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);


  double get _total {
    double sum = 0;
    for (final item in _items) {
      sum += item.quantity * item.price;
    }
    return sum;
  }

  @override
  void dispose() {
    _customerController.dispose();
    _scrollController.dispose();
    for (final item in _items) {
      item.nameController.dispose();
      item.priceController.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter customer name')));
      return;
    }

    final validItems = _items.where((i) => i.itemName.trim().isNotEmpty && i.price > 0).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }

    setState(() => _saving = true);

    final provider = context.read<CustomersProvider>();
    final customer = await provider.getOrCreateCustomer(_customerController.text.trim());
    if (!mounted) {
      return;
    }
    if (customer == null || customer.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create customer')));
      setState(() => _saving = false);
      return;
    }

    final itemNames = validItems.map((i) => i.itemName.trim()).toList();
    final quantities = validItems.map((i) => i.quantity).toList();
    final prices = validItems.map((i) => i.price).toList();

    final txnProvider = context.read<TransactionsProvider>();
    try {
      final txnId =
          await txnProvider.addTransactionWithItemNames(
              customer.id!, itemNames, quantities, prices);
      if (mounted) {
        setState(() => _saving = false);
        // Capture everything needed before popping - after Navigator.pop
        // this sheet's BuildContext is deactivated and unusable.
        final messenger = ScaffoldMessenger.of(context);
        final inv = context.read<InventoryProvider>();
        Navigator.pop(context);
        showAutoDismissSnackBar(
          messenger,
          message: 'Credit added',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              messenger.clearSnackBars();
              txnProvider.deleteTransaction(txnId);
            },
          ),
        );
        await inv.loadInventory();
        await _promptOutOfStockRestock(inv, itemNames, messenger);
      }
    } catch (e, s) {
      logError('add-credit', e, s);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  /// Non-blocking nudge: selling something that was marked Out of Stock
  /// means it is clearly back on the shelf. Uses only objects captured
  /// before the sheet was dismissed - never a BuildContext.
  Future<void> _promptOutOfStockRestock(
    InventoryProvider inv,
    List<String> soldNames,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      if (inv.items.isEmpty) return; // inventory never scanned - stay silent
      final oos = inv.items
          .where((i) =>
              i.stockStatus == StockStatus.outOfStock &&
              soldNames.any((s) => s.toLowerCase() == i.name.toLowerCase()))
          .toList();
      if (oos.isEmpty || oos.first.id == null) return;
      final target = inv.itemById(oos.first.id!);
      if (target == null) return;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('${target.name} was marked Out of Stock'),
        action: SnackBarAction(
          label: 'Back in stock',
          onPressed: () async {
            await inv.updateItem(
              target.copyWith(stockStatus: StockStatus.wellStocked),
            );
          },
        ),
      ));
    } catch (e) {
      logError('oos-nudge', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.add_circle_outline, size: 24),
                const SizedBox(width: 8),
                const Text('New Credit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return [];
                return _customerSuggestions.where((s) =>
                  s.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                if (_customerController.text.isNotEmpty && controller.text.isEmpty) {
                  controller.text = _customerController.text;
                }
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onChanged: (v) => _customerController.text = v,
                );
              },
              onSelected: (v) {
                _customerController.text = v;
              },
            ),
            const SizedBox(height: 12),
            const Text('Items', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                child: ListView(
                  controller: _scrollController,
                  children: [
                    ..._items.map((item) => _buildItemRow(item)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add another item'),
                      onPressed: () {
                        setState(() => _items.insert(0, _LineItem()));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  formatCurrency(_total),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Credit', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(_LineItem item) {
    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return [];
                      return _itemSuggestions.where((s) =>
                        s.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                      if (item.nameController.text.isNotEmpty && controller.text.isEmpty) {
                        controller.text = item.nameController.text;
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Item',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        onChanged: (v) {
                          item.itemName = v;
                          _autofillPrice(item, v);
                        },
                      );
                    },
                    onSelected: (v) {
                      item.itemName = v;
                      item.nameController.text = v;
                      setState(() => _autofillPrice(item, v));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: item.quantity > 1
                            ? () => setState(() => item.quantity--)
                            : null,
                      ),
                      Text('${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => item.quantity++),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price (₱)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      prefixText: '₱ ',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      // Manual edits win - autofill never overwrites these.
                      item.priceTouched = true;
                      item.price = double.tryParse(v) ?? 0;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: Text(
                    formatCurrency(item.quantity * item.price),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _items.remove(item)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItem {
  static int _nextId = 0;
  final int id = _nextId++;
  String itemName = '';
  int quantity = 1;
  double price = 0;
  /// True once the user types a price manually - autofill then backs off.
  bool priceTouched = false;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}
