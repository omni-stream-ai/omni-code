import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';
import 'workspace_agent_test.dart' as fixtures;

void main() {
  for (final (from, to) in [
    ('completed', 'in_progress'),
    ('pending', 'blocked'),
    ('cancelled', 'awaiting_review')
  ]) {
    testWidgets('user can directly change $from to $to and undo',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var status = from;
      final requests = <Map<String, dynamic>>[];
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/undo')) {
          status = from;
          return fixtures.ok({'undone': true});
        }
        if (request.url.path.endsWith('/tasks/actions')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          status = body['status'] as String;
          return fixtures.ok({'action_id': 'status-edit'});
        }
        return fixtures.ok(request.url.path.endsWith('/analyze')
            ? {'running': false}
            : fixtures.snapshot(
                tasks: [fixtures.task('t', status, 'Editable task')]));
      }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client, homeSurface: true)))));
      await tester.pumpAndSettle();
      if (['completed', 'cancelled'].contains(from)) {
        await fixtures.filterHomeTasks(tester, from);
      }
      await tester
          .tap(find.byKey(const ValueKey(('task-actions', 'session-1', 't'))));
      await tester.pumpAndSettle();
      for (final value in [
        'pending',
        'in_progress',
        'awaiting_review',
        'blocked',
        'completed',
        'cancelled'
      ]) {
        expect(
            find.byKey(ValueKey(('set-task-status', value))), findsOneWidget);
      }
      await tester.tap(find.byKey(ValueKey(('set-task-status', to))));
      await tester.pumpAndSettle();
      expect(requests.single['expected_status'], from);
      expect(requests.single['status'], to);
      expect(status, to);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(status, from);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  testWidgets('chat shows a durable undo action for task edits',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var messages = <Map<String, dynamic>>[];
    final edits = <Map<String, dynamic>>[];
    var undone = false;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/chat')) {
        edits.add(jsonDecode(request.body) as Map<String, dynamic>);
        messages = [
          {
            'id': 'reply',
            'role': 'assistant',
            'content': 'Marked 3 tasks as completed.',
            'task_action': {
              'id': 'chat-edit',
              'affected_tasks': 3,
              'status': 'completed',
              'undone': false
            }
          }
        ];
        return fixtures.ok(messages);
      }
      if (request.url.path.endsWith('/tasks/actions/chat-edit/undo')) {
        undone = true;
        messages.single['task_action']['undone'] = true;
        return fixtures.ok({'undone': true});
      }
      return fixtures.ok(fixtures.snapshot(chat: messages));
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkspaceAgentChat(client: client))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mark all tasks complete');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(edits.single['request_id'], isNotEmpty);
    expect(find.text('Undo task change'), findsOneWidget);
    await tester.tap(find.text('Undo task change'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Task change undone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
