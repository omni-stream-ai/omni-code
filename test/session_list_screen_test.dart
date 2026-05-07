import 'dart:async';
import 'dart:convert';

import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/project_detail_screen.dart';
import 'package:omni_code/src/screens/session_list_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:omni_code/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'active project moves to the first position after returning to list',
    (tester) async {
      String? pushedRouteName;
      final alpha = _project(
        id: 'alpha',
        name: 'Alpha',
        updatedAt: DateTime(2026, 5, 5, 11),
      );
      final beta = _project(
        id: 'beta',
        name: 'Beta',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          if (request.method == 'GET' && request.url.path == '/projects') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': alpha.id,
                    'name': alpha.name,
                    'root_path': alpha.rootPath,
                    'updated_at': alpha.updatedAt.toIso8601String(),
                    'session_count': alpha.sessionCount,
                    'last_session_preview': alpha.lastSessionPreview,
                  },
                  {
                    'id': beta.id,
                    'name': beta.name,
                    'root_path': beta.rootPath,
                    'updated_at': beta.updatedAt.toIso8601String(),
                    'session_count': beta.sessionCount,
                    'last_session_preview': beta.lastSessionPreview,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' && request.url.path == '/sessions') {
            return http.Response(
              jsonEncode({'data': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      client.debugSeedProjects([alpha, beta]);

      await tester.pumpWidget(
        _TestApp(
          home: SessionListScreen(client: client),
          onGenerateRoute: (settings) {
            if (settings.arguments is ProjectSummary) {
              final project = settings.arguments! as ProjectSummary;
              if (settings.name != AppRoutes.project(project.id)) {
                return null;
              }
              pushedRouteName = settings.name;
              return MaterialPageRoute<void>(
                builder: (_) => _FakeProjectDetailScreen(
                  client: client,
                  project: project,
                ),
              );
            }
            return null;
          },
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_projectNames(tester), ['Alpha', 'Beta']);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(pushedRouteName, AppRoutes.project('beta'));
      expect(find.text('模拟项目详情'), findsOneWidget);
      await tester.tap(find.text('触发活动并返回'));
      await tester.pumpAndSettle();

      expect(_projectNames(tester), ['Beta', 'Alpha']);
    },
  );

  testWidgets('home shows the 3 most recent sessions and opens session detail',
      (tester) async {
    String? pushedSessionRouteName;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'project-1',
                  'name': 'Project One',
                  'root_path': '/tmp/project-1',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'session_count': 2,
                  'last_session_preview': null,
                },
                {
                  'id': 'project-2',
                  'name': 'Project Two',
                  'root_path': '/tmp/project-2',
                  'updated_at': '2026-05-05T10:00:00.000',
                  'session_count': 2,
                  'last_session_preview': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'session-d',
                  'project_id': 'project-2',
                  'title': 'Session D',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T10:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
                {
                  'id': 'session-b',
                  'project_id': 'project-2',
                  'title': 'Session B',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'running',
                  'updated_at': '2026-05-05T12:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': 'Second latest',
                  'pending_approval': null,
                },
                {
                  'id': 'session-a',
                  'project_id': 'project-1',
                  'title': 'Session A',
                  'agent': 'claude_code',
                  'brief_reply_mode': false,
                  'status': 'awaiting_approval',
                  'updated_at': '2026-05-05T13:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': 'Latest',
                  'pending_approval': null,
                },
                {
                  'id': 'session-c',
                  'project_id': 'project-1',
                  'title': 'Session C',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'failed',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionListScreen(client: client),
        onGenerateRoute: (settings) {
          if (settings.arguments is SessionSummary) {
            final session = settings.arguments! as SessionSummary;
            if (settings.name !=
                AppRoutes.session(session.projectId, session.id)) {
              return null;
            }
            pushedSessionRouteName = settings.name;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('模拟会话详情')),
              ),
            );
          }
          return null;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Session A'), findsOneWidget);
    expect(find.text('Session B'), findsOneWidget);
    expect(find.text('Session C'), findsOneWidget);
    expect(find.text('Session D'), findsNothing);
    expect(find.text('Project One'), findsWidgets);
    expect(find.text('Project Two'), findsWidgets);

    await tester.tap(find.text('Session B'));
    await tester.pumpAndSettle();

    expect(pushedSessionRouteName, AppRoutes.session('project-2', 'session-b'));
    expect(find.text('模拟会话详情'), findsOneWidget);
  });

  testWidgets('refresh loading bar overlays the project list', (tester) async {
    final pendingResponse = Completer<http.Response>();
    addTearDown(() {
      if (!pendingResponse.isCompleted) {
        pendingResponse.complete(
          http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'alpha',
                  'name': 'Alpha',
                  'root_path': '/tmp/alpha',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'session_count': 1,
                  'last_session_preview': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
    });

    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return pendingResponse.future;
        }
        return http.Response('not found', 404);
      }),
    );
    client.debugSeedProjects([
      _project(
        id: 'alpha',
        name: 'Alpha',
        updatedAt: DateTime(2026, 5, 5, 11),
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionListScreen(client: client),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('refresh loading bar overlays the session list', (tester) async {
    final pendingResponse = Completer<http.Response>();
    addTearDown(() {
      if (!pendingResponse.isCompleted) {
        pendingResponse.complete(
          http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'session-1',
                  'project_id': 'project-1',
                  'title': 'Session 1',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
    });

    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/projects/project-1/sessions') {
          return pendingResponse.future;
        }
        return http.Response('not found', 404);
      }),
    );
    client.syncSessionSummary(
      SessionSummary(
        id: 'session-1',
        projectId: 'project-1',
        title: 'Session 1',
        agent: AgentKind.codex,
        briefReplyMode: false,
        status: SessionStatus.idle,
        updatedAt: DateTime(2026, 5, 5, 11),
        unreadCount: 0,
        pendingApproval: null,
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: ProjectDetailScreen(
          project: _project(
            id: 'project-1',
            name: 'Project 1',
            updatedAt: DateTime(2026, 5, 5, 11),
          ),
          client: client,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('auth approval command is shown as a single shell command',
      (tester) async {
    const requestId = '9c509a93-e16f-476a-9c7e-dec7ca3dcd23';
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'POST' &&
            request.url.path == '/client-auth/requests') {
          return http.Response(
            jsonEncode({
              'data': {
                'request_id': requestId,
                'status': 'pending',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionListScreen(client: client),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionListScreen)),
    )!;
    expect(find.text(l10n.waitingApprovalTitle), findsOneWidget);
    expect(
      find.text(
        'omni-code-bridge client-auth approve --request-id $requestId',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('client-auth approve\n--request-id'),
      findsNothing,
    );
    expect(
      find.text(l10n.waitingApprovalDownloadBridge),
      findsOneWidget,
    );
  });

  testWidgets('pending auth request is resumed instead of recreated',
      (tester) async {
    const requestId = 'existing-request-id';
    var registerRequestCount = 0;
    var statusRequestCount = 0;

    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        bridgeToken: '',
        pendingClientAuthRequestId: requestId,
      ),
    );

    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'GET' &&
            request.url.path == '/client-auth/requests/$requestId') {
          statusRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'request_id': requestId,
                'status': 'pending',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/client-auth/requests') {
          registerRequestCount += 1;
          return http.Response('unexpected register', 500);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionListScreen(client: client),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(statusRequestCount, 1);
    expect(registerRequestCount, 0);
    expect(
      find.text('omni-code-bridge client-auth approve --request-id $requestId'),
      findsOneWidget,
    );
  });

  testWidgets('retry auth forces a new request', (tester) async {
    const pendingRequestId = 'existing-request-id';
    const freshRequestId = 'fresh-request-id';
    var registerRequestCount = 0;
    var statusRequestCount = 0;

    addTearDown(() {
      appSettingsController.debugReplaceSettings(AppSettings.defaults());
    });
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        bridgeToken: '',
        pendingClientAuthRequestId: pendingRequestId,
      ),
    );

    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'GET' &&
            request.url.path == '/client-auth/requests/$pendingRequestId') {
          statusRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'request_id': pendingRequestId,
                'status': 'pending',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/client-auth/requests') {
          registerRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'request_id': freshRequestId,
                'status': 'pending',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionListScreen(client: client),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(statusRequestCount, 1);
    expect(registerRequestCount, 0);
    expect(find.widgetWithText(TextButton, '重新请求'), findsOneWidget);

    final retryButton = find.widgetWithText(TextButton, '重新请求');
    final dynamic onPressed = tester.widget<TextButton>(retryButton).onPressed;
    await onPressed();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(registerRequestCount, 1);
    expect(
      find.text(
          'omni-code-bridge client-auth approve --request-id $freshRequestId'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
    this.onGenerateRoute,
  });

  final Widget home;
  final Route<dynamic>? Function(RouteSettings settings)? onGenerateRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: home,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: onGenerateRoute,
    );
  }
}

List<String> _projectNames(WidgetTester tester) {
  final names = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .where((text) => text == 'Alpha' || text == 'Beta')
      .toList();
  final unique = <String>[];
  for (final name in names) {
    if (!unique.contains(name)) {
      unique.add(name);
    }
  }
  return unique;
}

ProjectSummary _project({
  required String id,
  required String name,
  required DateTime updatedAt,
}) {
  return ProjectSummary(
    id: id,
    name: name,
    rootPath: '/tmp/$id',
    updatedAt: updatedAt,
    sessionCount: 0,
    lastSessionPreview: null,
  );
}

class _FakeProjectDetailScreen extends StatelessWidget {
  const _FakeProjectDetailScreen({
    required this.client,
    required this.project,
  });

  final BridgeClient client;
  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模拟项目详情')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            client.syncSessionSummary(
              SessionSummary(
                id: 'session-${project.id}',
                projectId: project.id,
                title: 'session-${project.id}',
                agent: AgentKind.codex,
                briefReplyMode: false,
                status: SessionStatus.running,
                updatedAt: DateTime(2026, 5, 5, 12),
                unreadCount: 0,
                lastMessagePreview: 'new activity',
                pendingApproval: null,
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('触发活动并返回'),
        ),
      ),
    );
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
