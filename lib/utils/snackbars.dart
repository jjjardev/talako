import 'dart:async';

import 'package:flutter/material.dart';

int _latestSeq = 0;

/// Shows a [SnackBar] that is guaranteed to dismiss itself.
///
/// The framework's auto-hide timer occasionally never fires on some devices
/// when the snackbar is shown around route transitions (lingering snackbars
/// were reported across v2.4.1, v2.4.2 and v2.5.x). This wrapper arms a
/// watchdog: shortly after [duration] elapses, if this snackbar is somehow
/// still open, it is hidden explicitly.
///
/// Safety properties:
/// - The watchdog cancels the moment the snackbar closes (any reason).
/// - It only fires while this snackbar is the newest one shown, so a newer
///   snackbar is never dismissed by an older watchdog. Older queued bars are
///   drained naturally: each new bar's watchdog hides whatever is at the head
///   of the queue until the new bar itself closes.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAutoDismissSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
  Duration watchdogTick = const Duration(milliseconds: 500),
}) {
  final seq = ++_latestSeq;

  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      action: action,
    ),
  );

  const maxTicks = 120; // absolute lifetime cap (~1 min) - never leak a timer
  final deadlineTicks = (duration + const Duration(milliseconds: 250)).inMilliseconds ~/
      watchdogTick.inMilliseconds;
  var ticks = 0;

  Timer? watchdog;
  watchdog = Timer.periodic(watchdogTick, (timer) {
    ticks++;
    if (ticks > maxTicks) {
      timer.cancel();
      return;
    }
    if (seq != _latestSeq) return;
    if (ticks >= deadlineTicks) {
      messenger.hideCurrentSnackBar();
    }
  });

  unawaited(controller.closed.whenComplete(() => watchdog?.cancel()));

  return controller;
}
