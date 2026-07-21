import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/credit_entry.dart';
import '../models/item.dart';
import '../providers/customers_provider.dart';
import '../providers/items_provider.dart';
import '../utils/currency_format.dart';

class AddCreditScreen extends StatefulWidget {
  const AddCreditScreen({super.key});

  @override
  State<AddCreditScreen> createState() => AddCreditScreenState();
}

class AddCreditScreenState extends State<AddCreditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _itemController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  FocusNode? _itemFocusNode;
  final _priceFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  final _db = DatabaseHelper.instance;

  List<String> _customerSuggestions = [];
  List<String> _itemSuggestions = [];
  double _total = 0;
  bool _saving = false;
  int _itemsAddedForCustomer = 0;
  bool _isExistingItem = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _quantityController.addListener(_calculateTotal);
    _priceController.addListener(_calculateTotal);
  }

  void _loadSuggestions() {
    _loadSuggestionsFromDb();
  }

  Future<void> _loadSuggestionsFromDb() async {
    final customers = await _db.getAllCustomers();
    final items = await _db.getAllItems();
    if (!mounted) return;
    setState(() {
      _customerSuggestions = customers.map((c) => c.name).toList();
      _itemSuggestions = items.map((i) => i.name).toList();
    });
  }

  void _calculateTotal() {
    final price = double.tryParse(_priceController.text) ?? 0;
    final qty = int.tryParse(_quantityController.text) ?? 1;
    setState(() => _total = price * qty);
  }

  void _onItemChanged(String value) {
    final lower = value.toLowerCase();
    final i = _itemSuggestions.indexWhere((s) => s.toLowerCase() == lower);
    _isExistingItem = i >= 0;
    if (_isExistingItem) {
      final name = _itemSuggestions[i];
      _db.getItemByName(name).then((item) {
        if (item != null && _itemController.text == value) {
          _priceController.text = item.price.toString();
        }
      });
    }
  }

  void _incrementQty() {
    final current = int.tryParse(_quantityController.text) ?? 1;
    _quantityController.text = (current + 1).toString();
  }

  void _decrementQty() {
    final current = int.tryParse(_quantityController.text) ?? 1;
    if (current > 1) {
      _quantityController.text = (current - 1).toString();
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _itemController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _priceFocusNode.dispose();
    _quantityFocusNode.dispose();
    _customerSuggestions.clear();
    _itemSuggestions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Credit'),
        actions: [
          if (_itemsAddedForCustomer > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Added: $_itemsAddedForCustomer',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
          if (_itemsAddedForCustomer > 0)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                    decoration: const InputDecoration(labelText: 'Customer Name'),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) => _customerController.text = v,
                    onFieldSubmitted: (_) => _itemFocusNode?.requestFocus(),
                  );
                },
                onSelected: (v) {
                  _customerController.text = v;
                  _itemFocusNode?.requestFocus();
                },
              ),
              const SizedBox(height: 16),
              Autocomplete<String>(
                key: ValueKey('item_${_itemSuggestions.length}'),
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return [];
                  return _itemSuggestions.where((s) =>
                    s.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                  _itemFocusNode = focusNode;
                  if (_itemController.text.isNotEmpty && controller.text.isEmpty) {
                    controller.text = _itemController.text;
                  }
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Item'),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) {
                      _itemController.text = v;
                      _onItemChanged(v);
                    },
                    onFieldSubmitted: (_) => _quantityFocusNode.requestFocus(),
                  );
                },
                onSelected: (v) {
                  _itemController.text = v;
                  _isExistingItem = true;
                  _onItemChanged(v);
                  _quantityFocusNode.requestFocus();
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                focusNode: _priceFocusNode,
                decoration: const InputDecoration(labelText: 'Price per Unit (₱)'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final p = double.tryParse(v);
                  if (p == null || p <= 0) return 'Enter valid price > 0';
                  return null;
                },
                onFieldSubmitted: (_) => _quantityFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _decrementQty,
                  ),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      controller: _quantityController,
                      focusNode: _quantityFocusNode,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final q = int.tryParse(v);
                        if (q == null || q < 1) return '≥ 1';
                        return null;
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _incrementQty,
                  ),
                  const Spacer(),
                  Text('Total: ', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    formatCurrency(_total),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add Credit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final customersProvider = context.read<CustomersProvider>();
      final customer = await customersProvider.getOrCreateCustomer(_customerController.text.trim());
      if (customer == null) throw Exception('Could not create customer');

      final itemName = _itemController.text.trim();
      final price = double.parse(_priceController.text.trim());

      final existing = await _db.getItemByName(itemName);
      if (existing == null) {
        await _db.insertItem(Item(name: itemName, price: price));
        if (mounted) context.read<ItemsProvider>().loadItems();
        _itemSuggestions.add(itemName);
      }

      final credit = CreditEntry(
        customerId: customer.id!,
        itemName: itemName,
        quantity: int.parse(_quantityController.text.trim()),
        pricePerUnit: price,
        total: _total,
      );
      await customersProvider.addCredit(credit);

      setState(() {
        _itemsAddedForCustomer++;
        _saving = false;
        _itemController.clear();
        _priceController.clear();
        _quantityController.text = '1';
        _isExistingItem = false;
        _total = 0;
      });

      _itemFocusNode?.requestFocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _saving = false);
      }
    }
  }

  void resetForNewCustomer() {
    setState(() {
      _customerController.clear();
      _itemController.clear();
      _priceController.clear();
      _quantityController.text = '1';
      _isExistingItem = false;
      _total = 0;
      _itemsAddedForCustomer = 0;
    });
  }
}
