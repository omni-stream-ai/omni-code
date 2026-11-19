import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/workspace_agent_composer.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

import 'workspace_agent_test.dart' as fixtures;

class _Conversation {
  Map<String, dynamic>? selection;
  String agent = 'pi';
  final chat = <Map<String, dynamic>>[];
}

class _Server {
  final conversations = <String, _Conversation>{};
  final memories = <Map<String, dynamic>>[
    {
      'id': 'preference',
      'content': 'Prefer concise Chinese replies.',
      'project_id': null
    }
  ];
  final headers = <Map<String, String>>[];
  _Conversation conversation(String id) =>
      conversations.putIfAbsent(id, _Conversation.new);

  Future<http.Response> call(http.Request request) async {
    if (request.url.path == '/settings') {
      return fixtures.ok({'model_providers': []});
    }
    headers.add(Map.of(request.headers));
    final id = request.headers['X-Omni-Code-Conversation-Id']!;
    final current = conversation(id);
    if (request.url.path.endsWith('/conversations')) {
      return fixtures.ok([
        for (final entry in conversations.entries)
          if (entry.value.chat.isNotEmpty)
            {
              'id': entry.key,
              'title': entry.value.chat.first['content'],
              'preview': entry.value.chat.last['content'],
              'updated_at': '2026-11-16T12:00:00Z',
            }
      ]);
    }
    if (request.url.path.endsWith('/memories/preference') &&
        request.method == 'DELETE') {
      memories.clear();
      return fixtures.ok({'deleted': true});
    }
    if (request.url.path.endsWith('/memories')) return fixtures.ok(memories);
    if (request.url.path.endsWith('/model')) {
      if (request.method == 'PUT') {
        current.selection =
            jsonDecode(request.body)['selection'] as Map<String, dynamic>?;
      }
      return fixtures.ok({'selection': current.selection});
    }
    if (request.url.path.endsWith('/dispatch/settings')) {
      if (request.method == 'PUT') {
        current.agent = jsonDecode(request.body)['agent'] as String;
      }
      return fixtures.ok({'agent': current.agent});
    }
    if (request.url.path.endsWith('/chat')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      current.chat.addAll([
        {
          'id': '${current.chat.length}-user',
          'role': 'user',
          'content': body['message']
        },
        {
          'id': '${current.chat.length}-assistant',
          'role': 'assistant',
          'content': 'Original conversation reply'
        },
      ]);
      return fixtures.ok(current.chat);
    }
    return fixtures.ok({
      ...fixtures.snapshot(chat: current.chat),
      'conversation': {
        'id': id,
        'title': current.chat.firstOrNull?['content'] ?? ''
      },
      'dispatch_tasks': [
        {
          'id': 'shared-task',
          'request_id': 'previous-request',
          'conversation_id': conversations.keys.first,
          'session_id': 'worker-session',
          'project_id': 'project',
          'title': 'Continue earlier work',
          'status': 'running',
          'summary': 'Verifying the existing implementation',
          'agent': 'pi',
          'dependencies': [],
          'created_at': '2026-11-16T09:00:00Z',
          'updated_at': '2026-11-16T12:00:00Z',
        }
      ],
    });
  }
}

void main() {
  testWidgets(
      'selecting history from the home entry opens the existing conversation page',
      (tester) async {
    final server = _Server();
    final client = BridgeClient(httpClient: MockClient(server.call));
    final original = client.workspaceConversationId;
    server.conversation(original)
      ..selection = {'provider_id': 'service-a', 'model': 'model-a'}
      ..agent = 'codex'
      ..chat.addAll([
        {'id': 'u', 'role': 'user', 'content': 'Original request'},
        {'id': 'a', 'role': 'assistant', 'content': 'An existing answer'}
      ]);
    client.startWorkspaceConversation();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client, homeSurface: true, homeDashboard: true)))));
    await tester.pumpAndSettle();
    expect(find.text('An existing answer'), findsNothing);
    await tester.tap(find.byKey(const Key('main-agent-conversation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversation history'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('main-agent-history-$original')));
    await tester.pumpAndSettle();
    expect(client.workspaceConversationId, original);
    expect(
        find.byKey(const Key('main-agent-conversation-page')), findsOneWidget);
    expect(find.text('An existing answer'), findsOneWidget);
    expect(find.textContaining('model-a'), findsOneWidget);
    expect(server.conversation(original).chat, hasLength(2));
    await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
    await tester.pumpAndSettle();
    expect(find.text('An existing answer'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  test(
      'two applications with the same authenticated client ID start distinct conversations',
      () async {
    final server = _Server();
    final a = BridgeClient(httpClient: MockClient(server.call));
    final b = BridgeClient(httpClient: MockClient(server.call));
    try {
      final first = a.workspaceConversationId;
      expect(first, isNot(b.workspaceConversationId));
      await a.workspaceAgentRequest();
      await a.workspaceAgentRequest(action: '/model');
      await b.workspaceAgentRequest();
      expect(server.headers[0]['X-Omni-Code-Client-Id'],
          server.headers[2]['X-Omni-Code-Client-Id']);
      expect(server.headers[0]['X-Omni-Code-Conversation-Id'], first);
      expect(server.headers[1]['X-Omni-Code-Conversation-Id'], first);
      expect(server.headers[2]['X-Omni-Code-Conversation-Id'],
          b.workspaceConversationId);
      a.startWorkspaceConversation();
      expect(a.workspaceConversationId, isNot(first));
      a.openWorkspaceConversation(first);
      expect(a.workspaceConversationId, first);
    } finally {
      a.dispose();
      b.dispose();
    }
  });

  test(
      'responses from a previous main conversation cannot enter the newly selected one',
      () async {
    final pending = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((_) => pending.future));
    try {
      final request = client.workspaceAgentRequest(
          action: '/chat', method: 'POST', body: {'message': 'Old request'});
      client.startWorkspaceConversation();
      pending.complete(fixtures.ok([
        {'role': 'assistant', 'content': 'Old answer'}
      ]));
      await expectLater(request, throwsA(isA<StateError>()));
    } finally {
      client.dispose();
    }
  });

  testWidgets(
      'new conversation keeps task progress and history restores context settings and drafts',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server();
    final client = BridgeClient(httpClient: MockClient(server.call));
    final original = client.workspaceConversationId;
    server.conversation(original)
      ..selection = {'provider_id': 'service-a', 'model': 'model-a'}
      ..agent = 'codex';
    final composer = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(
                    client: client,
                    composerController: composer,
                    inline: true)))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Original request');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(find.text('Original conversation reply'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Keep my draft');
    await tester.tap(find.byKey(const Key('main-agent-new-conversation')));
    await tester.pumpAndSettle();
    expect(client.workspaceConversationId, isNot(original));
    expect(find.text('Original conversation reply'), findsNothing);
    expect(composer.text.text, isEmpty);
    expect(composer.selection, isNull);
    expect(composer.taskAgent, 'pi');
    expect(find.text('Continue earlier work'), findsOneWidget);
    expect(find.text('Verifying the existing implementation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('main-agent-conversation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversation history'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('main-agent-history-$original')));
    await tester.pumpAndSettle();
    expect(client.workspaceConversationId, original);
    expect(find.text('Original conversation reply'), findsOneWidget);
    expect(composer.text.text, 'Keep my draft');
    expect(
        composer.selection, {'provider_id': 'service-a', 'model': 'model-a'});
    expect(composer.taskAgent, 'codex');
    await tester.tap(find.byKey(const Key('main-agent-conversation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long-term memory'));
    await tester.pumpAndSettle();
    expect(find.text('Prefer concise Chinese replies.'), findsOneWidget);
    await tester.tap(find.byTooltip('Forget'));
    await tester.pumpAndSettle();
    expect(find.text('No memories yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-agent-new-conversation')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey(('main-agent-task-actions', 'shared-task'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open originating conversation'));
    await tester.pumpAndSettle();
    expect(client.workspaceConversationId, original);
    expect(find.text('Original conversation reply'), findsOneWidget);
    expect(composer.text.text, 'Keep my draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    composer.dispose();
    client.dispose();
  });
}
