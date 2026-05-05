import 'package:flutter_test/flutter_test.dart';

import 'package:omni_code/src/app.dart';

void main() {
  testWidgets('Omni Code home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OmniCodeApp());

    expect(find.text('Omni Code'), findsWidgets);
    expect(find.text('活跃会话'), findsOneWidget);
  });
}
