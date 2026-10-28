import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');

/// Formats integer minor units (centavos) as peso currency.
String formatCurrency(int minor) => _currencyFormat.format(minor / 100);
