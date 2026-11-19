import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/shortcuts/desktop_search_dialog.dart';
import 'package:omni_code/src/workspace_agent_models.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });
  final tasks = [
    for (final status in ['blocked', 'completed'])
      {
        'session_id': 's1',
        'project_id': 'p1',
        'task': {
          'id': status,
          'title': '$status child',
          'summary': 'API repair',
          'status': status,
          'group': {
            'id': 'delivery',
            'title': 'Release bundle',
            'summary': 'Ship improvements'
          },
        }
      },
  ];
  BridgeClient client({bool failTasks = false, VoidCallback? onTaskRead}) =>
      BridgeClient(httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path.contains('workspace-agent')) onTaskRead?.call();
        if (request.url.path.contains('workspace-agent') && failTasks) {
          return http.Response('unavailable', 500);
        }
        final Object data;
        if (request.url.path == '/projects') {
          data = [
            {
              'id': 'p1',
              'name': 'Alpha',
              'root_path': '/alpha',
              'updated_at': '2026-11-14T10:00:00Z',
              'session_count': 1
            }
          ];
        } else if (request.url.path == '/v2/sessions') {
          data = [
            {
              'id': 's1',
              'project_id': 'p1',
              'title': 'Conversation',
              'agent': 'codex',
              'status': 'idle',
              'updated_at': '2026-11-14T10:00:00Z',
              'unread_count': 0
            }
          ];
        } else {
          data = {
            'scope': {},
            'selected_sessions': 1,
            'cached_sessions': 1,
            'tasks': tasks,
            'projects': [
              {'id': 'p1', 'name': 'Alpha'}
            ]
          };
        }
        return http.Response(jsonEncode({'data': data}), 200,
            headers: {'content-type': 'application/json'});
      }));

  testWidgets(
      'disabled task analysis searches conversations without task reads',
      (tester) async {
    appSettingsController.debugReplaceSettings(
        AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
    var taskReads = 0;
    final bridge = client(onTaskRead: () => taskReads++);
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DesktopSearchDialog(client: bridge)));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('desktop-search-field')), 'release api');
    await tester.pumpAndSettle();
    expect(find.text('blocked child'), findsNothing);
    expect(find.text('completed child'), findsNothing);
    await tester.enterText(
        find.byKey(const Key('desktop-search-field')), 'conversation');
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsOneWidget);
    expect(taskReads, 0);
    await tester.pumpWidget(const SizedBox());
    bridge.dispose();
  });

  testWidgets(
      'desktop search finds grouped originals, history, and returns selected task',
      (tester) async {
    final bridge = client();
    Object? selected;
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        selected = await showDialog<Object>(
                            context: context,
                            builder: (_) =>
                                DesktopSearchDialog(client: bridge));
                      },
                      child: const Text('Search')),
                ))));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('desktop-search-field')), 'RELEASE api');
    await tester.pumpAndSettle();
    expect(find.text('blocked child'), findsOneWidget);
    expect(find.text('completed child'), findsOneWidget);
    expect(find.textContaining('History · Completed'), findsOneWidget);
    await tester.tap(find.text('completed child'));
    await tester.pumpAndSettle();
    expect((selected as WorkspaceTask).id, 'completed');
    bridge.dispose();
  });

  testWidgets('task search failure preserves project and session results',
      (tester) async {
    final bridge = client(failTasks: true);
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DesktopSearchDialog(client: bridge)));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Could not load task search'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    bridge.dispose();
  });
}
