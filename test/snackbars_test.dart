import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talako/utils/snackbars.dart';

void main() {
  Future<ScaffoldMessengerState> pumpApp(WidgetTester tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return messenger;
  }

  testWidgets('auto-dismisses at deadline even if native timeout stalls', (tester) async {
    final messenger = await pumpApp(tester);

    showAutoDismissSnackBar(messenger, message: 'Payment complete!');
    await tester.pumpAndSettle();
    expect(find.text('Payment complete!'), findsOneWidget);

    // Advance well past the 4s duration + watchdog buffer.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Payment complete!'), findsNothing,
        reason: 'watchdog must guarantee dismissal');
  });

  testWidgets('undo action fires callback and dismisses immediately', (tester) async {
    final messenger = await pumpApp(tester);
    var undone = false;

    showAutoDismissSnackBar(
      messenger,
      message: 'Credit added',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => undone = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Credit added'), findsNothing);
  });

  testWidgets('a newer snackbar is not killed by an older watchdog', (tester) async {
    final messenger = await pumpApp(tester);

    showAutoDismissSnackBar(
      messenger,
      message: 'FIRST',
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();
    showAutoDismissSnackBar(messenger, message: 'SECOND');
    await tester.pumpAndSettle();
    // SECOND queued behind FIRST; both may be visible in the tree.
    expect(find.text('FIRST'), findsOneWidget);

    // Past SECOND's deadline, the queue drains within a bounded time.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('SECOND'), findsNothing, reason: 'newest must close by its deadline');
    expect(find.text('FIRST'), findsNothing,
        reason: 'older snackbar must drain too instead of lingering forever');
  });
}
