import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/widgets/session_markdown_table.dart';

const document = r'''
| Name | Details | Status | Link |
| :--- | :---: | ---: | --- |
| **First** | A long description with an escaped \| pipe and inline `code` | Ready | [Open][child] |
| Second | | Pending | Last column |

[child]: ./child.md
''';

void main() {
  Future<void> mount(WidgetTester tester,
      {required double width,
      Brightness brightness = Brightness.light,
      void Function(String)? onOpenLink}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:
          ThemeData(brightness: brightness, platform: TargetPlatform.android),
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
            body: TabBarView(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MarkdownBody(
              data: document,
              blockSyntaxes: const [SessionTableSyntax()],
              builders: {
                'session-table': SessionTableBuilder(onOpenLink ?? (_) {})
              },
            ),
          ),
          const Text('Source view')
        ])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('wide table scrolls inside its frame in $brightness',
        (tester) async {
      await mount(tester, width: 360, brightness: brightness);
      expect(tester.takeException(), isNull);
      final horizontal = find.byWidgetPredicate((widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal);
      final scroll =
          tester.widget<SingleChildScrollView>(horizontal).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final frame =
          find.ancestor(of: horizontal, matching: find.byType(Container)).first;
      final bounds = tester.getRect(frame);
      expect(bounds.left, greaterThanOrEqualTo(20));
      expect(bounds.right, lessThanOrEqualTo(340));
      final decoration =
          tester.widget<Container>(frame).decoration! as BoxDecoration;
      expect((decoration.border! as Border).left.width, 1);
      expect((decoration.border! as Border).right.width, 1);
      await tester.drag(horizontal, const Offset(-1400, 0));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(tester.getRect(frame), bounds);
      expect(tester.getRect(find.text('Last column')).right,
          lessThan(bounds.right));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile cards retain all cells, rich text and reference links',
      (tester) async {
    String? opened;
    await mount(tester, width: 360, onOpenLink: (href) => opened = href);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsNothing);
    expect(find.text('Name'), findsNWidgets(2));
    expect(find.text('First'), findsOneWidget);
    expect(find.textContaining('escaped | pipe'), findsOneWidget);
    await tester.ensureVisible(find.text('Open'));
    await tester.tap(find.text('Open'));
    expect(opened, './child.md');
    await tester.ensureVisible(find.text('Last column'));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Table'));
    await tester.tap(find.widgetWithText(TextButton, 'Table'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop table stays within document width', (tester) async {
    await mount(tester, width: 1200);
    expect(find.text('Cards'), findsNothing);
    expect(tester.getRect(find.byType(Table)).right, lessThanOrEqualTo(1180));
    expect(tester.takeException(), isNull);
  });
}
