import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';
import 'package:omni_code/src/widgets/workspace_dispatch_panel.dart';
import 'workspace_agent_test.dart' as fixtures;

Map<String, dynamic> returned(String id, String request, String answer) => {
      'id': 'dispatch-return-$id',
      'dispatch_request_id': request,
      'role': 'assistant',
      'content': answer,
    };

void main() {
  testWidgets(
      'home conversation places task progress beneath the corresponding reply',
      (tester) async {
    final messages = [
      {
        'id': 'u1',
        'role': 'user',
        'content': 'Check export',
        'dispatch_request_id': 'r1'
      },
      {
        'id': 'a1',
        'role': 'assistant',
        'content': 'Checking export.',
        'dispatch_request_id': 'r1'
      },
      {
        'id': 'u2',
        'role': 'user',
        'content': 'Check search',
        'dispatch_request_id': 'r2'
      },
      {
        'id': 'a2',
        'role': 'assistant',
        'content': 'Checking search.',
        'dispatch_request_id': 'r2'
      },
    ];
    final client = BridgeClient(
        httpClient: MockClient((_) async => fixtures.ok({
              ...fixtures.snapshot(chat: messages),
              'dispatch_tasks': [
                {
                  'id': 't1',
                  'request_id': 'r1',
                  'title': 'Inspect CSV',
                  'status': 'running',
                  'project_id': 'p',
                  'session_id': 's1'
                },
                {
                  'id': 't2',
                  'request_id': 'r2',
                  'title': 'Inspect index',
                  'status': 'running',
                  'project_id': 'p',
                  'session_id': 's2'
                },
              ],
            })));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(client: client, inline: true)))));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('conversation-progress-r1'));
    final second = find.byKey(const ValueKey('conversation-progress-r2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.byType(WorkspaceDispatchPanel), findsNWidgets(3));
    expect(tester.getTopLeft(first).dy,
        greaterThan(tester.getTopLeft(find.text('Checking export.')).dy));
    expect(tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(find.text('Check search')).dy));
    await tester.ensureVisible(first);
    await tester
        .tap(find.descendant(of: first, matching: find.text('Working')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: first, matching: find.text('Inspect CSV')),
        findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('Inspect index')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('progress belongs to its reply and shares conversation polling',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reads = 0;
    var status = 'running';
    final messages = <Map<String, dynamic>>[
      {
        'id': 'u1',
        'role': 'user',
        'content': 'Explain export',
        'dispatch_request_id': 'r1'
      },
      {
        'id': 'a1',
        'role': 'assistant',
        'content': 'I will check export.',
        'dispatch_request_id': 'r1'
      },
      {
        'id': 'u2',
        'role': 'user',
        'content': 'Explain search',
        'dispatch_request_id': 'r2'
      },
      {
        'id': 'a2',
        'role': 'assistant',
        'content': 'I will check search.',
        'dispatch_request_id': 'r2'
      },
    ];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, endsWith('/dispatch/t1/control'));
        status = 'paused';
        return fixtures.ok({});
      }
      if (request.url.path.endsWith('/workspace-agent')) reads++;
      return fixtures.ok({
        ...fixtures.snapshot(chat: messages),
        'dispatch_tasks': [
          {
            'id': 't1',
            'request_id': 'r1',
            'title': 'Inspect CSV',
            'status': status,
            'project_id': 'p',
            'session_id': 's'
          },
          {
            'id': 't2',
            'request_id': 'r2',
            'title': 'Inspect index',
            'status': 'running',
            'project_id': 'p',
            'session_id': 's2'
          },
        ]
      });
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkspaceAgentChat(client: client))));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('conversation-progress-r1'));
    final second = find.byKey(const ValueKey('conversation-progress-r2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy,
        greaterThan(tester.getTopLeft(find.text('I will check export.')).dy));
    expect(tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(find.text('Explain search')).dy));
    expect(find.text('Inspect CSV'), findsNothing);
    final before = reads;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(reads - before, 1,
        reason: 'one shared poll, not a poll for each reply');
    await tester
        .tap(find.descendant(of: first, matching: find.text('Working')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: first, matching: find.text('Inspect CSV')),
        findsOneWidget);
    expect(find.text('Inspect index'), findsNothing);
    await tester.tap(find.descendant(of: first, matching: find.text('Pause')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: first, matching: find.text('Resume')),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    messages.add(returned('r1-final', 'r1', 'Export is UTF-8.'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Re: Explain export'), findsOneWidget);
    expect(find.text('Export is UTF-8.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft');
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'main answer appears in the open conversation without disturbing the next draft',
      (tester) async {
    var messages = <Map<String, dynamic>>[
      {
        'id': 'scheduled',
        'role': 'assistant',
        'content': 'Scheduled the export task.'
      }
    ];
    var posts = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') posts++;
      return fixtures.ok(fixtures.snapshot(chat: messages));
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkspaceAgentChat(client: client))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Another request I am drafting');
    messages = [
      ...messages,
      returned(
          'one', 'request-1', 'The export uses UTF-8 CSV with three columns.')
    ];
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('The export uses UTF-8 CSV with three columns.'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Another request I am drafting');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(posts, 0,
        reason: 'receiving the answer must not resubmit the user request');
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('a stale conversation poll cannot overwrite a new request reply',
      (tester) async {
    final old = <Map<String, dynamic>>[
      {'id': 'old', 'role': 'assistant', 'content': 'Earlier reply'}
    ];
    var messages = old;
    var hold = false;
    final delayed = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/chat') && request.method == 'POST') {
        messages = [
          ...messages,
          {
            'id': 'new',
            'role': 'assistant',
            'content': 'The new request was accepted.'
          }
        ];
        return fixtures.ok(messages);
      }
      if (hold && request.url.path.endsWith('/workspace-agent')) {
        return delayed.future;
      }
      return fixtures.ok(fixtures.snapshot(chat: messages));
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkspaceAgentChat(client: client))));
    await tester.pumpAndSettle();
    hold = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.enterText(find.byType(TextField), 'New work');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The new request was accepted.'), findsOneWidget);
    hold = false;
    delayed.complete(fixtures.ok(fixtures.snapshot(chat: old)));
    await tester.pumpAndSettle();
    expect(find.text('The new request was accepted.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'home shows the latest full main answer for each request without opening a child',
      (tester) async {
    final answer = 'The export uses UTF-8 CSV with three columns. NaN';
    final messages = <Map<String, dynamic>>[
      {
        'id': 'u1',
        'role': 'user',
        'content': 'Explain export',
        'dispatch_request_id': 'r1'
      },
      returned('first-part', 'r1', 'An earlier partial answer.'),
      returned('second-request', 'r2', 'Search uses an index.'),
      returned('final', 'r1', answer),
    ];
    final client = BridgeClient(
        httpClient: MockClient((_) async => fixtures
            .ok({...fixtures.snapshot(chat: messages), 'dispatch_tasks': []})));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceDispatchPanel(
                    client: client, showReturnedAnswers: true)))));
    await tester.pumpAndSettle();
    expect(find.text(answer), findsOneWidget);
    expect(find.text('Explain export'), findsOneWidget);
    expect(find.text('Search uses an index.'), findsOneWidget);
    expect(find.text('An earlier partial answer.'), findsNothing);
    expect(
        tester
            .widget<SelectableText>(find.byWidgetPredicate(
                (widget) => widget is SelectableText && widget.data == answer))
            .maxLines,
        5);
    await tester.tap(find.text('Read full reply').first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SelectableText>(find.byWidgetPredicate(
                (widget) => widget is SelectableText && widget.data == answer))
            .maxLines,
        isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
