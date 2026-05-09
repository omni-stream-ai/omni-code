import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/widgets/app_back_header.dart';

void main() {
  testWidgets('long title truncates without overflow on narrow widths',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(kToolbarHeight),
            child: SafeArea(
              child: AppBackHeader(
                title:
                    'This is a very long session title that should truncate instead of overflowing the row',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppBackHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
