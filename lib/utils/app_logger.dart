import 'package:flutter/foundation.dart';

void logError(String context, Object error, [StackTrace? stackTrace]) {
  debugPrint('[TalaKo][$context] $error');
  if (stackTrace != null && kDebugMode) {
    debugPrint('[TalaKo][$context] stack:\n$stackTrace');
  }
}

void logInfo(String message) {
  if (kDebugMode) debugPrint('[TalaKo] $message');
}
