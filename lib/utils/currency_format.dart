import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');

String formatCurrency(double amount) => _currencyFormat.format(amount);
