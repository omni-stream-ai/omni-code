import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/workspace_agent_models.dart';
import 'package:omni_code/src/widgets/project_avatar.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/screens/home_screen.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';

Map<String, dynamic> task(String id, String status, String title) => {
      'session_id': 'session-1',
      'project_id': 'project-1',
      'session_title': 'Workspace redesign',
      'updated_at': '2026-11-13T10:00:00Z',
      'task': <String, dynamic>{
        'id': id,
        'status': status,
        'title': title,
        'summary': status == 'completed'
            ? 'The layout is implemented and verified.'
            : 'Finish keyboard navigation and review the mobile experience.'
      },
    };
Map<String, dynamic> snapshot(
        {List<Map<String, dynamic>>? tasks,
        List<Map<String, dynamic>> chat = const [],
        Map<String, dynamic>? scope,
        Map<String, dynamic> errors = const {}}) =>
    {
      'scope': scope ??
          {
            'include_other_sessions': true,
            'recent_days': 5,
            'max_sessions': 15
          },
      'tasks': tasks ??
          [
            task('1', 'completed', 'Build the workspace shell'),
            task('2', 'in_progress', 'Polish the conversation experience'),
            task('3', 'blocked', 'Review deployment settings')
          ],
      'selected_sessions': 3,
      'cached_sessions': 3,
      'participated_sessions': 2,
      'external_sessions': 1,
      'running': false,
      'errors': errors,
      'chat': chat,
    };
http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json'});

Future<void> showHomeTasks(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('home-task-status-filter')));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> filterHomeTasks(WidgetTester tester, String status) async {
  final filter = find.byKey(const Key('home-task-status-filter'));
  await tester.ensureVisible(filter);
  await tester.tap(filter);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(('task-status-filter-option', status))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'automatic analysis can stop pending reads and polling then resume live',
      (tester) async {
    appSettingsController.debugReplaceSettings(
        AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
    addTearDown(() =>
        appSettingsController.debugReplaceSettings(AppSettings.defaults()));
    final pending = Completer<http.Response>();
    var analyses = 0;
    var reads = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/analyze')) {
        analyses++;
        if (analyses == 1) return pending.future;
        return ok({'running': false});
      }
      reads++;
      return ok(snapshot());
    }));
    Widget panel({int revision = 0}) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client,
                    sessionId: 'session-1',
                    revision: revision))));
    void enable(bool enabled) => appSettingsController.debugReplaceSettings(
        appSettingsController.settings
            .copyWith(autoTaskAnalysisEnabled: enabled));
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 65));
    expect(analyses, 0);
    expect(reads, 0);
    expect(find.byKey(const Key('session-agent-tasks')), findsNothing);

    enable(true);
    await tester.pump();
    expect(analyses, 1);
    enable(false);
    pending.complete(ok({'running': false}));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.byKey(const Key('session-agent-tasks')), findsNothing);

    enable(true);
    await tester.pumpAndSettle();
    expect(analyses, 2);
    expect(reads, 1);
    expect(find.byKey(const Key('session-agent-tasks')), findsOneWidget);
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();
    expect(analyses, 3);

    enable(false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(panel(revision: 1));
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();
    expect(analyses, 3);
    expect(find.byKey(const Key('session-agent-tasks')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets(
        'home tasks filter every status without reanalysis at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const statuses = [
        'pending',
        'in_progress',
        'awaiting_review',
        'blocked',
        'completed',
        'cancelled'
      ];
      var analyses = 0;
      final tasks = [
        for (final status in statuses)
          {...task(status, status, 'Task $status'), 'session_id': 's-$status'}
      ];
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/analyze')) {
          analyses++;
          return ok({'running': false});
        }
        return ok(snapshot(tasks: tasks));
      }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      textScaler: TextScaler.linear(width == 320 ? 1.6 : 1)),
                  child: SingleChildScrollView(
                      child: WorkspaceAgentPanel(
                          client: client, homeSurface: true))))));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('home-assistant-input')), 'Keep this draft');
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Work progress'), findsNothing);
      expect(find.text('Recently tracked'), findsNothing);
      expect(find.byKey(const Key('home-progress-toggle')), findsNothing);
      expect(find.text('Task completed'), findsNothing);
      expect(find.text('Task cancelled'), findsNothing);
      final initialAnalyses = analyses;
      for (final status in statuses) {
        await filterHomeTasks(tester, status);
        for (final other in statuses) {
          expect(find.text('Task $other'),
              status == other ? findsOneWidget : findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
      await filterHomeTasks(tester, 'all');
      for (final status in statuses) {
        expect(find.text('Task $status'), findsOneWidget);
      }
      await filterHomeTasks(tester, 'open');
      expect(find.text('Task completed'), findsNothing);
      expect(find.text('Task cancelled'), findsNothing);
      expect(analyses, initialAnalyses);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('home-assistant-input')))
              .controller!
              .text,
          'Keep this draft');
      final settings = find.byTooltip('Analysis range');
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.text('Focus on relevant conversations'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  testWidgets('status filters select matching children from mixed task groups',
      (tester) async {
    final tasks = [
      task('review', 'awaiting_review', 'Review this child'),
      task('blocked', 'blocked', 'Blocked child'),
      task('done', 'completed', 'Completed child'),
    ];
    for (final item in tasks) {
      item['task']['group'] = {
        'id': 'release',
        'title': 'Release work',
        'summary': 'Review the delivery'
      };
    }
    final client = BridgeClient(
        httpClient: MockClient((request) async => ok(
            request.url.path.endsWith('/analyze')
                ? {'running': false}
                : snapshot(tasks: tasks))));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    expect(find.text('Release work'), findsOneWidget);
    await filterHomeTasks(tester, 'awaiting_review');
    expect(find.text('Review this child'), findsOneWidget);
    expect(find.text('Release work'), findsNothing);
    expect(find.text('Blocked child'), findsNothing);
    expect(find.text('Completed child'), findsNothing);
    await filterHomeTasks(tester, 'completed');
    expect(find.text('Completed child'), findsOneWidget);
    expect(find.text('Review this child'), findsNothing);
    await filterHomeTasks(tester, 'all');
    expect(find.text('Release work'), findsOneWidget);
    expect(find.text('3 subtasks'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  test('old Bridge routes report an actionable compatibility error', () async {
    final client = BridgeClient(
        httpClient: MockClient((_) async => http.Response('', 404)));
    try {
      await expectLater(client.workspaceAgentRequest(),
          throwsA(isA<WorkspaceAgentIncompatibleException>()));
    } finally {
      client.dispose();
    }
  });

  test('a missing workspace resource is not reported as an old Bridge',
      () async {
    final client = BridgeClient(
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'error': 'Task not found'}), 404)));
    try {
      await expectLater(
          client.workspaceAgentRequest(action: '/chat/missing/apply'),
          throwsA(predicate((error) =>
              error is! WorkspaceAgentIncompatibleException &&
              error.toString().contains('Task not found'))));
    } finally {
      client.dispose();
    }
  });

  test('workspace requests discard responses from a previous bridge', () async {
    final previous = appSettingsController.settings;
    final pending = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((_) => pending.future));
    try {
      final request = client.workspaceAgentRequest();
      appSettingsController.debugReplaceSettings(
          previous.copyWith(bridgeUrl: 'http://different-workspace:9999'));
      pending.complete(ok(snapshot()));
      await expectLater(
          request,
          throwsA(predicate(
              (error) => error.toString().contains('connection_changed'))));
    } finally {
      client.dispose();
      appSettingsController.debugReplaceSettings(previous);
    }
  });
  testWidgets(
      'home opens conversation details and preserves failed requests across navigation',
      (tester) async {
    final sent = <String>[];
    final requestIds = <String>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/chat')) {
        expect(request.url.queryParameters['project_id'], 'project-1');
        final message = jsonDecode(request.body)['message'] as String;
        sent.add(message);
        requestIds.add(jsonDecode(request.body)['request_id'] as String);
        if (sent.length == 1) return http.Response('Temporary failure', 503);
        return ok([
          {
            'id': 'answer',
            'role': 'assistant',
            'content': 'Start with the conversation experience.'
          }
        ]);
      }
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot());
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client,
                    projectId: 'project-1',
                    homeSurface: true)))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-assistant-send')))
            .onPressed,
        isNull);
    await tester.enterText(find.byKey(const Key('home-assistant-input')),
        'What should I do next?');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('home-assistant-send')));
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(sent, ['What should I do next?']);
    final chat = find.byType(WorkspaceAgentChat);
    expect(chat, findsOneWidget);
    expect(
        find.byKey(const Key('main-agent-conversation-page')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final input = find.descendant(of: chat, matching: find.byType(TextField));
    expect(tester.widget<TextField>(input).controller!.text,
        'What should I do next?');
    await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        'What should I do next?');
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(sent, ['What should I do next?', 'What should I do next?']);
    expect(requestIds[1], requestIds[0]);
    expect(
        find.text('Start with the conversation experience.'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'home keeps a compact entry and opens conversation history on demand',
      (tester) async {
    final client = BridgeClient(
        httpClient: MockClient((r) async => ok(r.url.path.endsWith('/analyze')
            ? {'running': false}
            : snapshot(chat: [
                {
                  'id': 'u',
                  'role': 'user',
                  'content': 'Build the next release'
                },
                {
                  'id': 'a',
                  'role': 'assistant',
                  'content': 'Two tasks are in progress.'
                },
              ]))));
    for (var visit = 0; visit < 2; visit++) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client, homeSurface: true)))));
      await tester.pumpAndSettle();
      expect(find.text('Two tasks are in progress.'), findsNothing);
      expect(
          tester
              .getSize(find.byKey(const Key('home-main-agent-conversation')))
              .height,
          lessThan(300));
      expect(find.byKey(const Key('home-agent-tasks')), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.byKey(const Key('home-task-status-filter')), findsOneWidget);
      expect(find.byKey(const Key('home-progress-toggle')), findsNothing);
      expect(find.text('Work progress'), findsNothing);
      expect(find.text('Recently tracked'), findsNothing);
      expect(find.text('Build the next release'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('home-agent-messages')), findsNothing);
      expect(find.byKey(const Key('home-agent-expand')), findsNothing);
      expect(find.byKey(const Key('home-agent-preview')), findsNothing);
      await tester.tap(find.byKey(const Key('home-agent-open-conversation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main-agent-conversation-page')),
          findsOneWidget);
      expect(find.text('Build the next release'), findsOneWidget);
      expect(find.text('Two tasks are in progress.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
      await tester.pumpAndSettle();
      expect(find.text('Two tasks are in progress.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    client.dispose();
  });

  testWidgets(
      'home keeps the composer visible while reading history and receiving updates',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 900);
      var messages = List.generate(
          24,
          (index) => <String, dynamic>{
                'id': 'message-$index',
                'role': index.isEven ? 'user' : 'assistant',
                'content':
                    'Message $index: keep the project work moving and review the next step.',
              });
      final client = BridgeClient(
          httpClient: MockClient((_) async => ok(snapshot(chat: messages))));
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentChat(client: client, inline: true)))));
      await tester.pumpAndSettle();
      final messageList = find.byKey(const Key('home-agent-messages'));
      final list = tester.widget<SingleChildScrollView>(messageList);
      final scroll = list.controller!;
      expect(scroll.position.extentAfter, lessThan(2));
      final composer = find.byKey(const Key('home-agent-composer-surface'));
      final composerPosition = tester.getTopLeft(composer);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Message 0: keep the project work moving and review the next step.'),
          findsOneWidget);
      expect(
          find.byKey(const Key('home-agent-jump-to-latest')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('home-assistant-input')), 'Continue my draft');
      final readingOffset = scroll.offset;
      messages = [
        ...messages,
        {'id': 'new', 'role': 'assistant', 'content': 'A new result is ready.'}
      ];
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(scroll.offset, readingOffset);
      expect(tester.getTopLeft(composer), composerPosition);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('home-assistant-input')))
              .controller!
              .text,
          'Continue my draft');
      await tester.tap(find.byKey(const Key('home-agent-jump-to-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(2));
      expect(find.text('A new result is ready.'), findsOneWidget);
      expect(find.byKey(const Key('home-agent-jump-to-latest')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    }
  });

  testWidgets(
      'compact home entry and conversation details fit mobile keyboards and large text in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = const Size(390, 740);
      final client = BridgeClient(
          httpClient: MockClient(
              (request) async => ok(request.url.path.endsWith('/chat')
                  ? [
                      {
                        'id': 'reply',
                        'role': 'assistant',
                        'content': 'Here is the current progress.'
                      }
                    ]
                  : snapshot(chat: []))));
      await tester.pumpWidget(MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(1.5),
                  viewInsets: const EdgeInsets.only(bottom: 260)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client,
                      homeSurface: true,
                      homeDashboard: true,
                      showRecentTracking: false)))));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('home-assistant-input'));
      expect(field, findsOneWidget);
      expect(Theme.of(tester.element(field)).brightness, brightness);
      await tester.enterText(field, 'Review recent progress');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text,
          'Review recent progress');
      await tester.ensureVisible(find.byKey(const Key('home-assistant-send')));
      await tester.tap(find.byKey(const Key('home-assistant-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main-agent-conversation-page')),
          findsOneWidget);
      expect(find.byKey(const Key('agent-chat-input')), findsOneWidget);
      expect(find.text('Here is the current progress.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    }
  });

  testWidgets('home shows unfinished tasks and opens the source conversation',
      (tester) async {
    String? route;
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path == '/v2/sessions/session-1') {
        return http.Response(
            jsonEncode({
              'session': {
                'id': 'session-1',
                'project_id': 'project-1',
                'title': 'Workspace redesign',
                'agent': 'codex',
                'status': 'idle',
                'updated_at': '2026-11-13T10:00:00Z',
                'unread_count': 0
              }
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      return ok(
          r.url.path.endsWith('/analyze') ? {'running': false} : snapshot());
    }));
    client.debugSeedSessions([
      SessionSummary.fromJson({
        'id': 'session-1',
        'project_id': 'project-1',
        'title': 'Codex session',
        'agent': 'codex',
        'status': 'idle',
        'updated_at': '2026-11-13T10:00:00Z',
        'unread_count': 0
      })
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client))),
        onGenerateRoute: (settings) {
          route = settings.name;
          return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Conversation destination')));
        }));
    await tester.pumpAndSettle();
    expect(client.peekSessionById('session-1')?.title, 'Workspace redesign');
    expect(find.text('Build the workspace shell'), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    await tester.tap(find.text('Polish the conversation experience'));
    await tester.pumpAndSettle();
    expect(route, contains('session-1'));
    expect(find.text('Conversation destination'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets('merged task body opens the most recently updated conversation',
      (tester) async {
    String? route;
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path == '/v2/sessions/session-1') {
        return http.Response(
            jsonEncode({
              'session': {
                'id': 'session-1',
                'project_id': 'project-1',
                'title': 'Workspace redesign',
                'agent': 'codex',
                'status': 'idle',
                'updated_at': '2026-11-13T10:00:00Z',
                'unread_count': 0
              }
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      return ok(r.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(
              tasks: [
              {
                ...task('older', 'awaiting_review', 'Older child'),
                'session_id': 'session-older',
                'updated_at': '2026-11-12T10:00:00Z'
              },
              {
                ...task('newer', 'awaiting_review', 'Newer child'),
                'updated_at': '2026-11-13T10:00:00Z'
              },
            ].map((item) {
              (item['task'] as Map)['group'] = {
                'id': 'g',
                'title': 'Merged navigation',
                'summary': 'Ready'
              };
              return item;
            }).toList()));
    }));
    client.debugSeedSessions([
      SessionSummary.fromJson({
        'id': 'session-1',
        'project_id': 'project-1',
        'title': 'Codex session',
        'agent': 'codex',
        'status': 'idle',
        'updated_at': '2026-11-13T10:00:00Z',
        'unread_count': 0
      })
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client))),
        onGenerateRoute: (settings) {
          route = settings.name;
          return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Conversation destination')));
        }));
    await tester.pumpAndSettle();
    expect(client.peekSessionById('session-1')?.title, 'Workspace redesign');
    expect(find.text('Build the workspace shell'), findsNothing);
    expect(find.text('Merged navigation'), findsOneWidget);
    await tester.tap(find.text('Merged navigation'));
    await tester.pumpAndSettle();
    expect(route, contains('session-1'));
    expect(find.text('Conversation destination'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'automatic checks reuse cache and manual refresh always forces analysis',
      (tester) async {
    final requests = <Uri>[];
    var running = false;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/analyze')) {
        requests.add(request.url);
        return ok({'running': true});
      }
      return ok({...snapshot(), 'running': running});
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client, projectId: 'project-1')))));
    await tester.pumpAndSettle();
    expect(requests.single.queryParameters['project_id'], 'project-1');
    expect(requests.single.queryParameters['request_id'], isNotEmpty);
    expect(requests.single.queryParameters.containsKey('force'), false);
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last.queryParameters.containsKey('force'), false);
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['project_id'], 'project-1');
    expect(requests.last.queryParameters['force'], 'true');

    // A manual request is still accepted while a background analysis runs.
    running = true;
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    await tester.pump();
    final count = requests.length;
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pump();
    await tester.pump();
    expect(requests.length, count + 1);
    expect(requests.last.queryParameters['force'], 'true');
    // Polling an active run only reads its status.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(requests.length, count + 1);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'broken connections retain tasks and retry manual analysis with one request ID',
      (tester) async {
    var failures = 0;
    final attempts = <Uri>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/analyze')) {
        attempts.add(request.url);
        if (failures > 0) {
          failures--;
          throw http.ClientException('Broken pipe', request.url);
        }
        return ok({'running': false});
      }
      return ok(snapshot());
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client)))));
    await tester.pumpAndSettle();
    failures = 2;
    attempts.clear();
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    expect(find.text('Connection interrupted. Reconnecting…'), findsOneWidget);
    expect(find.text('Some tasks could not be updated'), findsNothing);
    expect(find.textContaining('Broken pipe'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(attempts.length, 3);
    expect(
        attempts.map((u) => u.queryParameters['request_id']).toSet().length, 1);
    expect(attempts.every((u) => u.queryParameters['force'] == 'true'), true);
    expect(find.text('Connection interrupted. Reconnecting…'), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'persistent connection failures show friendly text and recover automatically',
      (tester) async {
    var unavailable = true;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (unavailable) return http.Response('upstream unavailable', 503);
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot());
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client)))));
    await tester.pumpAndSettle();
    expect(find.text('No open tasks in the current range'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Bridge is temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('upstream unavailable'), findsNothing);
    unavailable = false;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Bridge is temporarily unavailable'), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'a failed snapshot retries reading without resubmitting accepted analysis',
      (tester) async {
    var posts = 0;
    var reads = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        return ok({'running': false});
      }
      if (reads++ == 0) throw http.ClientException('Connection reset');
      return ok(snapshot());
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client)))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(reads, 2);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'changing project cancels pending retry and does not transfer a forced request',
      (tester) async {
    final attempts = <Uri>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/analyze')) {
        attempts.add(request.url);
        if (request.url.queryParameters['force'] == 'true') {
          throw http.ClientException('Broken pipe');
        }
        return ok({'running': false});
      }
      return ok(snapshot());
    }));
    Widget page(String projectId) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(
                    client: client, projectId: projectId))));
    await tester.pumpWidget(page('project-1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('project-2'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(attempts.length, 3);
    expect(attempts.last.queryParameters['project_id'], 'project-2');
    expect(attempts.last.queryParameters.containsKey('force'), false);
    expect(find.text('Connection interrupted. Reconnecting…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets('authorization failures are not retried as connection failures',
      (tester) async {
    var calls = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      calls++;
      return http.Response('Unauthorized', 401);
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client)))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Connection interrupted. Reconnecting…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'task sentence and metadata fit desktop, narrow and large text layouts',
      (tester) async {
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final blocked = task('image', 'blocked', 'Generate the image');
    blocked['truncated'] = true;
    blocked['task'].addAll({
      'summary': 'Request returned HTTP 404; verify model name and access.',
      'created_at':
          now.subtract(const Duration(hours: 2, minutes: 12)).toIso8601String(),
      'updated_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      // Legacy phase information must not become another description or expansion.
      'progress': {'done': 'Request attempted'},
    });
    final legacy = task('legacy', 'pending', 'Review previous work');
    final data = snapshot(tasks: [blocked, legacy]);
    data['projects'] = [
      {'id': 'project-1', 'name': 'Image studio'}
    ];
    final client = BridgeClient(
        httpClient: MockClient((request) async => ok(
            request.url.path.endsWith('/analyze')
                ? {'running': false}
                : data)));
    for (final layout in [(1000.0, 1.0), (320.0, 1.0), (320.0, 1.6)]) {
      tester.view.physicalSize = Size(layout.$1, 1400);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.$2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client, homeSurface: true)))));
      await tester.pumpAndSettle();
      await showHomeTasks(tester);

      expect(
          find.text('Request returned HTTP 404; verify model name and access.'),
          findsNothing);
      await tester.tap(find.text('Generate the image'));
      await tester.pumpAndSettle();
      expect(
          find.text('Request returned HTTP 404; verify model name and access.'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('home-agent-tasks')),
              matching: find.text('Image studio')),
          findsNWidgets(2));
      expect(find.text('Elapsed 2 hr 12 min'), findsOneWidget);
      expect(find.text('5 min ago'), findsOneWidget);
      expect(find.text('Updated 5 min ago'), findsNothing);
      expect(find.byTooltip('Based on a recent excerpt'), findsNothing);
      expect(find.textContaining('Conversation '), findsOneWidget);
      expect(find.text('Request attempted'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    client.dispose();
  });

  test(
      'tasks sort by their own latest update with stable ties and legacy fallback',
      () {
    final oldest = task('oldest', 'pending', 'Oldest task');
    oldest['task']['updated_at'] = '2026-11-01T12:00:00Z';
    final latest = task('latest', 'in_progress', 'Latest task');
    latest['updated_at'] = '2026-11-01T12:00:00Z';
    latest['task']['updated_at'] = '2026-11-13T11:00:00Z';
    final tieZ = task('z', 'blocked', 'First tie');
    tieZ['task']['updated_at'] = '2026-11-13T09:00:00Z';
    final tieA = task('a', 'pending', 'Second tie');
    tieA['task']['updated_at'] = '2026-11-13T09:00:00Z';
    tieA['archived'] = true;
    final legacy = task('legacy', 'pending', 'Legacy task');
    final missing = task('missing', 'pending', 'Missing dates')
      ..remove('updated_at');
    final result = WorkspaceAgentSnapshot.fromJson(
        snapshot(tasks: [oldest, missing, tieZ, latest, tieA, legacy]));
    expect(result.tasks.map((task) => task.id),
        ['latest', 'legacy', 'z', 'a', 'oldest', 'missing']);
    expect(result.tasks.first.lastUpdatedAt, DateTime.utc(2026, 11, 13, 11));
    expect(result.tasks.last.lastUpdatedAt, isNull);
  });

  testWidgets(
      'recent tasks come first and the centered footer has a full width tap target',
      (tester) async {
    addTearDown(tester.view.reset);
    final tasks = List.generate(8, (index) {
      final item = task(index.toString(), 'pending', 'Task $index');
      item['task']['updated_at'] =
          DateTime.utc(2026, 11, 13, index).toIso8601String();
      return item;
    });
    final client = BridgeClient(
        httpClient: MockClient((request) async => ok(
            request.url.path.endsWith('/analyze')
                ? {'running': false}
                : snapshot(tasks: tasks))));
    for (final home in [true, false]) {
      for (final width in [320.0, 1000.0]) {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: WorkspaceAgentPanel(
                        client: client,
                        homeSurface: home,
                        sessionId: home ? null : 'session-1')))));
        await tester.pumpAndSettle();
        if (home) await showHomeTasks(tester);

        final shown = home ? 6 : 5;
        for (var index = 7; index > 8 - shown; index--) {
          expect(tester.getTopLeft(find.text('Task $index')).dy,
              lessThan(tester.getTopLeft(find.text('Task ${index - 1}')).dy));
        }
        expect(find.text('Task 0'), findsNothing);
        final toggle = find.byKey(const Key('task-list-toggle'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        final button = tester.getRect(toggle);
        expect(button.height, greaterThanOrEqualTo(48));
        expect(
            button.width,
            closeTo(
                tester
                        .getSize(find.byKey(ValueKey(
                            home ? 'home-agent-tasks' : 'session-agent-tasks')))
                        .width -
                    (home ? 0 : 34),
                1));
        expect(
            button.center.dx,
            closeTo(
                tester
                    .getCenter(find.byKey(ValueKey(
                        home ? 'home-agent-tasks' : 'session-agent-tasks')))
                    .dx,
                1));
        expect(find.text('Show all tasks'), findsOneWidget);
        await tester.tapAt(button.centerLeft + const Offset(8, 0));
        await tester.pumpAndSettle();
        expect(find.text('Task 0'), findsOneWidget);
        expect(find.text('Show less'), findsOneWidget);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester
            .tapAt(tester.getRect(toggle).centerRight - const Offset(8, 0));
        await tester.pumpAndSettle();
        expect(find.text('Task 0'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    client.dispose();
  });

  testWidgets('acceptance moves tasks into history and undo restores review',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var status = 'awaiting_review';
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/undo')) {
        status = 'awaiting_review';
        return ok({'undone': true});
      }
      if (request.url.path.endsWith('/tasks/actions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        status = body['status'] as String;
        return ok({'action_id': 'accept-action'});
      }
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(tasks: [task('image', status, 'Generate the image')]));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    expect(find.text('Awaiting review'), findsOneWidget);
    final menu =
        find.byKey(const ValueKey(('task-actions', 'session-1', 'image')));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Archive task'), findsNothing);
    await tester.tap(find.text('Accept task'));
    await tester.pumpAndSettle();
    expect(requests.single['expected_status'], 'awaiting_review');
    expect(requests.single['status'], 'completed');
    expect(requests.single['tasks'], [
      {'session_id': 'session-1', 'task_id': 'image'}
    ]);
    expect(find.text('Generate the image'), findsNothing);
    await filterHomeTasks(tester, 'completed');
    expect(find.text('Generate the image'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(status, 'awaiting_review');
    expect(find.text('Generate the image'), findsNothing);
    await filterHomeTasks(tester, 'open');
    expect(find.text('Awaiting review'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('blocked tasks can be completed and undo restores blocked',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var status = 'blocked';
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/undo')) {
        status = 'blocked';
        return ok({'undone': true});
      }
      if (request.url.path.endsWith('/tasks/actions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        status = body['status'] as String;
        return ok({'action_id': 'accept-action'});
      }
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(tasks: [task('image', status, 'Generate the image')]));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    expect(find.text('Blocked'), findsOneWidget);
    final menu =
        find.byKey(const ValueKey(('task-actions', 'session-1', 'image')));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Archive task'), findsNothing);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();
    expect(requests.single['expected_status'], 'blocked');
    expect(requests.single['status'], 'completed');
    expect(requests.single['tasks'], [
      {'session_id': 'session-1', 'task_id': 'image'}
    ]);
    expect(find.text('Generate the image'), findsNothing);
    await filterHomeTasks(tester, 'completed');
    expect(find.text('Generate the image'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(status, 'blocked');
    expect(find.text('Generate the image'), findsNothing);
    await filterHomeTasks(tester, 'open');
    expect(find.text('Blocked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('failed cancellation retains tasks and enables retry',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/tasks/actions')) return pending.future;
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(tasks: [task('image', 'blocked', 'Generate the image')]));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    final menu =
        find.byKey(const ValueKey(('task-actions', 'session-1', 'image')));
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Accept task'), findsNothing);
    await tester.tap(find.text('Cancel task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<PopupMenuButton<String>>(menu).enabled, isFalse);
    expect(find.text('Generate the image'), findsOneWidget);
    pending.complete(http.Response('Unable to save', 500));
    await tester.pumpAndSettle();
    expect(find.text('Generate the image'), findsOneWidget);
    expect(tester.widget<PopupMenuButton<String>>(menu).enabled, isTrue);
    expect(find.text('Could not update tasks. Refresh and retry.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'related tasks filter by status and batch actions only touch that status',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = [
      task('root', 'in_progress', 'Current work'),
      task('review-1', 'awaiting_review', 'First review'),
      task('review-2', 'awaiting_review', 'Second review'),
      task('blocked', 'blocked', 'Needs access'),
      task('done', 'completed', 'Already complete')
    ];
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/tasks/actions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        for (final target in body['tasks'] as List) {
          tasks.firstWhere(
                  (task) => task['task']['id'] == target['task_id'])['task']
              ['status'] = body['status'];
        }
        return ok({'action_id': 'batch-action'});
      }
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(tasks: tasks));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    await tester.tap(
        find.byKey(const ValueKey(('related-tasks', 'session-1', 'root'))));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('related-task-panel'));
    expect(find.descendant(of: panel, matching: find.text('First review')),
        findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Needs access')),
        findsNothing);
    await tester.tap(find.byKey(const Key('accept-related-tasks')));
    await tester.pumpAndSettle();
    expect(requests.single['expected_status'], 'awaiting_review');
    expect((requests.single['tasks'] as List).map((task) => task['task_id']),
        ['review-1', 'review-2']);
    expect(tasks[0]['task']['status'], 'in_progress');
    expect(tasks[3]['task']['status'], 'blocked');
    expect(tasks[4]['task']['status'], 'completed');
    await tester.tap(find.byKey(const ValueKey(('related-status', 'blocked'))));
    await tester.pumpAndSettle();
    expect(find.text('Complete this status'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-related-tasks')));
    await tester.pumpAndSettle();
    expect(requests.last['expected_status'], 'blocked');
    expect(requests.last['tasks'], [
      {'session_id': 'session-1', 'task_id': 'blocked'}
    ]);
    expect(tasks[0]['task']['status'], 'in_progress');
    expect(tasks[3]['task']['status'], 'cancelled');
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('blocked bulk completion only touches the selected status',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = [
      task('root', 'in_progress', 'Current work'),
      task('review-1', 'awaiting_review', 'First review'),
      task('review-2', 'awaiting_review', 'Second review'),
      task('blocked', 'blocked', 'Needs access'),
      task('done', 'completed', 'Already complete')
    ];
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/tasks/actions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        for (final target in body['tasks'] as List) {
          tasks.firstWhere(
                  (task) => task['task']['id'] == target['task_id'])['task']
              ['status'] = body['status'];
        }
        return ok({'action_id': 'batch-action'});
      }
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(tasks: tasks));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    await tester.tap(
        find.byKey(const ValueKey(('related-tasks', 'session-1', 'root'))));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('related-task-panel'));
    expect(find.descendant(of: panel, matching: find.text('First review')),
        findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Needs access')),
        findsNothing);
    await tester.tap(find.byKey(const Key('accept-related-tasks')));
    await tester.pumpAndSettle();
    expect(requests.single['expected_status'], 'awaiting_review');
    expect((requests.single['tasks'] as List).map((task) => task['task_id']),
        ['review-1', 'review-2']);
    expect(tasks[0]['task']['status'], 'in_progress');
    expect(tasks[3]['task']['status'], 'blocked');
    expect(tasks[4]['task']['status'], 'completed');
    await tester.tap(find.byKey(const ValueKey(('related-status', 'blocked'))));
    await tester.pumpAndSettle();
    expect(find.text('Complete this status'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-related-tasks')));
    await tester.pumpAndSettle();
    expect(requests.last['expected_status'], 'blocked');
    expect(requests.last['tasks'], [
      {'session_id': 'session-1', 'task_id': 'blocked'}
    ]);
    expect(tasks[0]['task']['status'], 'in_progress');
    expect(tasks[3]['task']['status'], 'completed');
    expect(requests.last['status'], 'completed');
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  for (final action in ['Complete group', 'Cancel group']) {
    testWidgets('merged menu supports $action atomically and undo',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tasks = [
        task('first', 'awaiting_review', 'First child'),
        task('second', 'blocked', 'Second child'),
        task('third', 'completed', 'Finished child'),
      ];
      for (final item in tasks) {
        item['task']['group'] = {
          'id': 'workspace',
          'title': 'Merged work',
          'summary': 'Ready'
        };
      }
      final requests = <Map<String, dynamic>>[];
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/undo')) {
          tasks[0]['task']['status'] = 'awaiting_review';
          tasks[1]['task']['status'] = 'blocked';
          tasks[2]['task']['status'] = 'completed';
          return ok({'undone': true});
        }
        if (request.url.path.endsWith('/tasks/actions')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          for (final target in body['tasks'] as List) {
            tasks.firstWhere(
                    (item) => item['task']['id'] == target['task_id'])['task']
                ['status'] = body['status'];
          }
          return ok({'action_id': 'group-action'});
        }
        return ok(request.url.path.endsWith('/analyze')
            ? {'running': false}
            : snapshot(tasks: tasks));
      }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client, homeSurface: true)))));
      await tester.pumpAndSettle();
      await showHomeTasks(tester);

      final menu = find.byWidgetPredicate((widget) =>
          widget is PopupMenuButton<String> &&
          widget.key.toString().contains('group-actions'));
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      final targets = requests.single['tasks'] as List;
      expect(targets.length, action == 'Cancel group' ? 3 : 2);
      expect(targets.map((target) => target['task_id']),
          containsAll(['first', 'second']));
      expect(
          targets.firstWhere(
              (target) => target['task_id'] == 'first')['expected_status'],
          'awaiting_review');
      expect(
          targets.firstWhere(
              (target) => target['task_id'] == 'second')['expected_status'],
          'blocked');
      expect(tasks[0]['task']['status'],
          action == 'Complete group' ? 'completed' : 'cancelled');
      expect(tasks[1]['task']['status'], tasks[0]['task']['status']);
      expect(tasks[2]['task']['status'],
          action == 'Cancel group' ? 'cancelled' : 'completed');
      expect(find.text('Merged work'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Merged work'), findsOneWidget);
      expect(tasks[0]['task']['status'], 'awaiting_review');
      expect(tasks[1]['task']['status'], 'blocked');
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  for (final width in [320.0, 1000.0]) {
    testWidgets(
        'merged tasks retain original children and accept individual tasks at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tasks = [
        task('first', 'awaiting_review', 'First original task'),
        task('second', 'awaiting_review', 'Second original task'),
        task('third', 'blocked', 'Third original task')
      ];
      for (final task in tasks) {
        task['task']['group'] = {
          'id': 'workspace',
          'title': 'Improve the workspace',
          'summary': 'Delivered changes are ready for review.'
        };
      }
      final requests = <Map<String, dynamic>>[];
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/tasks/actions')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          for (final target in body['tasks'] as List) {
            tasks.firstWhere(
                    (task) => task['task']['id'] == target['task_id'])['task']
                ['status'] = body['status'];
          }
          return ok({'action_id': 'child-action'});
        }
        return ok(request.url.path.endsWith('/analyze')
            ? {'running': false}
            : snapshot(tasks: tasks));
      }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
                      client: client, homeSurface: true)))));
      await tester.pumpAndSettle();
      await showHomeTasks(tester);

      expect(find.text('Improve the workspace'), findsOneWidget);
      expect(find.text('First original task'), findsNothing);
      await tester.tap(find.text('3 subtasks'));
      await tester.pumpAndSettle();
      expect(find.text('First original task'), findsOneWidget);
      expect(find.text('Second original task'), findsOneWidget);
      expect(find.text('Third original task'), findsNothing);
      final accept = find
          .byKey(const ValueKey(('accept-related-task', 'session-1', 'first')));
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(requests.single['tasks'], [
        {'session_id': 'session-1', 'task_id': 'first'}
      ]);
      expect(tasks[1]['task']['status'], 'awaiting_review');
      expect(tasks[2]['task']['status'], 'blocked');
      expect(find.text('Improve the workspace'), findsOneWidget);
      expect(find.text('First original task'), findsNothing);
      expect(find.text('Second original task'), findsOneWidget);
      await filterHomeTasks(tester, 'completed');
      expect(find.text('First original task'), findsOneWidget);
      expect(find.text('Second original task'), findsNothing);
      expect(find.text('Improve the workspace'), findsNothing);
      expect(find.text('Completed'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  testWidgets(
      'home analysis ends on the next snapshot and idle polling stays silent',
      (tester) async {
    var running = true;
    var holdRead = false;
    var posts = 0;
    final pending = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        return ok({'running': running});
      }
      if (holdRead) return pending.future;
      return ok({...snapshot(), 'running': running});
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await showHomeTasks(tester);

    expect(find.text('Organizing tasks'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    running = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(posts, 1);
    expect(find.text('Organizing tasks'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    holdRead = true;
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(posts, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    pending.complete(ok(snapshot()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('a failed status read stops animating an old running snapshot',
      (tester) async {
    var running = true;
    var failRead = false;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') return ok({'running': running});
      if (failRead) return http.Response('Status request failed', 400);
      return ok({...snapshot(), 'running': running});
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await showHomeTasks(tester);

    expect(find.text('Organizing tasks'), findsOneWidget);
    failRead = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Organizing tasks'), findsNothing);
    expect(find.text('Updates pending'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    failRead = false;
    running = false;
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Updates pending'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('home task details keep metadata and errors out of the task list',
      (tester) async {
    var unavailable = false;
    var partialError = false;
    const evidenceError = 'Task response refers to unavailable evidence';
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (unavailable) throw http.ClientException('Broken pipe');
      return ok(request.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(
              errors: partialError ? {'session-1': evidenceError} : const {}));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    await showHomeTasks(tester);

    expect(find.text('All app conversations'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Task details'));
    await tester.tap(find.byTooltip('Task details'));
    await tester.pumpAndSettle();
    expect(find.text('All app conversations'), findsOneWidget);
    expect(
        find.text('Included: 2 app conversations · 1 external conversations'),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    unavailable = true;
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bridge is temporarily unavailable'), findsNothing);
    await tester.tap(find.byTooltip('Task details'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bridge is temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('Broken pipe'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    unavailable = false;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bridge is temporarily unavailable'), findsNothing);
    partialError = true;
    await tester.ensureVisible(find.byTooltip('Refresh tasks'));
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    expect(find.text(evidenceError), findsNothing);
    expect(find.text('Some tasks could not be updated'), findsNothing);
    expect(find.text('Polish the conversation experience'), findsOneWidget);
    await tester.tap(find.byTooltip('Task details'));
    await tester.pumpAndSettle();
    expect(find.text(evidenceError), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets('scope validates bounds and persists all three controls',
      (tester) async {
    Map<String, dynamic>? saved;
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.method == 'PUT') saved = jsonDecode(r.body) as Map<String, dynamic>;
      return ok(r.url.path.endsWith('/analyze')
          ? {'running': false}
          : snapshot(scope: saved ?? {'recent_days': 5, 'max_sessions': 15}));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentPanel(client: client)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Analysis range'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.tap(find.text('Save and refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 1 to 365'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byType(TextFormField).at(0), '7');
    await tester.enterText(find.byType(TextFormField).at(1), '12');
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Save and refresh'));
    await tester.pumpAndSettle();
    expect(saved,
        {'include_other_sessions': true, 'recent_days': 7, 'max_sessions': 12});
    expect(find.text('External: last 7 days · Up to 12 conversations'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Analysis range'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Save and refresh'));
    await tester.pumpAndSettle();
    expect(saved, {
      'include_other_sessions': false,
      'recent_days': 7,
      'max_sessions': 12
    });
    expect(find.text('All app conversations'), findsOneWidget);
    expect(find.text('External conversations excluded'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'conversation sidebar displays completed and unfinished tasks at narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = BridgeClient(
        httpClient: MockClient((r) async => ok(r.url.path.endsWith('/analyze')
            ? {'running': false}
            : snapshot())));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 304,
                    child: WorkspaceAgentPanel(
                        client: client,
                        projectId: 'project-1',
                        sessionId: 'session-1'))))));
    await tester.pumpAndSettle();
    expect(find.text('Build the workspace shell'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Blocked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets(
      'assistant retains failed input and applies the exact server proposal',
      (tester) async {
    var failed = true;
    var applied = false;
    var saved = false;
    var sent = '';
    final chat = [
      {
        'id': 'reply-1',
        'role': 'assistant',
        'content': 'I can update the analysis range.',
        'proposal': {
          'analysis_scope': {
            'recent_days': 7,
            'max_sessions': 12,
            'include_other_sessions': false
          }
        },
        'applied': false
      }
    ];
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path.endsWith('/apply')) {
        applied = true;
        chat[0]['applied'] = true;
        return ok({'applied': true});
      }
      if (r.method == 'POST') {
        sent = (jsonDecode(r.body) as Map)['message'] as String;
        if (failed) return http.Response('Model unavailable', 503);
        saved = true;
        return ok(chat);
      }
      return ok(snapshot(chat: saved || applied ? chat : []));
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkspaceAgentChat(client: client))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Change to seven days');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Change to seven days'), findsOneWidget);
    expect(sent, 'Change to seven days');
    failed = false;
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Settings change preview'), findsOneWidget);
    expect(applied, false);
    await tester.tap(find.text('Apply change'));
    await tester.pumpAndSettle();
    expect(applied, true);
    expect(find.text('Applied'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  testWidgets('render task dashboard in dark and light themes', (tester) async {
    await tester.runAsync(() async {
      for (final family in ['Ahem', 'Roboto', 'Arial']) {
        final loader = FontLoader(family);
        for (final path in [
          'designs/assets/fonts/Roboto-Regular.ttf',
          'designs/assets/fonts/Roboto-Bold.ttf'
        ]) {
          loader.addFont(Future.value(
              ByteData.sublistView(await File(path).readAsBytes())));
        }
        await loader.load();
      }
      final root = Platform.environment['FLUTTER_ROOT'] ??
          '/home/junjie/Flutter/flutter';
      final icons = File(
          '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(await icons.readAsBytes()))))
            .load();
      }
    });
    tester.view.physicalSize = const Size(1100, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = BridgeClient(
        httpClient: MockClient((r) async => ok(r.url.path.endsWith('/analyze')
            ? {'running': false}
            : snapshot())));
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final key = GlobalKey();
      final baseTheme = brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme;
      final theme = baseTheme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
              style: baseTheme.filledButtonTheme.style?.copyWith(
                  textStyle: WidgetStatePropertyAll(baseTheme
                      .textTheme.labelLarge!
                      .copyWith(fontFamily: 'Roboto')))));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                      color: theme.scaffoldBackgroundColor,
                      child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('OMNI / WORKSPACE',
                                    style: TextStyle(
                                        fontSize: 12, letterSpacing: 3)),
                                const SizedBox(height: 28),
                                WorkspaceAgentPanel(client: client)
                              ])))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final name = brightness.name;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../.cache/workspace-agent/dashboard-$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
    client.dispose();
  });
  testWidgets('workspace tasks integrate into desktop and mobile home layouts',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final artwork =
        'data:image/svg+xml;base64,${base64Encode(File('assets/app-icon.svg').readAsBytesSync())}';
    var withConversation = false;
    final client = BridgeClient(httpClient: MockClient((request) async {
      switch (request.url.path) {
        case '/projects':
          return ok([
            {
              'id': 'project-1',
              'name': 'Omni Code',
              'icon_data_uri': artwork,
              'root_path': '/workspace/omni-code',
              'updated_at': '2026-11-13T10:00:00Z',
              'session_count': 2
            }
          ]);
        case '/v2/sessions':
          return ok([
            {
              'id': 'session-1',
              'project_id': 'project-1',
              'title': 'Workspace redesign',
              'agent': 'codex',
              'status': 'idle',
              'updated_at': '2026-11-13T10:00:00Z',
              'unread_count': 0,
              'last_message_preview':
                  'Review keyboard navigation and the mobile layout.'
            }
          ]);
        case '/workspace-agent':
          return ok({
            ...snapshot(
                chat: withConversation
                    ? [
                        {
                          'id': 'request',
                          'role': 'user',
                          'content': 'Give the workspace a calmer home.'
                        },
                        {
                          'id': 'answer',
                          'role': 'assistant',
                          'content':
                              'The conversation now stays here. I’m bringing tasks and their progress into one place. Two items still need attention before we finish.'
                        },
                      ]
                    : []),
            'projects': [
              {'id': 'project-1', 'name': 'Omni Code', 'icon_data_uri': artwork}
            ],
            'dispatch_tasks': withConversation
                ? [
                    {
                      'id': 'conversation-layout',
                      'request_id': 'request',
                      'title': 'Refine conversation layout',
                      'status': 'running',
                      'project_id': 'project-1',
                      'session_id': 'session-1',
                      'created_at': '2026-11-16T09:00:00Z',
                      'summary':
                          'Checking message scrolling and the fixed composer.',
                    },
                    {
                      'id': 'mobile-check',
                      'request_id': 'request',
                      'title': 'Check mobile interactions',
                      'status': 'queued',
                      'project_id': 'project-1',
                      'session_id': 'session-2',
                      'created_at': '2026-11-16T09:01:00Z',
                      'dependencies': ['conversation-layout'],
                    },
                  ]
                : [],
          });
        case '/workspace-agent/analyze':
          return ok({'running': false});
        default:
          return ok([]);
      }
    }));
    for (final layout in [
      (1400.0, false),
      (390.0, false),
      (1400.0, true),
      (390.0, true)
    ]) {
      final width = layout.$1;
      withConversation = layout.$2;
      tester.view.physicalSize = Size(width, width > 500 ? 1000 : 844);
      final key = GlobalKey();
      final baseTheme = AppTheme.darkTheme;
      final theme = baseTheme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
              style: baseTheme.filledButtonTheme.style?.copyWith(
                  textStyle: WidgetStatePropertyAll(baseTheme
                      .textTheme.labelLarge!
                      .copyWith(fontFamily: 'Roboto')))));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepaintBoundary(key: key, child: HomeScreen(client: client))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-agent-tasks')), findsOneWidget);
      expect(find.text('Polish the conversation experience'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
          tester
              .widgetList<ProjectAvatar>(find.byType(ProjectAvatar))
              .where((avatar) => avatar.name == 'Omni Code')
              .every((avatar) => avatar.iconDataUri == artwork),
          isTrue);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
            '../.cache/workspace-agent/home-${width.toInt()}${withConversation ? '-conversation' : ''}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
    client.dispose();
  });
}
