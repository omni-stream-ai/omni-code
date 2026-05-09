import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_code/src/app.dart';

void main() {
  testWidgets('Omni Code home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OmniCodeApp());

    expect(find.byType(Scaffold), findsWidgets);
  });
}
