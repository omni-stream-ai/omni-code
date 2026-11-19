import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/widgets/app_snack_bar.dart';

void main() {
  for (final withAction in [false, true]) {
    testWidgets('success closes automatically (action: $withAction)',
        (tester) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(MaterialApp(
          scaffoldMessengerKey: messenger,
          home: const Scaffold(body: SizedBox())));
      messenger.currentState!.showSnackBar(AppSnackBar(
          content: const Text('Saved'),
          action: withAction
              ? SnackBarAction(label: 'Undo', onPressed: () {})
              : null));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(Duration(seconds: withAction ? 7 : 3));
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsNothing);
    });
  }

  testWidgets('error close button dismisses without waiting for timeout',
      (tester) async {
    final messenger = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: messenger,
        home: const Scaffold(body: SizedBox())));
    messenger.currentState!.showSnackBar(AppSnackBar(
        isError: true,
        content: const Text('Failed'),
        action: SnackBarAction(label: 'Copy', onPressed: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsNothing);
  });
}
