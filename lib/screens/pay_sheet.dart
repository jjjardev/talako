import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/currency_format.dart';
import '../utils/money.dart';

class PaySheet extends StatefulWidget {
  final int transactionId;
  final String customerName;
  final int remainingBalance;

  const PaySheet({
    super.key,
    required this.transactionId,
    required this.customerName,
    required this.remainingBalance,
  });

  @override
  State<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<PaySheet> {
  String _input = '';
  bool _submitting = false;

  int get _displayAmount => parseMajorToMinor(_input) ?? 0;

  int get _newRemaining {
    final paid = _displayAmount;
    return widget.remainingBalance - paid;
  }

  bool get _isValid => _displayAmount > 0 && _displayAmount <= widget.remainingBalance;

  bool get _isFullPayment => isFullPayment(_displayAmount, widget.remainingBalance);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.payments, size: 24, color: Colors.green),
              const SizedBox(width: 8),
              Text('Pay - ${widget.customerName}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Remaining Balance',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
                  const SizedBox(height: 4),
                  Text(
                    formatCurrency(widget.remainingBalance),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  Text('Payment Amount',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
                  const SizedBox(height: 4),
                  Text(
                    _input.isEmpty ? '₱ 0.00' : formatCurrency(_displayAmount),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _isValid ? Colors.green.shade700 : Colors.red,
                    ),
                  ),
                  if (_input.isNotEmpty && _isValid) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isFullPayment ? 'Fully paid' : 'Remaining: ${formatCurrency(_newRemaining)}',
                      style: TextStyle(fontSize: 14, color: _isFullPayment ? Colors.green : Colors.orange),
                    ),
                  ],
                  if (_input.isNotEmpty && !_isValid)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Amount exceeds balance', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          if (_isValid && !_isFullPayment)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.done_all, size: 16,
                      color: Colors.white),
                  label: Text(
                      'Pay full ${formatCurrency(widget.remainingBalance)}'),
                  backgroundColor: Colors.green.shade600,
                  labelStyle: const TextStyle(color: Colors.white),
                  onPressed: () => setState(() {
                    _input = formatMinorPlain(widget.remainingBalance);
                  }),
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isValid && !_submitting ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _isFullPayment
                          ? 'Confirm Full Payment'
                          : 'Confirm Payment (${formatCurrency(_displayAmount)})',
                      style: const TextStyle(fontSize: 18),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _buildNumpad(),
        ],
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Row(
          children: [
            _numpadButton('1'),
            _numpadButton('2'),
            _numpadButton('3'),
          ],
        ),
        Row(
          children: [
            _numpadButton('4'),
            _numpadButton('5'),
            _numpadButton('6'),
          ],
        ),
        Row(
          children: [
            _numpadButton('7'),
            _numpadButton('8'),
            _numpadButton('9'),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: OutlinedButton(
                  onPressed: () {
                    if (!_input.contains('.')) {
                      setState(() => _input += _input.isEmpty ? '0.' : '.');
                    }
                  },
                  style: _numpadStyle(),
                  child: const Text('.', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
            _numpadButton('0'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
                    });
                  },
                  style: _numpadStyle(),
                  child: const Icon(Icons.backspace, size: 24),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numpadButton(String digit) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              if (_input.length < 10) {
                if (_input.contains('.')) {
                  final decimal = _input.split('.');
                  if (decimal[1].length < 2) _input += digit;
                } else {
                  _input += digit;
                }
              }
            });
          },
          style: _numpadStyle(),
          child: Text(digit, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  ButtonStyle _numpadStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: Colors.grey.shade300),
    );
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();
    final provider = context.read<TransactionsProvider>();
    if (_isFullPayment) {
      await provider.processPayment(widget.transactionId, widget.remainingBalance);
    } else {
      await provider.processPayment(widget.transactionId, _displayAmount);
    }
    if (mounted) {
      Navigator.pop(context, _isFullPayment ? widget.remainingBalance : _displayAmount);
    }
  }
}