import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/widgets/navigation_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NavigationSettingsStore settingsStore;
  setUp(() {
    settingsStore = _NavigationSettingsStore();
    appSettingsController.debugReplaceStore(settingsStore);
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets(
      'sidebar scope filters before taking five and persists after reload',
      (tester) async {
    final sessions = List.generate(
        6,
        (index) => SessionSummary(
              id: 'session-$index',
              projectId: index == 5 ? 'current' : 'other',
              title: 'Session $index',
              agentId: 'codex',
              briefReplyMode: false,
              status: SessionStatus.idle,
              updatedAt: DateTime(2026),
              unreadCount: 0,
            ));
    Widget panel(String? projectId) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: SizedBox(
                  width: 280,
                  child: NavigationPanel(
                    activeRoute: AppRouteKind.project,
                    activeProjectId: projectId,
                    recentSessions: sessions,
                    showRecentContent: true,
                    onNavigateHome: () {},
                    onNavigateProjects: () {},
                    onNavigateSettings: () {},
                  ))),
        );
    await tester.pumpWidget(panel('current'));
    expect(find.text('Session 5'), findsOneWidget);
    expect(find.text('Session 0'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('navigation-recent-session-scope')),
            matching:
                find.byKey(const Key('navigation-recent-session-scope-icon'))),
        findsOneWidget);
    expect(
        tester
            .widget<PopupMenuButton<bool>>(
                find.byKey(const Key('navigation-recent-session-scope')))
            .tooltip,
        contains('Current project'));
    await tester.tap(find.byKey(const Key('navigation-recent-session-scope')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('navigation-session-scope-true')),
            matching: find
                .byKey(const Key('navigation-session-scope-selected-check'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('navigation-session-scope-false')),
            matching: find
                .byKey(const Key('navigation-session-scope-selected-check'))),
        findsNothing);
    await tester.tap(find.byKey(const Key('navigation-session-scope-false')));
    await tester.pumpAndSettle();
    expect(find.text('Session 0'), findsOneWidget);
    expect(find.text('Session 5'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('navigation-recent-session-scope')),
            matching:
                find.byKey(const Key('navigation-recent-session-scope-icon'))),
        findsOneWidget);
    expect(
        tester
            .widget<PopupMenuButton<bool>>(
                find.byKey(const Key('navigation-recent-session-scope')))
            .tooltip,
        contains('All projects'));
    final restarted = AppSettingsController()..debugReplaceStore(settingsStore);
    await restarted.load();
    expect(restarted.settings.recentSessionsCurrentProjectOnly, isFalse);
    await tester.tap(find.byKey(const Key('navigation-recent-session-scope')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('navigation-session-scope-false')),
            matching: find
                .byKey(const Key('navigation-session-scope-selected-check'))),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('navigation-session-scope-true')));
    await tester.pumpAndSettle();
    expect(find.text('Session 5'), findsOneWidget);
    // Home has no current project and remains useful with this default.
    await tester.pumpWidget(panel(null));
    expect(find.text('Session 0'), findsOneWidget);
    restarted.dispose();
  });

  testWidgets(
      'scope icon paints visible pixels in both themes without icon fonts',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: SizedBox(
                width: 240,
                child: NavigationPanel(
                  activeRoute: AppRouteKind.session,
                  onNavigateHome: () {},
                  onNavigateProjects: () {},
                  onNavigateSettings: () {},
                  showRecentContent: true,
                  recentSessions: [
                    SessionSummary(
                      id: 'session',
                      projectId: 'project',
                      title: 'Session',
                      agentId: 'codex',
                      briefReplyMode: false,
                      status: SessionStatus.idle,
                      updatedAt: DateTime(2026),
                      unreadCount: 0,
                    )
                  ],
                ))),
      ));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('navigation-recent-session-scope-icon')));
      final paintedPixels = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          final pixels =
              (await image.toByteData(format: ImageByteFormat.rawRgba))!;
          var visible = 0;
          for (var i = 3; i < pixels.lengthInBytes; i += 4) {
            if (pixels.getUint8(i) > 128) visible++;
          }
          final png = (await image.toByteData(format: ImageByteFormat.png))!;
          await File(
                  '${Directory.systemTemp.path}/omni-code-scope-icon-${brightness.name}.png')
              .writeAsBytes(
                  png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
          return visible;
        } finally {
          image.dispose();
        }
      });
      expect(paintedPixels, greaterThan(30),
          reason: 'The ${brightness.name} icon must contain visible strokes');
    }
  });

  testWidgets('recent navigation shows five items and session menu actions',
      (tester) async {
    final clipboard = <String, Object?>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.addAll(Map<String, Object?>.from(call.arguments as Map));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    var sessionNewSessionCount = 0;
    var projectNewSessionCount = 0;
    final sessions = List.generate(
      6,
      (index) => SessionSummary(
        id: 'session-$index',
        projectId: 'project-1',
        title: 'Session $index',
        agentId: 'codex',
        briefReplyMode: false,
        status: SessionStatus.idle,
        updatedAt: DateTime(2026, 5, 5, 11, index),
        unreadCount: 0,
        runtimeSessionRef: index == 0 ? 'codex-session-ref' : null,
      ),
    );
    final projects = List.generate(
      6,
      (index) => ProjectSummary(
        id: 'project-$index',
        name: 'Project $index',
        rootPath: '/tmp/project-$index',
        updatedAt: DateTime(2026, 5, 5, 10, index),
        sessionCount: index,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: NavigationPanel(
              activeRoute: AppRouteKind.session,
              onNavigateHome: () {},
              onNavigateProjects: () {},
              onNavigateSettings: () {},
              recentSessions: sessions,
              recentProjects: projects,
              showRecentContent: true,
              onOpenSession: (_) {},
              onOpenProject: (_) {},
              onNewSessionForSession: (_) => sessionNewSessionCount += 1,
              onNewSessionForProject: (_) => projectNewSessionCount += 1,
              agentLabelFor: (_) => 'Codex',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Session 0'), findsOneWidget);
    expect(find.text('Session 4'), findsOneWidget);
    expect(find.text('Session 5'), findsNothing);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project 4'), findsOneWidget);
    expect(find.text('Project 5'), findsNothing);

    await tester.ensureVisible(find.text('Session 0'));
    final sessionGesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await sessionGesture.addPointer(
        location: tester.getCenter(find.text('Session 0')));
    await tester.pump();

    await tester.tapAt(_rowMoreButtonPoint(tester, find.text('Session 0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    expect(sessionNewSessionCount, 1);

    await tester.tap(find.text('Copy Codex ID'));
    await tester.pumpAndSettle();
    expect(clipboard['text'], 'codex-session-ref');
    await sessionGesture.removePointer();
    await tester.pump();

    await tester.ensureVisible(find.text('Project 0'));
    final projectGesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await projectGesture.addPointer(
        location: tester.getCenter(find.text('Project 0')));
    await tester.pump();

    await tester.tapAt(_rowMoreButtonPoint(tester, find.text('Project 0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    expect(projectNewSessionCount, 1);

    await projectGesture.removePointer();
  });

  testWidgets('recent menus can stay visible for touch layouts',
      (tester) async {
    var sessionNewSessionCount = 0;
    final sessions = [
      SessionSummary(
        id: 'session-0',
        projectId: 'project-1',
        title: 'Session 0',
        agentId: 'codex',
        briefReplyMode: false,
        status: SessionStatus.idle,
        updatedAt: DateTime(2026, 5, 5, 11),
        unreadCount: 0,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: NavigationPanel(
              activeRoute: AppRouteKind.session,
              onNavigateHome: () {},
              onNavigateProjects: () {},
              onNavigateSettings: () {},
              recentSessions: sessions,
              showRecentContent: true,
              alwaysShowRecentMenus: true,
              onOpenSession: (_) {},
              onNewSessionForSession: (_) => sessionNewSessionCount += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(_rowMoreButtonPoint(tester, find.text('Session 0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();

    expect(sessionNewSessionCount, 1);
  });
}

class _NavigationSettingsStore implements AppSettingsStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

Offset _rowMoreButtonPoint(WidgetTester tester, Finder rowText) {
  final rowCenter = tester.getCenter(rowText.first);
  return Offset(248, rowCenter.dy);
}
