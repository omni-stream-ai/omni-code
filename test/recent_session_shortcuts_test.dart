import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/session_detail_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/shortcuts/app_desktop_shortcuts.dart';
import 'package:omni_code/src/shortcuts/desktop_shortcut.dart';
import 'package:omni_code/src/shortcuts/recent_session_shortcuts.dart';
import 'package:omni_code/src/widgets/navigation_panel.dart';

void main() {
  late _MemoryStore store;
  setUp(() {
    store = _MemoryStore();
    appSettingsController.debugReplaceStore(store);
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  test('recent navigation filters before limiting to the five visible rows',
      () {
    final sessions = List.generate(9,
        (index) => _session('$index', projectId: index < 3 ? 'other' : 'p1'));
    final visible = visibleRecentSessions(sessions,
        activeProjectId: 'p1', currentProjectOnly: true);
    expect(visible.map((session) => session.id), ['3', '4', '5', '6', '7']);
    expect(
        adjacentRecentSession(visible, activeSessionId: '4', previous: true)
            ?.id,
        '3');
    expect(
        adjacentRecentSession(visible, activeSessionId: '4', previous: false)
            ?.id,
        '5');
    expect(adjacentRecentSession(visible, activeSessionId: '3', previous: true),
        isNull);
    expect(
        adjacentRecentSession(visible, activeSessionId: '7', previous: false),
        isNull);
    expect(
        visibleRecentSessions(sessions,
                activeProjectId: 'p1', currentProjectOnly: false)
            .map((session) => session.id),
        ['0', '1', '2', '3', '4']);
  });

  test('missing current session enters at an edge; empty and single stop', () {
    final visible = [_session('a'), _session('b')];
    expect(
        adjacentRecentSession(visible,
                activeSessionId: 'missing', previous: true)
            ?.id,
        'b');
    expect(
        adjacentRecentSession(visible,
                activeSessionId: 'missing', previous: false)
            ?.id,
        'a');
    for (final previous in [true, false]) {
      expect(
          adjacentRecentSession([], activeSessionId: 'a', previous: previous),
          isNull);
      expect(
          adjacentRecentSession([_session('a')],
              activeSessionId: 'a', previous: previous),
          isNull);
    }
  });

  for (final routeName in ['/projects/p1/b', '/session', null]) {
    testWidgets('session navigation works with focused editor on $routeName',
        (tester) async {
      final app = _TestApp(
          initialSession: _session('b'),
          initialRouteName: routeName,
          sessions: [_session('a'), _session('b'), _session('c')]);
      await tester.pumpWidget(app);
      await tester.tap(find.text('Open session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor')));
      await tester.enterText(find.byKey(const Key('editor')), 'draft');
      await _move(tester, previous: true);
      expect(find.text('active:a'), findsOneWidget);
      expect(
          find.byKey(const Key('navigation-previousSession')), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const Key('navigation-previousSession')))
              .onPressed,
          isNull);
      await _move(tester, previous: true);
      expect(find.text('active:a'), findsOneWidget);
      await _move(tester, previous: false);
      expect(find.text('active:b'), findsOneWidget);
      await _move(tester, previous: false);
      expect(find.text('active:c'), findsOneWidget);
      await _move(tester, previous: false);
      expect(find.text('active:c'), findsOneWidget);
      // Contextual bindings stop applying once the session route is popped.
      Navigator.of(tester.element(find.byKey(const Key('editor')))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Open session'), findsOneWidget);
      await _move(tester, previous: false);
      expect(find.text('Open session'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets(
      'scope changes apply immediately and hints follow actual bindings',
      (tester) async {
    await tester.pumpWidget(_TestApp(initialSession: _session('a'), sessions: [
      _session('a'),
      _session('other', projectId: 'p2'),
      _session('b')
    ]));
    await tester.tap(find.text('Open session'));
    await tester.pumpAndSettle();
    expect(find.text('Session other'), findsNothing);
    expect(find.byTooltip('Next recent session · Ctrl+Alt+↓'), findsOneWidget);
    await _move(tester, previous: false);
    expect(find.text('active:b'), findsOneWidget);
    await appSettingsController.save(appSettingsController.settings
        .copyWith(recentSessionsCurrentProjectOnly: false, desktopShortcuts: {
      DesktopShortcutAction.previousSession:
          const DesktopKeyBinding(LogicalKeyboardKey.keyJ, control: true),
      DesktopShortcutAction.nextSession: null,
    }));
    await tester.pumpAndSettle();
    expect(find.text('Session other'), findsOneWidget);
    expect(find.byTooltip('Previous recent session · Ctrl+J'), findsOneWidget);
    expect(find.byTooltip('Next recent session'), findsOneWidget);
    await _move(tester, previous: true);
    expect(find.text('active:b'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('active:other'), findsOneWidget);
    await _move(tester, previous: false);
    expect(find.text('active:other'), findsOneWidget);
    // Disabling the binding keeps its clickable navigation button useful.
    await tester.tap(find.byKey(const Key('navigation-nextSession')));
    await tester.pumpAndSettle();
    expect(find.text('active:b'), findsOneWidget);
    final restored = AppSettingsController()..debugReplaceStore(store);
    await restored.load();
    expect(restored.settings.desktopShortcuts,
        appSettingsController.settings.desktopShortcuts);
    restored.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('dialogs and covering pages block underlying session shortcuts',
      (tester) async {
    await tester.pumpWidget(_TestApp(
        initialSession: _session('a'),
        sessions: [_session('a'), _session('b')]));
    await tester.tap(find.text('Open session'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(const Key('editor')));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Dialog')));
    await tester.pumpAndSettle();
    await _move(tester, previous: false);
    expect(find.text('Dialog'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('active:a'), findsOneWidget);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covering page'))));
    await tester.pumpAndSettle();
    await _move(tester, previous: false);
    expect(find.text('Covering page'), findsOneWidget);
    Navigator.of(tester.element(find.text('Covering page'))).pop();
    await tester.pumpAndSettle();
    await _move(tester, previous: false);
    expect(find.text('active:b'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('actual session details switch without retaining legacy routes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessions = [_session('a'), _session('b'), _session('c')];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/events')) {
        return http.Response('', 200,
            headers: {'content-type': 'text/event-stream'});
      }
      if (request.url.path.endsWith('/messages')) {
        return http.Response(jsonEncode({'data': []}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('not found', 404);
    }))
      ..debugSeedSessions(sessions);
    await tester.pumpWidget(_TestApp(
        initialSession: sessions.first, sessions: sessions, client: client));
    await tester.tap(find.text('Open session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    String activeSession() => tester
        .widget<SessionDetailScreen>(find.byType(SessionDetailScreen))
        .session
        .id;
    expect(activeSession(), 'a');
    await _move(tester, previous: false, settle: false);
    expect(activeSession(), 'b');
    await _move(tester, previous: false, settle: false);
    expect(activeSession(), 'c');
    await _move(tester, previous: true, settle: false);
    expect(activeSession(), 'b');
    Navigator.of(tester.element(find.byType(SessionDetailScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open session'), findsOneWidget);
    expect(find.byType(SessionDetailScreen, skipOffstage: false), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

SessionSummary _session(String id, {String projectId = 'p1'}) => SessionSummary(
    id: id,
    projectId: projectId,
    title: 'Session $id',
    agentId: 'codex',
    briefReplyMode: false,
    status: SessionStatus.idle,
    updatedAt: DateTime(2026),
    unreadCount: 0);

Future<void> _move(WidgetTester tester,
    {required bool previous, bool settle = true}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(
      previous ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

class _TestApp extends StatefulWidget {
  const _TestApp({
    required this.initialSession,
    required this.sessions,
    this.initialRouteName = '/session',
    this.client,
  });
  final SessionSummary initialSession;
  final List<SessionSummary> sessions;
  final String? initialRouteName;
  final BridgeClient? client;

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = DesktopShortcutNavigatorObserver();

  Widget _sessionPage(SessionSummary session) => Builder(builder: (context) {
        if (widget.client != null) {
          return SessionDetailScreen(
              session: session,
              client: widget.client,
              enableSpeechServices: false);
        }
        void open(SessionSummary target) {
          Navigator.of(context).pushReplacementNamed(
              AppRoutes.session(target.projectId, target.id),
              arguments: target);
        }

        return RecentSessionShortcuts(
          activeProjectId: session.projectId,
          activeSessionId: session.id,
          recentSessions: widget.sessions,
          onOpenSession: open,
          child: Scaffold(
            body: Row(children: [
              SizedBox(
                width: 232,
                child: NavigationPanel(
                  activeRoute: AppRouteKind.session,
                  activeProjectId: session.projectId,
                  activeSessionId: session.id,
                  recentSessions: widget.sessions,
                  showRecentContent: true,
                  showDesktopShortcuts: true,
                  onOpenSession: open,
                  onNavigateHome: () {},
                  onNavigateProjects: () {},
                  onNavigateSettings: () {},
                ),
              ),
              Expanded(
                child: Column(children: [
                  Text('active:${session.id}'),
                  const TextField(key: Key('editor')),
                ]),
              ),
            ]),
          ),
        );
      });

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => AppDesktopShortcuts(
          navigatorKey: navigatorKey,
          observer: observer,
          child: child!,
        ),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => settings.arguments is SessionSummary
              ? _sessionPage(settings.arguments! as SessionSummary)
              : Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: RouteSettings(name: widget.initialRouteName),
                        builder: (_) => _sessionPage(widget.initialSession),
                      ),
                    ),
                    child: const Text('Open session'),
                  ),
                ),
        ),
      );
}

class _MemoryStore implements AppSettingsStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}
