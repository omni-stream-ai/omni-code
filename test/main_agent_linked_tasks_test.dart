import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

import 'workspace_agent_test.dart' as fixtures;

Map<String, dynamic> execution(String id, {String status = 'running'}) => {
      'id': id,
      'request_id': 'request-$id',
      'session_id': 'session-$id',
      'project_id': 'project',
      'title': 'Execute task $id',
      'status': status,
      'summary': 'Latest progress for $id',
      'agent': 'pi',
      'dependencies': [],
      'created_at': '2026-11-16T0$id:00:00Z',
      'updated_at': '2026-11-16T09:00:00Z',
    };

Finder taskMenu(String id) =>
    find.byKey(ValueKey(('main-agent-task-actions', id)));
Finder pinnedTasks() => find.byKey(const Key('home-main-agent-linked-tasks'));

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  for (final surface in ['home', 'inline', 'page']) {
    testWidgets('disabled analysis opens linked conversations from $surface',
        (tester) async {
      appSettingsController.debugReplaceSettings(
          AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1000);
      addTearDown(tester.view.reset);
      var analyses = 0;
      String? route;
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path == '/v2/sessions/session-2') {
          return http.Response(
              jsonEncode({
                'session': {
                  'id': 'session-2',
                  'project_id': 'project',
                  'title': 'Execution conversation',
                  'agent': 'pi',
                  'status': 'running',
                  'updated_at': '2026-11-16T09:00:00Z',
                  'unread_count': 0,
                }
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path.endsWith('/analyze')) analyses++;
        return fixtures.ok({
          ...fixtures.snapshot(chat: [
            {
              'id': 'reply',
              'role': 'assistant',
              'content': 'Continue in the linked conversation.',
              'dispatch_request_id': 'request-2',
            }
          ]),
          'dispatch_tasks': [
            execution('1'),
            execution('2'),
            {...execution('3', status: 'queued'), 'session_id': null},
            {
              ...execution('4'),
              'session_id': 'session-2',
              'request_id': 'request-2',
            },
          ],
        });
      }));
      client.syncSessionSummary((await client.getSession('session-2')).session);
      final Widget content = surface == 'home'
          ? WorkspaceAgentPanel(
              client: client, homeSurface: true, homeDashboard: true)
          : WorkspaceAgentChat(
              client: client,
              inline: surface == 'inline',
              fullPage: surface == 'page');
      await tester.pumpWidget(MaterialApp(
          home: surface == 'page'
              ? content
              : Scaffold(body: SingleChildScrollView(child: content)),
          onGenerateRoute: (settings) {
            route = settings.name;
            return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Execution destination')));
          }));
      await tester.pumpAndSettle();
      final links = surface == 'page'
          ? find.byKey(const ValueKey('conversation-progress-request-2'))
          : find.byKey(const Key('home-main-agent-linked-sessions'));
      expect(
          find.descendant(
              of: links, matching: find.text('Linked conversations')),
          findsOneWidget);
      expect(
          find.descendant(
              of: links, matching: find.text('Execution conversation')),
          findsOneWidget);
      expect(taskMenu('1'), findsNothing);
      expect(taskMenu('2'), findsNothing);
      expect(find.text('Linked tasks'), findsNothing);
      expect(find.byKey(const Key('home-agent-tasks')), findsNothing);
      final conversation = find.descendant(
          of: links,
          matching: find.byKey(
              const ValueKey(('assistant-linked-session', 'session-2'))));
      expect(conversation, findsOneWidget);
      expect(find.text('Execute task 3'), findsNothing);
      await tester.ensureVisible(conversation);
      await tester.tap(conversation);
      await tester.pumpAndSettle();
      expect(route, AppRoutes.session('project', 'session-2'));
      expect(find.text('Execution destination'), findsOneWidget);
      expect(analyses, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  testWidgets(
      'compact home entry opens details before the model replies and sends exactly once',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final pending = Completer<http.Response>();
    final sent = <Map<String, dynamic>>[];
    final projects = <String?>[];
    var chat = <Map<String, dynamic>>[
      {
        'id': 'previous',
        'role': 'assistant',
        'content': 'A previous answer belongs in conversation details.'
      }
    ];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/settings') {
        return fixtures.ok({'model_providers': []});
      }
      if (request.url.path.endsWith('/model')) {
        return fixtures.ok({
          'selection': {'provider_id': 'service', 'model': 'chosen-model'}
        });
      }
      if (request.url.path.endsWith('/dispatch/settings')) {
        return fixtures.ok({'agent': 'codex'});
      }
      if (request.url.path.endsWith('/chat')) {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        projects.add(request.url.queryParameters['project_id']);
        return pending.future;
      }
      return fixtures.ok({
        ...fixtures.snapshot(chat: chat),
        'dispatch_tasks': [execution('1'), execution('2'), execution('3')]
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client,
                    projectId: 'task-filter-project',
                    homeSurface: true,
                    homeDashboard: true)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-agent-messages')), findsNothing);
    expect(find.text('A previous answer belongs in conversation details.'),
        findsNothing);
    expect(find.text('Execute task 1'), findsNothing);
    expect(find.text('Execute task 2'), findsOneWidget);
    expect(find.text('Execute task 3'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const Key('home-main-agent-conversation')))
            .height,
        lessThan(400));
    await tester.enterText(find.byKey(const Key('home-assistant-input')),
        'Implement the dashboard');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        find.byKey(const Key('main-agent-conversation-page')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Thinking…'), findsOneWidget);
    expect(sent, hasLength(1));
    expect(projects.single, isNull);
    expect(sent.single['configuration'], {
      'selection': {'provider_id': 'service', 'model': 'chosen-model'},
      'agent': 'codex'
    });
    chat = [
      {'id': 'user', 'role': 'user', 'content': 'Implement the dashboard'},
      {'id': 'reply', 'role': 'assistant', 'content': 'The work is scheduled.'},
    ];
    pending.complete(fixtures.ok(chat));
    await tester.pumpAndSettle();
    expect(find.text('The work is scheduled.'), findsOneWidget);
    expect(sent, hasLength(1));
    await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
    await tester.pumpAndSettle();
    expect(find.text('The work is scheduled.'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        isEmpty);
    expect(find.text('Execute task 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'main conversation pins the two newest executions and shares live progress polling',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.reset);
    var reads = 0;
    var progress = 'Verifying the requested result';
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/workspace-agent')) reads++;
      return fixtures.ok({
        ...fixtures.snapshot(
            chat: List.generate(
                18,
                (i) => {
                      'id': 'message-$i',
                      'role': i.isEven ? 'user' : 'assistant',
                      'content':
                          'Conversation message $i about the work in progress.',
                    })),
        'dispatch_tasks': [
          execution('1'),
          execution('2', status: 'paused'),
          {...execution('3', status: 'awaiting_review'), 'summary': progress},
        ],
      });
    }));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(client: client, inline: true)))));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: pinnedTasks(), matching: find.text('Execute task 3')),
        findsOneWidget);
    expect(
        find.descendant(
            of: pinnedTasks(), matching: find.text('Execute task 2')),
        findsOneWidget);
    expect(find.text('Execute task 1'), findsNothing);
    expect(find.byKey(const Key('home-recent-tracking')), findsNothing);
    expect(find.text('Verifying the requested result'), findsOneWidget);
    final pinnedPosition = tester.getTopLeft(pinnedTasks());
    final composer = find.byKey(const Key('home-agent-composer-surface'));
    final composerPosition = tester.getTopLeft(composer);
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const Key('home-agent-messages')))
        .controller!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pinnedTasks()), pinnedPosition);
    expect(tester.getTopLeft(composer), composerPosition);
    await tester.enterText(find.byKey(const Key('home-assistant-input')),
        'Keep this next request');
    progress = 'Verification returned the final result';
    final before = reads;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(reads - before, 1);
    expect(find.text(progress), findsOneWidget);
    expect(scroll.offset, 0);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        'Keep this next request');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'main execution menu pauses resumes cancels and opens the correct conversation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.reset);
    var status = 'running';
    final actions = <String>[];
    final paused = Completer<void>();
    String? route;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/control')) {
        expect(request.url.path, endsWith('/dispatch/2/control'));
        final action = jsonDecode(request.body)['action'] as String;
        actions.add(action);
        if (action == 'pause') await paused.future;
        status = switch (action) {
          'pause' => 'paused',
          'resume' => 'running',
          _ => 'cancelled'
        };
        return fixtures.ok({});
      }
      if (request.url.path == '/v2/sessions/session-2') {
        return http.Response(
            jsonEncode({
              'session': {
                'id': 'session-2',
                'project_id': 'project',
                'title': 'Execution conversation',
                'agent': 'pi',
                'status': 'idle',
                'updated_at': '2026-11-16T09:00:00Z',
                'unread_count': 0,
              }
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      return fixtures.ok({
        ...fixtures.snapshot(),
        'dispatch_tasks': [execution('2', status: status)]
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(client: client, inline: true))),
        onGenerateRoute: (settings) {
          route = settings.name;
          return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Execution destination')));
        }));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Keep this draft');
    Future<void> choose(String label) async {
      await tester.tap(taskMenu('2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }

    await choose('Pause');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester.widget<PopupMenuButton<String>>(taskMenu('2')).enabled, isFalse);
    paused.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: pinnedTasks(), matching: find.text('Paused')),
        findsOneWidget);
    await choose('Resume');
    await tester.pumpAndSettle();
    expect(find.descendant(of: pinnedTasks(), matching: find.text('Running')),
        findsOneWidget);
    await choose('Cancel task');
    await tester.pumpAndSettle();
    expect(find.descendant(of: pinnedTasks(), matching: find.text('Cancelled')),
        findsOneWidget);
    expect(actions, ['pause', 'resume', 'cancel']);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        'Keep this draft');
    await choose('Open execution conversation');
    await tester.pumpAndSettle();
    expect(route, AppRoutes.session('project', 'session-2'));
    expect(find.text('Execution destination'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('failed main execution control retains status and allows retry',
      (tester) async {
    var fail = true;
    var status = 'running';
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/control')) {
        if (fail) return http.Response('Control unavailable', 503);
        status = 'paused';
        return fixtures.ok({});
      }
      return fixtures.ok({
        ...fixtures.snapshot(),
        'dispatch_tasks': [execution('2', status: status)]
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(client: client, inline: true)))));
    await tester.pumpAndSettle();
    for (final shouldFail in [true, false]) {
      fail = shouldFail;
      await tester.tap(taskMenu('2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(status, shouldFail ? 'running' : 'paused');
      expect(tester.widget<PopupMenuButton<String>>(taskMenu('2')).enabled,
          isTrue);
    }
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'pinned execution progress fits mobile keyboards and large text in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 740);
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      final client = BridgeClient(
          httpClient: MockClient((_) async => fixtures.ok({
                ...fixtures.snapshot(),
                'dispatch_tasks': [
                  execution('1'),
                  execution('2', status: 'queued')
                ],
              })));
      await tester.pumpWidget(MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(1.6),
                  viewInsets: const EdgeInsets.only(bottom: 260)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentChat(client: client, inline: true)))));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey(('main-agent-task', '1'))), findsOneWidget);
      expect(
          find.byKey(const ValueKey(('main-agent-task', '2'))), findsOneWidget);
      expect(find.byKey(const Key('home-assistant-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    }
  });
}
