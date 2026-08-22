import 'package:flutter/material.dart';
import 'kitchen_screen.dart';
import 'palengke_screen.dart';
import 'stock_watch_screen.dart';

class StockHomeScreen extends StatefulWidget {
  const StockHomeScreen({super.key});

  @override
  State<StockHomeScreen> createState() => _StockHomeScreenState();
}

class _StockHomeScreenState extends State<StockHomeScreen> {
  _Segment _segment = _Segment.shelf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<_Segment>(
              segments: const [
                ButtonSegment(value: _Segment.shelf, label: Text('Shelf'), icon: Icon(Icons.storefront, size: 18)),
                ButtonSegment(value: _Segment.kitchen, label: Text('Kitchen'), icon: Icon(Icons.soup_kitchen_outlined, size: 18)),
                ButtonSegment(value: _Segment.palengke, label: Text('Palengke'), icon: Icon(Icons.shopping_basket_outlined, size: 18)),
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
