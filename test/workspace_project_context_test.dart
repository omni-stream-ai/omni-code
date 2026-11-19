import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

import 'workspace_agent_test.dart' as fixtures;

Map<String, dynamic> _project(String id) => {
      'id': id,
      'name': id == 'alpha' ? 'Alpha' : 'Beta',
      'root_path': '/workspace/$id',
      'updated_at': '2026-11-16T12:00:00Z',
      'session_count': 1,
    };

Map<String, dynamic> _task(String id, String project, String status) => {
      ...fixtures.task(id, status, '$project $id'),
      'project_id': project,
      'session_id': 's-$project',
    };

class _ContextServer {
  String? activeProject = 'alpha';
  bool dirty = true;
  bool gitAvailable = true;
  bool withDispatch = false;
  String alphaBranch = 'feature/alpha';
  String status = 'in_progress';
  int reads = 0;
  Completer<http.Response>? heldAlpha;
  Map<String, dynamic>? statusChange;

  Map<String, dynamic> snapshot(String? selected) {
    final project = selected ?? activeProject;
    return {
      ...fixtures.snapshot(chat: [
        {
          'id': 'answer',
          'role': 'assistant',
          'content': 'Keep **discussing** the project.'
        },
      ], tasks: [
        _task('open', 'alpha', status),
        _task('done', 'alpha', 'completed'),
        _task('other', 'beta', 'in_progress'),
      ]),
      'conversation': {
        'id': 'conversation',
        'active_project_id': activeProject
      },
      if (withDispatch)
        'dispatch_tasks': [
          for (final id in ['alpha', 'beta'])
            {
              'id': 'work-$id',
              'request_id': 'work',
              'project_id': id,
              'session_id': 's-$id',
              'title': 'Live $id task',
              'status': 'running',
              'agent': 'pi',
              'summary': 'Verifying $id implementation',
              'created_at': '2026-11-16T12:00:00Z',
              'updated_at': '2026-11-16T12:00:00Z',
            },
        ],
      if (project != null)
        'project_context': {
          'project': _project(project),
          'git_status': !gitAvailable
              ? null
              : {
                  'branch': project == 'alpha' ? alphaBranch : 'feature/beta',
                  'dirty': dirty,
                  'staged': dirty,
                  'unstaged': dirty,
                  'untracked': dirty,
                  'staged_count': dirty ? 2 : 0,
                  'unstaged_count': dirty ? 3 : 0,
                  'untracked_count': dirty ? 1 : 0,
                  'ahead': 1,
                  'behind': 0,
                },
          'commit': {
            'head': 'abcdef0123456789',
            'subject': '$project latest delivery'
          },
          'sessions': [
            {
              'id': 's-$project',
              'project_id': project,
              'title': '$project conversation',
              'preview': 'Continue this conversation'
            },
          ],
        },
    };
  }

  Future<http.Response> call(http.Request request) async {
    switch (request.url.path) {
      case '/settings':
        return fixtures.ok({'model_providers': []});
      case '/workspace-agent/model':
        return fixtures.ok({'selection': null});
      case '/workspace-agent/dispatch/settings':
        return fixtures.ok({'agent': 'pi'});
      case '/workspace-agent/tasks/actions':
        statusChange = jsonDecode(request.body) as Map<String, dynamic>;
        status = statusChange!['status'] as String;
        return fixtures.ok({'action_id': 'status-action'});
      case '/v2/sessions/s-alpha':
        return fixtures.ok({
          'session': {
            'id': 's-alpha',
            'project_id': 'alpha',
            'title': 'alpha conversation',
            'agent': 'pi',
            'status': 'idle',
            'updated_at': '2026-11-16T12:00:00Z',
            'unread_count': 0,
          }
        });
      default:
        reads++;
        final selected = request.url.queryParameters['project_id'];
        if (selected == 'alpha' && heldAlpha != null) return heldAlpha!.future;
        return fixtures.ok(snapshot(selected));
    }
  }
}

Future<void> _showChat(WidgetTester tester, _ContextServer server,
    {String? selected,
    void Function(String)? onNavigate,
    double textScale = 1}) async {
  final client = BridgeClient(httpClient: MockClient(server.call));
  addTearDown(client.dispose);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!),
    home: WorkspaceAgentChat(
        client: client,
        fullPage: true,
        projectId: selected,
        projects: [
          ProjectSummary.fromJson(_project('alpha')),
          ProjectSummary.fromJson(_project('beta'))
        ]),
    onGenerateRoute: (settings) {
      onNavigate?.call(settings.name!);
      return MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Text('Execution conversation opened')));
    },
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
      () => appSettingsController.debugReplaceSettings(AppSettings.defaults()));
  tearDown(
      () => appSettingsController.debugReplaceSettings(AppSettings.defaults()));

  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'assistant shows the discussed projects git and related tasks at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _ContextServer();
      await _showChat(tester, server);
      expect(find.text('Keep discussing the project.'), findsOneWidget);
      if (width == 320) {
        expect(find.byKey(const Key('workspace-context-git-branch')),
            findsNothing);
        await tester
            .tap(find.byKey(const Key('workspace-project-context-summary')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('workspace-context-project-name')),
          findsOneWidget);
      expect(find.text('feature/alpha'), findsOneWidget);
      expect(find.text('Uncommitted changes'), findsOneWidget);
      expect(find.text('Staged  2'), findsOneWidget);
      expect(find.text('Unstaged  3'), findsOneWidget);
      expect(find.text('Untracked  1'), findsOneWidget);
      expect(find.text('abcdef01'), findsOneWidget);
      expect(find.text('alpha latest delivery'), findsOneWidget);
      expect(find.text('alpha open'), findsOneWidget);
      expect(find.text('alpha done'), findsNothing);
      expect(find.text('beta other'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('alpha done'), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey(('task-actions', 's-alpha', 'open'))));
      await tester
          .tap(find.byKey(const ValueKey(('task-actions', 's-alpha', 'open'))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey(('set-task-status', 'completed'))));
      await tester.pumpAndSettle();
      expect(server.statusChange!['expected_status'], 'in_progress');
      expect(server.statusChange!['tasks'], [
        {'session_id': 's-alpha', 'task_id': 'open'}
      ]);
      expect(find.text('Task status updated'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'compact project context fits large text and shows running work even when old task records are complete',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _ContextServer()
      ..status = 'completed'
      ..withDispatch = true;
    await _showChat(tester, server, textScale: 1.6);
    expect(find.text('Tasks 1'), findsOneWidget);
    await tester
        .tap(find.byKey(const Key('workspace-project-context-summary')));
    await tester.pumpAndSettle();
    expect(find.text('Live alpha task'), findsOneWidget);
    expect(find.text('Live beta task'), findsNothing);
    expect(find.text('Verifying alpha implementation'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'project git polling updates independently and keeps existing markdown stable',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _ContextServer();
    await _showChat(tester, server);
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    final reads = server.reads;
    server.dirty = false;
    server.alphaBranch = 'main';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Working tree clean'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)), same(markdown));
    expect(server.reads, reads + 1,
        reason: 'the context shares conversation polling');
    server.gitAvailable = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Git status unavailable'), findsOneWidget);
    expect(find.text('Working tree clean'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'automatic discussion changes and explicit project selection keep context isolated from late polls',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _ContextServer();
    await _showChat(tester, server, selected: 'alpha');
    await tester.enterText(
        find.byKey(const Key('agent-chat-input')), 'Preserve this draft');
    server.heldAlpha = Completer<http.Response>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.tap(find.byTooltip('Current project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Beta'));
    await tester.pumpAndSettle();
    expect(find.text('feature/beta'), findsOneWidget);
    expect(find.text('beta other'), findsOneWidget);
    server.heldAlpha!.complete(fixtures.ok(server.snapshot('alpha')));
    server.heldAlpha = null;
    await tester.pumpAndSettle();
    expect(find.text('feature/alpha'), findsNothing);
    expect(find.text('alpha open'), findsNothing);
    expect(find.text('Preserve this draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Current project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        PopupMenuItem<String>, 'All projects · Global tasks'));
    await tester.pumpAndSettle();
    server.activeProject = 'beta';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('feature/beta'), findsOneWidget);
    expect(find.text('alpha open'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'disabling task analysis keeps live project info and linked conversation navigation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _ContextServer();
    String? destination;
    await _showChat(tester, server, onNavigate: (route) => destination = route);
    await tester
        .tap(find.byKey(const Key('workspace-project-context-summary')));
    await tester.pumpAndSettle();
    appSettingsController.debugReplaceSettings(
        AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
    await tester.pumpAndSettle();
    expect(find.text('Related tasks'), findsNothing);
    expect(find.text('alpha open'), findsNothing);
    expect(find.text('Linked conversations'), findsOneWidget);
    expect(find.text('feature/alpha'), findsOneWidget);
    final session = find.text('alpha conversation');
    await tester.ensureVisible(session);
    await tester.tap(session);
    await tester.pumpAndSettle();
    expect(destination, AppRoutes.session('alpha', 's-alpha'));
    expect(find.text('Execution conversation opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a fresh global conversation does not pick a project from unrelated tasks',
      (tester) async {
    final server = _ContextServer()..activeProject = null;
    await _showChat(tester, server);
    expect(find.byKey(const Key('workspace-project-context-summary')),
        findsNothing);
    expect(
        find.byKey(const Key('workspace-context-project-name')), findsNothing);
    expect(find.byKey(const Key('workspace-project-context-button')),
        findsNothing);
    expect(find.text('Keep discussing the project.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
