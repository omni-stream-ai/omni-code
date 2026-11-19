import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/workspace_agent_composer.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

http.Response ok(Object? data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json'});
final projects = [
  for (final id in ['alpha', 'beta'])
    ProjectSummary(
        id: id,
        name: 'Project $id',
        rootPath: '/$id',
        updatedAt: DateTime(2026),
        sessionCount: 0)
];
final input = find.byKey(const Key('home-assistant-input'));
final suggestions = find.byKey(const Key('assistant-composer-suggestions'));
Finder option(String value) =>
    find.byKey(ValueKey(('assistant-completion', value)));

BridgeClient client({Future<http.Response> Function(http.Request)? handler}) =>
    BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/settings') return ok({'model_providers': []});
      if (request.url.path.endsWith('/model')) return ok({'selection': null});
      if (request.url.path.endsWith('/dispatch/settings')) {
        return ok({'agent': 'codex'});
      }
      if (handler != null) return handler(request);
      if (request.url.path == '/agents/commands') {
        return ok([
          {
            'kind': 'codex',
            'commands': [
              {'name': r'$review', 'description': 'Review the implementation'},
              {
                'name': r'$refactor',
                'description': 'Refactor the implementation'
              },
            ]
          },
          {
            'kind': 'pi',
            'commands': [
              {'name': '/compact'}
            ]
          },
        ]);
      }
      if (request.url.path == '/files/completions') {
        return ok([
          {'path': 'lib/my file.dart', 'is_dir': false},
          {'path': 'lib/next.dart', 'is_dir': false},
        ]);
      }
      return ok([]);
    }));

Widget app(WorkspaceAgentComposerController draft,
        {VoidCallback? onSend,
        VoidCallback? onConversationOpened,
        String? projectId,
        TransitionBuilder? builder}) =>
    MaterialApp(
        builder: builder,
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: WorkspaceAgentComposer(
                        controller: draft,
                        home: true,
                        prominent: true,
                        projects: projects,
                        projectId: projectId,
                        onConversationOpened: onConversationOpened,
                        onSend: onSend ?? () {})))));

void main() {
  testWidgets('IME composition does not accept suggestions or send prematurely',
      (tester) async {
    final bridge = client();
    final draft = WorkspaceAgentComposerController(bridge);
    var sends = 0;
    await tester.pumpWidget(app(draft, onSend: () => sends++));
    await tester.pumpAndSettle();
    await tester.enterText(input, '/new');
    draft.text.value = const TextEditingValue(
        text: '/new',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4));
    await tester.pumpAndSettle();
    expect(suggestions, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 0);
    expect(draft.text.text, '/new');
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  testWidgets('mobile reference menus fit large text and a visible keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);
    final bridge = client();
    final draft = WorkspaceAgentComposerController(bridge);
    await tester.pumpWidget(app(draft,
        projectId: 'alpha',
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.6),
                viewInsets: const EdgeInsets.only(bottom: 260)),
            child: child!)));
    await tester.pumpAndSettle();
    await tester.enterText(input, '@lib');
    await tester.pumpAndSettle();
    expect(suggestions, findsOneWidget);
    await tester.tap(option('lib/my file.dart'));
    await tester.pumpAndSettle();
    expect(draft.references.single.value, 'lib/my file.dart');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  for (final width in [360.0, 1100.0]) {
    testWidgets(
        'slash completions overlay the editor and accept keys at $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.reset);
      final bridge = client();
      final draft = WorkspaceAgentComposerController(bridge);
      var sends = 0;
      await tester.pumpWidget(app(draft, onSend: () => sends++));
      await tester.pumpAndSettle();
      final height = tester.getSize(input).height;
      await tester.enterText(input, '/');
      await tester.pumpAndSettle();
      expect(suggestions, findsOneWidget);
      expect(option('/new'), findsOneWidget);
      expect(tester.getSize(input).height, height);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(draft.text.text, '/history ');
      expect(sends, 0);
      expect(suggestions, findsNothing);
      await tester.enterText(input, '/ne');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(suggestions, findsNothing);
      expect(draft.text.text, '/ne');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
      bridge.dispose();
    });
  }

  testWidgets('assistant slash commands run locally instead of sending chat',
      (tester) async {
    final bridge = client(
        handler: (request) async =>
            ok(request.url.path.endsWith('/conversations')
                ? [
                    {
                      'id': 'previous',
                      'title': 'Previous conversation',
                      'updated_at': '2026-11-16T10:00:00Z'
                    }
                  ]
                : []));
    final draft = WorkspaceAgentComposerController(bridge);
    var sends = 0, opened = 0;
    await tester.pumpWidget(app(draft,
        onSend: () => sends++, onConversationOpened: () => opened++));
    await tester.pumpAndSettle();
    final original = bridge.workspaceConversationId;
    await tester.enterText(input, '/new ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(bridge.workspaceConversationId, isNot(original));
    expect(draft.text.text, isEmpty);
    await tester.enterText(input, '/history ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous conversation'));
    await tester.pumpAndSettle();
    expect(bridge.workspaceConversationId, 'previous');
    expect(opened, 1);
    await tester.enterText(input, '/memory ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(find.text('Long-term memory'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.enterText(input, '/model ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-provider-option-auto')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-provider-option-auto')));
    await tester.pumpAndSettle();
    await tester.enterText(input, '/help ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(find.text('Assistant commands'), findsOneWidget);
    expect(sends, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  testWidgets('file references select a project and preserve the caret suffix',
      (tester) async {
    final bridge = client();
    final draft = WorkspaceAgentComposerController(bridge);
    await tester.pumpWidget(app(draft));
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Read @li and keep the suffix');
    draft.text.selection = const TextSelection.collapsed(offset: 8);
    await tester.pumpAndSettle();
    expect(option('Project beta'), findsOneWidget);
    await tester.tap(option('Project beta'));
    await tester.pumpAndSettle();
    expect(option('lib/my file.dart'), findsOneWidget);
    await tester.tap(option('lib/my file.dart'));
    await tester.pumpAndSettle();
    expect(draft.text.text, 'Read @"lib/my file.dart" and keep the suffix');
    expect(draft.references.single.toJson(),
        {'kind': 'file', 'project_id': 'beta', 'path': 'lib/my file.dart'});
    final conversation = bridge.workspaceConversationId;
    bridge.startWorkspaceConversation();
    await tester.pumpAndSettle();
    expect(draft.references, isEmpty);
    bridge.openWorkspaceConversation(conversation);
    await tester.pumpAndSettle();
    expect(draft.references.single.projectId, 'beta');
    draft.text.text = 'Read @"lib/my file.dart.other"';
    expect(draft.references, isEmpty);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  testWidgets(
      'skills use the chosen execution agent and Enter accepts before sending',
      (tester) async {
    final bridge = client();
    final draft = WorkspaceAgentComposerController(bridge);
    var sends = 0;
    await tester
        .pumpWidget(app(draft, projectId: 'alpha', onSend: () => sends++));
    await tester.pumpAndSettle();
    await tester.enterText(input, r'$re');
    await tester.pumpAndSettle();
    expect(option(r'$review'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(draft.text.text, r'$refactor ');
    expect(draft.references.single.toJson(),
        {'kind': 'skill', 'project_id': 'alpha', 'name': 'refactor'});
    expect(sends, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sends, 1);
    draft.setTaskAgent('pi');
    await tester.enterText(input, r'$re');
    await tester.pumpAndSettle();
    expect(option(r'$review'), findsNothing);
    expect(draft.references, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  testWidgets('old file suggestions cannot enter a new conversation',
      (tester) async {
    final pending = Completer<http.Response>();
    var reads = 0;
    final bridge = client(handler: (request) async {
      if (request.url.path == '/files/completions') {
        reads++;
        return pending.future;
      }
      return ok([]);
    });
    final draft = WorkspaceAgentComposerController(bridge);
    await tester.pumpWidget(app(draft, projectId: 'alpha'));
    await tester.pumpAndSettle();
    await tester.enterText(input, '@lib');
    await tester.pump(const Duration(milliseconds: 200));
    expect(reads, 1);
    bridge.startWorkspaceConversation();
    pending.complete(ok([
      {'path': 'lib/old.dart', 'is_dir': false}
    ]));
    await tester.pumpAndSettle();
    expect(suggestions, findsNothing);
    expect(draft.references, isEmpty);
    expect(draft.text.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    bridge.dispose();
  });

  testWidgets('selected references are included in assistant chat requests',
      (tester) async {
    Map<String, dynamic>? sent;
    final bridge = client(handler: (request) async {
      if (request.url.path.endsWith('/chat')) {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return ok([
          {'id': 'reply', 'role': 'assistant', 'content': 'I read the file.'}
        ]);
      }
      if (request.url.path == '/files/completions') {
        return ok([
          {'path': 'lib/main.dart', 'is_dir': false}
        ]);
      }
      return ok({'scope': {}, 'tasks': [], 'chat': [], 'running': false});
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkspaceAgentChat(
            client: bridge,
            projectId: 'alpha',
            projects: projects,
            fullPage: true)));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('agent-chat-input'));
    await tester.enterText(field, 'Explain @lib');
    await tester.pumpAndSettle();
    await tester.tap(option('lib/main.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-chat-send')));
    await tester.pumpAndSettle();
    expect(sent?['message'], 'Explain @lib/main.dart');
    expect(sent?['references'], [
      {'kind': 'file', 'project_id': 'alpha', 'path': 'lib/main.dart'}
    ]);
    expect(find.text('I read the file.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    bridge.dispose();
  });
}
