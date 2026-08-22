import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'kitchen_screen.dart';
import 'palengke_screen.dart';
import 'stock_watch_screen.dart';
import '../providers/inventory_provider.dart';

class StockHomeScreen extends StatefulWidget {
  const StockHomeScreen({super.key});

  @override
  State<StockHomeScreen> createState() => _StockHomeScreenState();
}

class _StockHomeScreenState extends State<StockHomeScreen> {
  _Segment _segment = _Segment.shelf;

  bool get _onPalengke => _segment == _Segment.palengke;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        centerTitle: true,
        actions: [
          if (_onPalengke)
            IconButton(
              tooltip: 'Share list',
              icon: const Icon(Icons.share),
              onPressed: () =>
                  sharePalengkeList(context.read<InventoryProvider>()),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<_Segment>(
              segments: const [
                ButtonSegment(value: _Segment.shelf, label: Text('Shelf')),
                ButtonSegment(value: _Segment.kitchen, label: Text('Kitchen')),
                ButtonSegment(value: _Segment.palengke, label: Text('Palengke')),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
          Expanded(
            child: switch (_segment) {
              _Segment.shelf => const StockWatchScreen(),
              _Segment.kitchen => const KitchenScreen(),
              _Segment.palengke => const PalengkeScreen(),
            },
          ),
        ],
      ),
    );
  }
}

enum _Segment { shelf, kitchen, palengke }
