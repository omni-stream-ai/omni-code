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
import 'package:omni_code/src/widgets/project_avatar.dart';
import 'package:omni_code/src/screens/home_screen.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/desktop_navigation_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets(
      'disabled automatic analysis hides task sections and display entry',
      (tester) async {
    appSettingsController.debugReplaceSettings(
        AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
    var analyses = 0;
    final client = BridgeClient(httpClient: _FakeHttpClient((request) async {
      final dynamic data;
      if (request.url.path == '/workspace-agent') {
        data = {
          'scope': {},
          'tasks': [],
          'running': false,
          'chat': [],
          'dispatch_tasks': [],
        };
      } else if (request.url.path.endsWith('/analyze')) {
        analyses++;
        data = {'running': false};
      } else {
        data = [];
      }
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('home-main-agent-conversation')), findsOneWidget);
    expect(find.byKey(const Key('home-recent-sessions')), findsOneWidget);
    expect(find.byKey(const Key('home-agent-tasks')), findsNothing);
    expect(find.byKey(const Key('home-tasks-skeleton')), findsNothing);
    await tester.enterText(find.byKey(const Key('home-assistant-input')),
        'Keep the conversation draft');
    await tester.tap(find.byKey(const Key('home-display-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-show-recent-tasks')), findsNothing);
    await tester.tap(find.byKey(const Key('home-display-save')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();
    expect(analyses, 0);
    expect(appSettingsController.settings.homeShowRecentTasks, isTrue);

    appSettingsController.debugReplaceSettings(
        appSettingsController.settings.copyWith(autoTaskAnalysisEnabled: true));
    await tester.pumpAndSettle();
    expect(analyses, 1);
    expect(find.byKey(const Key('home-agent-tasks')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        'Keep the conversation draft');
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('home opens projects from navigation', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
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

    expect(find.byKey(const Key('home-app-logo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-navigation-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.projectsTitle));
    await tester.pumpAndSettle();

    expect(pushedRouteName, AppRoutes.projects);
    expect(find.byType(ProjectsScreen), findsOneWidget);
    expect(
        tester
            .widgetList<ProjectAvatar>(find.byType(ProjectAvatar))
            .map((avatar) => avatar.name),
        containsAll(['Alpha', 'Beta']));
  });

  testWidgets(
      'home display supports every combination and persists after reload',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryAppSettingsStore();
    appSettingsController.debugReplaceStore(store);
    final client = BridgeClient(httpClient: _FakeHttpClient((request) async {
      final dynamic data = request.url.path == '/workspace-agent'
          ? {
              'scope': {},
              'tasks': [],
              'selected_sessions': 0,
              'cached_sessions': 0,
              'running': false,
              'errors': {}
            }
          : request.url.path.endsWith('/analyze')
              ? {'running': false}
              : [];
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Keep my home draft');
    for (final width in [390.0, 1000.0, 1600.0]) {
      tester.view.physicalSize = Size(width, 1100);
      await tester.pumpAndSettle();
      for (final mask in [7, 6, 5, 4, 3, 2, 1, 0, 7]) {
        final settingsButton = find.byKey(const Key('home-display-settings'));
        await tester.ensureVisible(settingsButton);
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();
        final switches = [
          'home-show-main-agent',
          'home-show-recent-sessions',
          'home-show-recent-tasks'
        ];
        for (var index = 0; index < switches.length; index++) {
          final toggle = find.byKey(Key(switches[index]));
          if (tester.widget<SwitchListTile>(toggle).value !=
              (mask & (1 << index) != 0)) {
            await tester.tap(toggle);
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.byKey(const Key('home-display-save')));
        await tester.pumpAndSettle();
        final main = find.byKey(const Key('home-main-agent-conversation'));
        final sessions = find.byKey(const Key('home-recent-sessions'));
        final tasks = find.byKey(const Key('home-agent-tasks'));
        expect(main, mask & 1 != 0 ? findsOneWidget : findsNothing);
        expect(sessions, mask & 2 != 0 ? findsOneWidget : findsNothing);
        expect(tasks, mask & 4 != 0 ? findsOneWidget : findsNothing);
        expect(find.byKey(const Key('home-restore-sections')),
            mask == 0 ? findsOneWidget : findsNothing);
        final persisted =
            AppSettings.fromJson(jsonDecode((await store.read())!));
        expect(persisted.homeShowMainAgent, mask & 1 != 0);
        expect(persisted.homeShowRecentSessions, mask & 2 != 0);
        expect(persisted.homeShowRecentTasks, mask & 4 != 0);
        if (mask & 1 != 0) {
          expect(
              tester
                  .widget<TextField>(
                      find.byKey(const Key('home-assistant-input')))
                  .controller!
                  .text,
              'Keep my home draft');
        }
        if (width == 1600 && mask == 7) {
          expect(tester.getBottomLeft(main).dy,
              lessThan(tester.getTopLeft(sessions).dy));
          expect(tester.getTopLeft(sessions).dy, tester.getTopLeft(tasks).dy);
          expect(tester.getTopLeft(sessions).dx,
              lessThan(tester.getTopLeft(tasks).dx));
          expect(tester.getSize(main).width,
              greaterThan(tester.getSize(sessions).width));
        }
        if (width == 390 && mask == 7) {
          expect(tester.getBottomLeft(main).dy,
              lessThan(tester.getTopLeft(sessions).dy));
          expect(tester.getBottomLeft(sessions).dy,
              lessThan(tester.getTopLeft(tasks).dy));
        }
        expect(tester.takeException(), isNull);
      }
    }
    await appSettingsController.save(appSettingsController.settings.copyWith(
        homeShowMainAgent: false,
        homeShowRecentSessions: true,
        homeShowRecentTasks: false));
    await tester.pumpWidget(const SizedBox());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    await appSettingsController.load();
    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-main-agent-conversation')), findsNothing);
    expect(find.byKey(const Key('home-recent-sessions')), findsOneWidget);
    expect(find.byKey(const Key('home-agent-tasks')), findsNothing);
    await tester.tap(find.byKey(const Key('home-display-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-show-main-agent')));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(appSettingsController.settings.homeShowMainAgent, isFalse);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets(
      'home leads with main agent chat and links recent tasks to their source',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? openedRoute;
    final session = _sessionJson(
        id: 'session-1',
        projectId: 'alpha',
        title: 'Release conversation',
        updatedAt: '2026-11-16T10:00:00Z');
    final otherSession = _sessionJson(
        id: 'session-2',
        projectId: 'alpha',
        title: 'Search conversation',
        updatedAt: '2026-11-16T09:00:00Z');
    Map<String, dynamic> task(String id, String sessionId, String title,
            String status, String updatedAt) =>
        {
          'session_id': sessionId,
          'project_id': 'alpha',
          'session_title': sessionId == 'session-1'
              ? 'Release conversation'
              : 'Search conversation',
          'updated_at': updatedAt,
          'task': {
            'id': id,
            'title': title,
            'summary': '',
            'status': status,
            'updated_at': updatedAt
          },
        };
    final client = BridgeClient(httpClient: _FakeHttpClient((request) async {
      dynamic data;
      switch (request.url.path) {
        case '/projects':
          data = [
            _projectJson(
                id: 'alpha', name: 'Alpha', updatedAt: '2026-11-16T10:00:00Z')
          ];
        case '/v2/sessions':
          data = [session, otherSession];
        case '/v2/sessions/session-2':
          return http.Response(jsonEncode({'session': otherSession}), 200,
              headers: {'content-type': 'application/json'});
        case '/workspace-agent/analyze':
          data = {'running': false};
        case '/workspace-agent':
          data = {
            'scope': {},
            'selected_sessions': 2,
            'cached_sessions': 2,
            'running': false,
            'errors': {},
            'tasks': [
              task('release', 'session-1', 'Review release', 'blocked',
                  '2026-11-15T10:00:00Z'),
              task('search', 'session-2', 'Search shipped', 'completed',
                  '2026-11-16T11:00:00Z'),
              {
                ...task('archived', 'session-1', 'Archived work', 'pending',
                    '2026-11-16T12:00:00Z'),
                'archived': true
              },
            ]
          };
        default:
          data = [];
      }
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'});
    }));
    for (final width in [390.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(_TestApp(
          home: HomeScreen(client: client),
          onGenerateRoute: (settings) {
            openedRoute = settings.name;
            return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Source conversation')));
          }));
      await tester.pumpAndSettle();
      final conversation =
          find.byKey(const Key('home-main-agent-conversation'));
      final tracking = find.byKey(const Key('home-agent-tasks'));
      expect(conversation, findsOneWidget);
      expect(find.byKey(const Key('home-assistant-input')), findsOneWidget);
      expect(find.byKey(const Key('home-primary-sessions')), findsNothing);
      expect(find.text('Assistant'), findsOneWidget);
      expect(find.descendant(of: tracking, matching: find.text('Tasks')),
          findsOneWidget);
      expect(find.text('Review release'), findsOneWidget);
      expect(find.text('Search shipped'), findsNothing);
      expect(find.textContaining('Archived work'), findsNothing);
      expect(find.text('Work progress'), findsNothing);
      expect(find.text('Recently tracked'), findsNothing);
      final statusFilter = find.byKey(const Key('home-task-status-filter'));
      await tester.ensureVisible(statusFilter);
      await tester.tap(statusFilter);
      await tester.pumpAndSettle();
      await tester.tap(find
          .byKey(const ValueKey(('task-status-filter-option', 'completed'))));
      await tester.pumpAndSettle();
      expect(find.text('Search shipped'), findsOneWidget);
      expect(find.text('Review release'), findsNothing);
      expect(tester.getBottomLeft(conversation).dy,
          lessThan(tester.getTopLeft(tracking).dy));
      if (width >= 760) {
        expect(tester.getSize(conversation).width,
            greaterThan(tester.getSize(tracking).width));
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Search shipped'));
      await tester.tap(find.text('Search shipped'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open conversation'));
      await tester.tap(find.text('Open conversation'));
      await tester.pumpAndSettle();
      expect(openedRoute, AppRoutes.session('alpha', 'session-2'));
      expect(find.text('Source conversation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    client.dispose();
  });

  testWidgets('home mobile shows recent sessions before recent projects',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'alpha',
                  name: 'Alpha',
                  updatedAt: '2026-05-05T15:00:00.000',
                ),
                _projectJson(
                  id: 'beta',
                  name: 'Beta',
                  updatedAt: '2026-05-05T14:00:00.000',
                ),
                _projectJson(
                  id: 'gamma',
                  name: 'Gamma',
                  updatedAt: '2026-05-05T13:00:00.000',
                ),
                _projectJson(
                  id: 'delta',
                  name: 'Delta',
                  updatedAt: '2026-05-05T12:00:00.000',
                ),
                _projectJson(
                  id: 'epsilon',
                  name: 'Epsilon',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-1',
                  projectId: 'alpha',
                  title: 'Session One',
                  updatedAt: '2026-05-05T11:30:00.000',
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
    await _openHistory(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    final sessionsTitle = find.text(l10n.recentSessionsTitle);
    final projectsTitle = find.text('Recent projects');

    expect(sessionsTitle, findsOneWidget);
    expect(
      tester.getTopLeft(sessionsTitle).dy,
      lessThan(tester.getTopLeft(projectsTitle).dy),
    );
    expect(find.text('Recent projects'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Epsilon'), findsNothing);
  });

  testWidgets('home search filters both projects and sessions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-1',
                  projectId: 'alpha',
                  title: 'Fix compile error',
                  updatedAt: '2026-05-05T11:30:00.000',
                  preview: 'Investigate analyzer output',
                ),
                _sessionJson(
                  id: 'session-2',
                  projectId: 'beta',
                  title: 'Review PR',
                  updatedAt: '2026-05-05T12:30:00.000',
                  preview: 'Check beta release notes',
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
    await _openHistory(tester);

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'beta');

    expect(find.text('Alpha'), findsAtLeastNWidgets(1));
    expect(find.text('Fix compile error'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 299));

    expect(find.text('Alpha'), findsAtLeastNWidgets(1));
    expect(find.text('Fix compile error'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Beta'), findsAtLeastNWidgets(1));
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Review PR'), findsOneWidget);
    expect(find.text('Fix compile error'), findsNothing);
  });

  testWidgets('home search caps visible results and can load more sessions',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'alpha',
                  name: 'Match Alpha',
                  updatedAt: '2026-05-05T15:00:00.000',
                ),
                _projectJson(
                  id: 'beta',
                  name: 'Match Beta',
                  updatedAt: '2026-05-05T14:00:00.000',
                ),
                _projectJson(
                  id: 'gamma',
                  name: 'Match Gamma',
                  updatedAt: '2026-05-05T13:00:00.000',
                ),
                _projectJson(
                  id: 'delta',
                  name: 'Match Delta',
                  updatedAt: '2026-05-05T12:00:00.000',
                ),
                _projectJson(
                  id: 'epsilon',
                  name: 'Match Epsilon',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                for (var i = 6; i >= 1; i--)
                  _sessionJson(
                    id: 'match-session-$i',
                    projectId: 'alpha',
                    title: 'Match Session $i',
                    updatedAt: '2026-05-05T${10 + i}:00:00.000',
                    preview: 'Match Preview $i',
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
    await _openHistory(tester);

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'match');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Match Session 6'), findsOneWidget);
    expect(find.text('Match Session 5'), findsOneWidget);
    expect(find.text('Match Session 4'), findsOneWidget);
    expect(find.text('Match Session 3'), findsOneWidget);
    expect(find.text('Match Session 2'), findsOneWidget);
    expect(find.text('Match Session 1'), findsNothing);

    expect(find.text('Match Alpha'), findsOneWidget);
    expect(find.text('Match Beta'), findsOneWidget);
    expect(find.text('Match Gamma'), findsOneWidget);
    expect(find.text('Match Delta'), findsOneWidget);
    expect(find.text('Match Epsilon'), findsNothing);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    final loadMore = find.text(l10n.loadMoreSessionsLabel);
    expect(loadMore, findsOneWidget);

    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Match Session 1'), findsOneWidget);
  });

  testWidgets('history search aligns with content width', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-1',
                  projectId: 'alpha',
                  title: 'Session One',
                  updatedAt: '2026-05-05T11:30:00.000',
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
    await _openHistory(tester);

    final searchField = find.byKey(const Key('home-dashboard-search-field'));
    final featuredCard = find.byKey(const Key('home-history-projects'));

    expect(searchField, findsOneWidget);
    expect(featuredCard, findsOneWidget);

    final searchRect = tester.getRect(searchField);
    final featuredRect = tester.getRect(featuredCard);

    expect(searchRect.left, equals(featuredRect.left));
    expect(searchRect.right, equals(featuredRect.right));
  });

  testWidgets('home recent project row can start a new session directly',
      (tester) async {
    var projectRequests = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/projects') {
          projectRequests += 1;
          return http.Response(
            jsonEncode({
              'data': [
                _projectJson(
                  id: 'alpha',
                  name: 'Alpha',
                  updatedAt: '2026-05-05T11:00:00.000',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-1',
                  projectId: 'alpha',
                  title: 'Session One',
                  updatedAt: '2026-05-05T11:30:00.000',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'codex',
                  'label': 'Codex',
                  'aliases': ['codex'],
                  'selectable': true,
                  'default_selected': true,
                  'compatible_formats': ['codex'],
                  'installed': true,
                  'installed_path': '/usr/local/bin/codex',
                  'install_hint': 'manual',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [],
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
    await _openHistory(tester);

    await tester
        .ensureVisible(find.byKey(const Key('home-project-new-session-alpha')));
    await tester.tap(find.byKey(const Key('home-project-new-session-alpha')));
    await tester.pumpAndSettle();

    expect(projectRequests, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(2));
  });

  for (final width in [390.0, 1400.0]) {
    for (final order in [
      ['main', 'sessions', 'tasks'],
      ['sessions', 'tasks', 'main'],
      ['tasks', 'main', 'sessions'],
    ]) {
      testWidgets(
          'home sections reveal independently in order $order at width $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var gates = {
          for (final section in [
            'projects',
            'profiles',
            'main',
            'sessions',
            'tasks'
          ])
            section: Completer<void>()
        };
        final requested = <String>{};
        Future<http.Response> respond(String section, dynamic data) async {
          requested.add(section);
          await gates[section]!.future;
          return http.Response(jsonEncode({'data': data}), 200,
              headers: {'content-type': 'application/json'});
        }

        final client =
            BridgeClient(httpClient: _FakeHttpClient((request) async {
          switch (request.url.path) {
            case '/projects':
              return respond('projects', [
                _projectJson(
                    id: 'project-1',
                    name: 'Project One',
                    updatedAt: '2026-11-16T10:00:00Z')
              ]);
            case '/v2/codex/profiles':
              return respond('profiles', []);
            case '/v2/sessions':
              return respond('sessions', [
                _sessionJson(
                    id: 'session-1',
                    projectId: 'project-1',
                    title: 'Ready conversation',
                    updatedAt: '2026-11-16T10:00:00Z')
              ]);
            case '/settings':
              return respond('main', {'model_providers': []});
            case '/workspace-agent/model':
              return respond('main', {'selection': null});
            case '/workspace-agent/dispatch/settings':
              return respond('main', {'agent': 'pi'});
            case '/workspace-agent':
              return respond('tasks', {
                'scope': {},
                'selected_sessions': 1,
                'cached_sessions': 1,
                'running': false,
                'errors': {},
                'chat': [],
                'tasks': [
                  {
                    'session_id': 'session-1',
                    'project_id': 'project-1',
                    'session_title': 'Ready conversation',
                    'task': {
                      'id': 'task-1',
                      'title': 'Ready task',
                      'summary': 'Continue the work',
                      'status': 'pending'
                    }
                  }
                ]
              });
            default:
              return http.Response(
                  jsonEncode({
                    'data': {'running': false}
                  }),
                  200);
          }
        }));
        await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(requested,
            containsAll(['projects', 'profiles', 'main', 'sessions', 'tasks']));
        const skeletonKeys = {
          'main': 'home-main-agent-skeleton',
          'sessions': 'home-recent-skeleton',
          'tasks': 'home-tasks-skeleton',
        };
        for (final key in skeletonKeys.values) {
          expect(find.byKey(Key(key)), findsOneWidget);
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final main = find.byKey(const Key('home-main-agent-conversation'));
        final sessions = find.byKey(const Key('home-recent-sessions'));
        final tasks = find.byKey(const Key('home-agent-tasks'));
        expect(tester.getBottomLeft(main).dy,
            lessThan(tester.getTopLeft(sessions).dy));
        if (width > 760) {
          expect(find.byType(DesktopNavigationSidebar), findsOneWidget);
          expect(tester.getTopLeft(sessions).dy, tester.getTopLeft(tasks).dy);
        } else {
          expect(tester.getTopLeft(sessions).dy,
              lessThan(tester.getTopLeft(tasks).dy));
        }
        final ready = <String>{};
        for (final section in order) {
          gates[section]!.complete();
          ready.add(section);
          await tester.pumpAndSettle();
          for (final entry in skeletonKeys.entries) {
            expect(find.byKey(Key(entry.value)),
                ready.contains(entry.key) ? findsNothing : findsOneWidget);
          }
          expect(find.byKey(const Key('home-assistant-input')),
              ready.contains('main') ? findsOneWidget : findsNothing);
          expect(find.text('Ready conversation'),
              ready.contains('sessions') ? findsOneWidget : findsNothing);
          expect(find.text('Ready task'),
              ready.contains('tasks') ? findsOneWidget : findsNothing);
          expect(tester.takeException(), isNull);
        }
        // Project and profile metadata are still pending after all three panes are usable.
        expect(gates['projects']!.isCompleted, isFalse);
        expect(gates['profiles']!.isCompleted, isFalse);
        await tester.enterText(
            find.byKey(const Key('home-assistant-input')), 'Keep this draft');
        gates['projects']!.complete();
        gates['profiles']!.complete();
        await tester.pumpAndSettle();
        // Refreshes retain ready content while each request completes again.
        gates = {for (final section in gates.keys) section: Completer<void>()};
        final refresh = find.descendant(
            of: sessions, matching: find.byIcon(Icons.refresh_rounded));
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pump(const Duration(milliseconds: 50));
        for (final key in skeletonKeys.values) {
          expect(find.byKey(Key(key)), findsNothing);
        }
        expect(find.text('Ready conversation'), findsOneWidget);
        expect(find.text('Ready task'), findsOneWidget);
        expect(
            tester
                .widget<TextField>(
                    find.byKey(const Key('home-assistant-input')))
                .controller!
                .text,
            'Keep this draft');
        for (final gate in gates.values) {
          gate.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        client.dispose();
      });
    }
  }

  testWidgets(
      'empty sections finish while project metadata fails and profiles wait',
      (tester) async {
    final profiles = Completer<http.Response>();
    final client = BridgeClient(httpClient: _FakeHttpClient((request) async {
      dynamic data;
      switch (request.url.path) {
        case '/projects':
          return http.Response(
              jsonEncode({'error': 'project catalog unavailable'}), 500);
        case '/v2/codex/profiles':
          return profiles.future;
        case '/v2/sessions':
          data = [];
        case '/settings':
          data = {'model_providers': []};
        case '/workspace-agent':
          data = {
            'scope': {},
            'tasks': [],
            'selected_sessions': 0,
            'cached_sessions': 0,
            'running': false,
            'errors': {}
          };
        default:
          data = {'selection': null, 'agent': 'pi', 'running': false};
      }
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(_TestApp(home: HomeScreen(client: client)));
    await tester.pumpAndSettle();
    for (final key in [
      'home-main-agent-skeleton',
      'home-recent-skeleton',
      'home-tasks-skeleton'
    ]) {
      expect(find.byKey(Key(key)), findsNothing);
    }
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    expect(find.byKey(const Key('home-assistant-input')), findsOneWidget);
    expect(find.text(l10n.noSessionsYet), findsOneWidget);
    expect(find.text('Nothing pending. A little space for your next idea.'),
        findsOneWidget);
    expect(find.textContaining('project catalog unavailable'), findsOneWidget);
    profiles.complete(http.Response(jsonEncode({'data': []}), 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('home exposes bridge settings when the configured bridge fails',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        throw Exception('bridge unavailable');
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: HomeScreen(client: client),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.settings) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => SettingsScreen(client: client),
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
    final changeBridge = find.text(l10n.changeBridge);
    expect(changeBridge, findsOneWidget);

    await tester.tap(changeBridge);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('saving a new bridge connects and returns home for authorization',
      (tester) async {
    const nextUrl = 'http://10.0.0.8:8787';
    var newBridgeRequests = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.url.path == '/projects') {
          if (request.url == Uri.parse('$nextUrl/projects')) {
            newBridgeRequests++;
            return http.Response('unauthorized', 401);
          }
          throw http.ClientException('bridge unavailable');
        }
        return http.Response(
          jsonEncode({
            'data': {'model_providers': [], 'prompt': ''},
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      _TestApp(
        home: HomeScreen(client: client),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.settings) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => SettingsScreen(client: client),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    await tester.tap(find.text(l10n.changeBridge));
    await tester.pumpAndSettle();

    final bridgeUrl = find.byKey(const Key('settings-bridge-url'));
    await tester.ensureVisible(bridgeUrl);
    await tester.enterText(bridgeUrl, nextUrl);
    await tester.ensureVisible(find.text(l10n.save));
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(newBridgeRequests, 1);
    expect(appSettingsController.settings.bridgeUrl, nextUrl);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text(l10n.authorizeThisDevice), findsOneWidget);
    final connectBridgeField = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(connectBridgeField).controller?.text,
      nextUrl,
    );
    expect(find.textContaining('Failed to save settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'home focuses on main agent chat and preserves drafts through history',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-1',
                  projectId: 'alpha',
                  title: 'Session One',
                  updatedAt: '2026-05-05T11:30:00.000',
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

    expect(find.byType(DesktopNavigationSidebar), findsOneWidget);
    expect(find.byKey(const Key('home-navigation-button')), findsNothing);
    expect(
        find.byKey(const Key('home-main-agent-conversation')), findsOneWidget);
    expect(find.byKey(const Key('home-agent-tasks')), findsOneWidget);
    expect(find.byKey(const Key('home-assistant-input')), findsOneWidget);
    expect(find.text('Recent projects'), findsNothing);
    expect(find.text('Session One'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Keep this draft');
    await _openHistory(tester);
    expect(find.byType(DesktopNavigationSidebar), findsOneWidget);
    expect(find.text('Session One'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-history-button')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('home-main-agent-conversation')), findsOneWidget);
    expect(find.text('Session One'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('home-assistant-input')))
            .controller!
            .text,
        'Keep this draft');
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

  testWidgets('projects screen shows drawer menu button on mobile',
      (tester) async {
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
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(_TestApp(home: ProjectsScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
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
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
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
    await _openHistory(tester);

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

  testWidgets('home shows fork source for forked sessions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'child-session',
                  projectId: 'project-1',
                  title: 'Child Session',
                  updatedAt: '2026-05-05T12:00:00.000',
                  forkedFromSessionId: 'parent-session',
                ),
                _sessionJson(
                  id: 'parent-session',
                  projectId: 'project-1',
                  title: 'Parent Session',
                  updatedAt: '2026-05-05T11:00:00.000',
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
    await _openHistory(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    expect(
      find.text(l10n.forkedFromSession('Parent Session')),
      findsOneWidget,
    );
  });

  testWidgets('home refresh keeps expanded recent session count',
      (tester) async {
    var sessionsRequestCount = 0;
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          sessionsRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': [
                for (var i = 7; i >= 1; i--)
                  _sessionJson(
                    id: 'session-$i',
                    projectId: 'project-1',
                    title: 'Session $i',
                    updatedAt: '2026-05-05T${10 + i}:00:00.000',
                    preview: 'Refresh $sessionsRequestCount · Preview $i',
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
    await _openHistory(tester);

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

    final refreshButton = find.byIcon(Icons.refresh_rounded).last;
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sessionsRequestCount, 2);
    expect(find.text('Session 2'), findsOneWidget);
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);
  });

  testWidgets('home refreshes recent sessions when app resumes after throttle',
      (tester) async {
    final binding = tester.binding;
    final now = _FakeNow(DateTime(2026, 5, 10, 9, 0, 0));
    var sessionsRequestCount = 0;
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          sessionsRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-$sessionsRequestCount',
                  projectId: 'project-1',
                  title: 'Session $sessionsRequestCount',
                  updatedAt: '2026-05-05T13:00:00.000',
                  preview: 'Latest $sessionsRequestCount',
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
      _TestApp(home: HomeScreen(client: client, now: now.call)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _openHistory(tester);

    expect(sessionsRequestCount, 1);
    expect(find.text('Session 1'), findsOneWidget);

    now.advance(const Duration(seconds: 16));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sessionsRequestCount, 2);
    expect(find.text('Session 2'), findsOneWidget);
  });

  testWidgets('home refresh keeps expanded recent sessions visible',
      (tester) async {
    var sessionsRequestCount = 0;
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          sessionsRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': [
                for (var i = 7; i >= 1; i--)
                  _sessionJson(
                    id: 'session-$i',
                    projectId: 'project-1',
                    title: sessionsRequestCount == 1
                        ? 'Session $i'
                        : 'Refreshed Session $i',
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
    await _openHistory(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomeScreen)),
    )!;
    final loadMore = find.text(l10n.loadMoreSessionsLabel);

    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Session 2'), findsOneWidget);
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);

    final refreshButton = find.byIcon(Icons.refresh_rounded).last;
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sessionsRequestCount, 2);
    expect(find.text('Refreshed Session 2'), findsOneWidget);
    expect(find.text('Refreshed Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);
  });

  testWidgets('home skips resumed refresh inside throttle window',
      (tester) async {
    final binding = tester.binding;
    final now = _FakeNow(DateTime(2026, 5, 10, 9, 0, 0));
    var sessionsRequestCount = 0;
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
          sessionsRequestCount += 1;
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  id: 'session-$sessionsRequestCount',
                  projectId: 'project-1',
                  title: 'Session $sessionsRequestCount',
                  updatedAt: '2026-05-05T13:00:00.000',
                  preview: 'Latest $sessionsRequestCount',
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
      _TestApp(home: HomeScreen(client: client, now: now.call)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _openHistory(tester);

    expect(sessionsRequestCount, 1);
    expect(find.text('Session 1'), findsOneWidget);

    now.advance(const Duration(seconds: 10));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sessionsRequestCount, 1);
    expect(find.text('Session 1'), findsOneWidget);
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
        if (request.method == 'GET' && request.url.path == '/v2/sessions') {
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
    await _openHistory(tester);

    await tester.ensureVisible(find.text('Session A'));
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

Future<void> _openHistory(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('home-history-button')));
  await tester.tap(find.byKey(const Key('home-history-button')));
  await tester.pumpAndSettle();
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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
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

class _FakeNow {
  _FakeNow(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
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
  String? forkedFromSessionId,
  String? reasoningEffort,
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
    'forked_from_session_id': forkedFromSessionId,
    'reasoning_effort': reasoningEffort,
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
                agentId: 'codex',
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
