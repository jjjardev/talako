import 'package:intl/intl.dart';

final _dateFormat = DateFormat('MMM dd, yyyy - h:mm a');
final _dateFormatShort = DateFormat('MMM dd, yyyy');

String formatDate(String iso8601) {
  final dt = DateTime.parse(iso8601);
  return _dateFormat.format(dt);
}

String formatDateShort(String iso8601) {
  final dt = DateTime.parse(iso8601);
  return _dateFormatShort.format(dt);
}
