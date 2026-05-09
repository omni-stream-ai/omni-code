import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/home_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('home opens projects screen from the projects card',
      (tester) async {
    String? pushedRouteName;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'alpha',
                  name: 'Alpha',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
                _projectJson(
                  id: 'beta',
                  name: 'Beta',
                  updatedAt: '2026-05-05T10:00:00.000',
                ),
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

    await tester.pumpWidget(
      _TestApp(
        home: HomeScreen(client: client),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.projects) {
            pushedRouteName = settings.name;
            return MaterialPageRoute<void>(
              builder: (_) => ProjectsScreen(client: client),
            );
          }
          return null;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;

    await tester.tap(find.text(l10n.projectsTitle));
    await tester.pumpAndSettle();

    expect(pushedRouteName, AppRoutes.projects);
    expect(find.byType(ProjectsScreen), findsOneWidget);
  });

  testWidgets('home shows dashboard skeleton while loading initial data',
      (tester) async {
    final gate = Completer<void>();
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          await gate.future;
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'project-1',
                  name: 'Project One',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
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

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();

    expect(find.byKey(const Key('home-dashboard-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Project One'), findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(find.text(l10n.noSessionsYet), findsOneWidget);
  });

  testWidgets('projects screen keeps the active project at the top',
      (tester) async {
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
                _projectJson(
                  id: alpha.id,
                  name: alpha.name,
                  updatedAt: alpha.updatedAt.toIso8601String(),
                ),
                _projectJson(
                  id: beta.id,
                  name: beta.name,
                  updatedAt: beta.updatedAt.toIso8601String(),
                ),
              ],
            }),
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
        home: ProjectsScreen(client: client),
        onGenerateRoute: (settings) {
          if (settings.arguments is ProjectSummary) {
            final project = settings.arguments! as ProjectSummary;
            if (settings.name != AppRoutes.project(project.id)) {
              return null;
            }
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

    expect(find.text('模拟项目详情'), findsOneWidget);
    await tester.tap(find.text('触发活动并返回'));
    await tester.pumpAndSettle();

    expect(_projectNames(tester), ['Beta', 'Alpha']);
  });

  testWidgets('direct /projects load redirects unauthorized users to home',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.projects,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case AppRoutes.home:
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => HomeScreen(client: client),
              );
            case AppRoutes.projects:
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => ProjectsScreen(client: client),
              );
          }
          return null;
        },
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(l10n.connectWelcomeTitle), findsOneWidget);
    expect(find.byType(ProjectsScreen), findsNothing);
  });

  testWidgets('home shows recent sessions in groups of five', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'project-1',
                  name: 'Project One',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
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
                for (var i = 7; i >= 1; i--)
                  _sessionJson(
                    id: 'session-$i',
                    projectId: 'project-1',
                    title: 'Session $i',
                    updatedAt: '2026-05-05T${10 + i}:00:00.000',
                    preview: 'Preview $i',
                  ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Session 7'), findsOneWidget);
    expect(find.text('Session 6'), findsOneWidget);
    expect(find.text('Session 5'), findsOneWidget);
    expect(find.text('Session 4'), findsOneWidget);
    expect(find.text('Session 3'), findsOneWidget);
    expect(find.text('Session 2'), findsNothing);
    expect(find.text('Session 1'), findsNothing);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    final loadMore = find.text(l10n.loadMoreSessionsLabel);
    expect(loadMore, findsOneWidget);

    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Session 2'), findsOneWidget);
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);
  });

  testWidgets('home opens session detail from a recent session card',
      (tester) async {
    String? pushedSessionRouteName;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'project-1',
                  name: 'Project One',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
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
                _sessionJson(
                  id: 'session-a',
                  projectId: 'project-1',
                  title: 'Session A',
                  updatedAt: '2026-05-05T13:00:00.000',
                  preview: 'Latest',
                ),
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
        home: HomeScreen(client: client),
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

    await tester.tap(find.text('Session A'));
    await tester.pumpAndSettle();

    expect(pushedSessionRouteName, AppRoutes.session('project-1', 'session-a'));
    expect(find.text('模拟会话详情'), findsOneWidget);
  });

  testWidgets('home shows connect state before requesting authorization',
      (tester) async {
    const requestId = '9c509a93-e16f-476a-9c7e-dec7ca3dcd23';
    var registerRequestCount = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'POST' &&
            request.url.path == '/client-auth/requests') {
          registerRequestCount += 1;
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

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(find.text(l10n.connectWelcomeTitle), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.authorizeThisDevice),
      findsOneWidget,
    );
    expect(find.text(l10n.waitingApprovalTitle), findsNothing);
    expect(registerRequestCount, 0);

    final authorizeButton =
        find.widgetWithText(FilledButton, l10n.authorizeThisDevice);
    await tester.ensureVisible(authorizeButton);
    await tester.tap(authorizeButton);
    await tester.pumpAndSettle();

    expect(registerRequestCount, 1);
    expect(find.text(l10n.waitingApprovalTitle), findsOneWidget);
    expect(
      find.text(
        'omni-code-bridge client-auth approve --request-id $requestId',
      ),
      findsOneWidget,
    );
  });

  testWidgets('home can edit bridge url inline before authorization',
      (tester) async {
    const requestId = 'inline-config-request-id';
    final requestedUris = <Uri>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requestedUris.add(request.url);
        if (request.method == 'GET' &&
            request.url == Uri.parse('http://127.0.0.1:8787/projects')) {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'POST' &&
            request.url ==
                Uri.parse('http://10.0.0.8:8787/client-auth/requests')) {
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

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;

    await tester.enterText(
      find.byType(TextField).first,
      'http://10.0.0.8:8787',
    );
    await tester.pump();

    final authorizeButton =
        find.widgetWithText(FilledButton, l10n.authorizeThisDevice);
    await tester.ensureVisible(authorizeButton);
    await tester.tap(authorizeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      appSettingsController.settings.bridgeUrl,
      'http://10.0.0.8:8787',
    );
    expect(
      requestedUris,
      contains(Uri.parse('http://10.0.0.8:8787/client-auth/requests')),
    );
    expect(find.text(l10n.waitingApprovalTitle), findsOneWidget);
  });

  testWidgets('pending auth request resumes waiting approval state',
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

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(statusRequestCount, 1);
    expect(registerRequestCount, 0);
    expect(find.text(l10n.waitingApprovalTitle), findsOneWidget);
    expect(find.text(l10n.connectWelcomeTitle), findsNothing);
    expect(
      find.text(
        'omni-code-bridge client-auth approve --request-id $requestId',
      ),
      findsOneWidget,
    );
  });

  testWidgets('request again forces a new auth request', (tester) async {
    const pendingRequestId = 'existing-request-id';
    const freshRequestId = 'fresh-request-id';
    var registerRequestCount = 0;
    var statusRequestCount = 0;

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

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(statusRequestCount, 1);
    expect(registerRequestCount, 0);
    expect(find.text(l10n.waitingApprovalTitle), findsOneWidget);
    expect(find.text(l10n.backToWelcome), findsOneWidget);

    final requestAgainButton =
        find.widgetWithText(OutlinedButton, l10n.waitingApprovalRequestAgain);
    tester.widget<OutlinedButton>(requestAgainButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(registerRequestCount, 1);
    expect(
      find.text(
        'omni-code-bridge client-auth approve --request-id $freshRequestId',
      ),
      findsOneWidget,
    );
  });

  testWidgets('waiting approval back button returns to the welcome page',
      (tester) async {
    final pendingRequestId = 'existing-request-id';
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response('unauthorized', 401);
        }
        if (request.method == 'GET' &&
            request.url.path == '/client-auth/requests/$pendingRequestId') {
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
        return http.Response('not found', 404);
      }),
    );
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        pendingClientAuthRequestId: pendingRequestId,
      ),
    );

    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    await tester.tap(find.text(l10n.backToWelcome));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(l10n.waitingApprovalTitle), findsNothing);
    expect(find.text(l10n.connectWelcomeTitle), findsOneWidget);
    expect(find.text(l10n.authorizeThisDevice), findsOneWidget);
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

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
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

Map<String, Object?> _projectJson({
  required String id,
  required String name,
  required String updatedAt,
}) {
  return {
    'id': id,
    'name': name,
    'root_path': '/tmp/$id',
    'updated_at': updatedAt,
    'session_count': 0,
    'last_session_preview': null,
  };
}

Map<String, Object?> _sessionJson({
  required String id,
  required String projectId,
  required String title,
  required String updatedAt,
  String? preview,
}) {
  return {
    'id': id,
    'project_id': projectId,
    'title': title,
    'agent': 'codex',
    'brief_reply_mode': false,
    'status': 'running',
    'updated_at': updatedAt,
    'unread_count': 0,
    'last_message_preview': preview,
    'pending_approval': null,
  };
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
