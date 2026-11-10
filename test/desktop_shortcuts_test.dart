import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/keyboard_shortcuts_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/shortcuts/app_desktop_shortcuts.dart';
import 'package:omni_code/src/shortcuts/desktop_search_dialog.dart';
import 'package:omni_code/src/shortcuts/desktop_shortcut.dart';
import 'package:omni_code/src/shortcuts/shortcut_recorder_dialog.dart';
import 'package:omni_code/src/widgets/new_session_flow.dart';
import 'package:omni_code/src/widgets/desktop_navigation_sidebar.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/shortcuts/shortcut_keycaps.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  late _MemoryStore store;
  late BridgeClient client;

  setUp(() async {
    store = _MemoryStore();
    appSettingsController.debugReplaceStore(store);
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    client = BridgeClient(httpClient: MockClient((request) async {
      final data = request.url.path == '/projects'
          ? [
              {
                'id': 'p1',
                'name': 'Project Alpha',
                'root_path': '/work/alpha',
                'updated_at': '2026-11-07T10:00:00Z',
                'session_count': 1
              },
            ]
          : [
              {
                'id': 's1',
                'project_id': 'p1',
                'title': 'Fix keyboard navigation',
                'agent': 'codex',
                'status': 'idle',
                'updated_at': '2026-11-07T10:00:00Z',
                'unread_count': 0
              },
            ];
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'});
    }));
    // Load HTTP fixtures before entering the widget test's fake clock.
    await Future.wait([client.listProjects(), client.listSessions()]);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('platform defaults use Ctrl or Cmd and have no collisions', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final search = defaultDesktopShortcut(DesktopShortcutAction.search);
      expect(search.key, LogicalKeyboardKey.keyP);
      expect(search.meta, platform == TargetPlatform.macOS);
      expect(search.control, platform != TargetPlatform.macOS);
      expect(defaultDesktopShortcut(DesktopShortcutAction.newWindow).key,
          LogicalKeyboardKey.keyN);
      for (final action in [
        DesktopShortcutAction.previousSession,
        DesktopShortcutAction.nextSession,
      ]) {
        final binding = defaultDesktopShortcut(action);
        expect(
            binding.key,
            action == DesktopShortcutAction.previousSession
                ? LogicalKeyboardKey.arrowUp
                : LogicalKeyboardKey.arrowDown);
        expect(binding.alt, isTrue);
        expect(binding.meta, platform == TargetPlatform.macOS);
        expect(binding.control, platform != TargetPlatform.macOS);
      }
      final defaults =
          DesktopShortcutAction.values.map(defaultDesktopShortcut).toSet();
      expect(defaults.length, DesktopShortcutAction.values.length);
      expect(defaults.every((binding) => binding.isValid), isTrue);
    }
  });

  test('old and malformed settings keep usable defaults', () {
    expect(AppSettings.fromJson({}).desktopShortcuts, isEmpty);
    final settings = AppSettings.fromJson({
      'desktop_shortcuts': {
        'search': {'key_id': LogicalKeyboardKey.keyP.keyId},
        'newWindow': {'key_id': -1, 'control': true},
        'settings': {'key_id': LogicalKeyboardKey.keyK.keyId, 'control': 'yes'},
        'home': null,
        'futureAction': {},
      }
    });
    expect(settings.desktopShortcuts, {DesktopShortcutAction.home: null});
    expect(
        resolveDesktopShortcut(
            settings.desktopShortcuts, DesktopShortcutAction.search),
        defaultDesktopShortcut(DesktopShortcutAction.search));
  });

  test('custom and disabled shortcuts survive controller save and reload',
      () async {
    final controller = AppSettingsController()..debugReplaceStore(store);
    const binding =
        DesktopKeyBinding(LogicalKeyboardKey.keyK, control: true, shift: true);
    await controller.save(AppSettings.defaults().copyWith(desktopShortcuts: {
      DesktopShortcutAction.search: binding,
      DesktopShortcutAction.newWindow: null,
    }).copyWith(appLanguage: 'zh'));
    final restored = AppSettingsController()..debugReplaceStore(store);
    await restored.load();
    expect(restored.settings.desktopShortcuts, {
      DesktopShortcutAction.search: binding,
      DesktopShortcutAction.newWindow: null
    });
    expect(restored.settings.appLanguage, 'zh');
    expect(jsonDecode(store.value!)['desktop_shortcuts']['newWindow'], isNull);
  });

  _desktopTestWidgets(
      'search opens from a focused editor, navigates by keyboard and filters',
      (tester) async {
    await tester.pumpWidget(_TestApp(client: client));
    await tester.tap(find.byKey(const Key('editor')));
    await _chord(tester, LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSearchDialog), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSearchDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).last.selected,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('route:/projects/p1/s1'), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('desktop-search-field')), 'alpha');
    await tester.pump();
    expect(find.text('Project Alpha'), findsWidgets);
    await tester.enterText(
        find.byKey(const Key('desktop-search-field')), 'no-such-result');
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSearchDialog), findsNothing);
  });

  _desktopTestWidgets(
      'new window ignores repeat and extra modifiers, and respects remapping and disable',
      (tester) async {
    var windows = 0;
    await tester.pumpWidget(_TestApp(
        client: client,
        openWindow: () async {
          windows++;
        }));
    await tester.tap(find.byKey(const Key('editor')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(windows, 1);
    await appSettingsController
        .save(appSettingsController.settings.copyWith(desktopShortcuts: {
      DesktopShortcutAction.newWindow:
          const DesktopKeyBinding(LogicalKeyboardKey.keyM, control: true),
    }));
    await _chord(tester, LogicalKeyboardKey.keyN);
    expect(windows, 1);
    await _chord(tester, LogicalKeyboardKey.keyM, alt: true);
    expect(windows, 1);
    await _chord(tester, LogicalKeyboardKey.keyM);
    expect(windows, 2);
    await appSettingsController.save(appSettingsController.settings
        .copyWith(desktopShortcuts: {DesktopShortcutAction.newWindow: null}));
    await _chord(tester, LogicalKeyboardKey.keyM);
    await _chord(tester, LogicalKeyboardKey.keyN);
    expect(windows, 2);
  });

  _desktopTestWidgets(
      'settings, projects, home, back, sidebar and new session actions work',
      (tester) async {
    await tester.pumpWidget(_TestApp(client: client));
    await _chord(tester, LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(find.text('route:/settings'), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyP, shift: true);
    await tester.pumpAndSettle();
    expect(find.text('route:/projects'), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(appSettingsController.settings.desktopNavigationCollapsed, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('route:/'), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyH, shift: true);
    await tester.pumpAndSettle();
    expect(find.text('route:/'), findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyN, shift: true);
    await tester.pumpAndSettle();
    expect(find.byType(SelectProjectDialog), findsOneWidget);
  });

  _desktopTestWidgets(
      'recording blocks commands, rejects conflicts, saves, disables and resets',
      (tester) async {
    var windows = 0;
    await tester.pumpWidget(_TestApp(
        client: client,
        shortcutsPage: true,
        openWindow: () async {
          windows++;
        }));
    await tester.tap(find.byKey(const Key('shortcut-edit-search')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(find.text('Use a modifier with a key, or a function key (F1–F24).'),
        findsOneWidget);
    await _chord(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(windows, 0);
    expect(find.text('This shortcut is already assigned to New window.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull);
    await _chord(tester, LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutRecorderDialog), findsNothing);
    expect(
        appSettingsController
            .settings.desktopShortcuts[DesktopShortcutAction.search]?.key,
        LogicalKeyboardKey.keyK);
    final restored = AppSettingsController()..debugReplaceStore(store);
    await restored.load();
    expect(restored.settings.desktopShortcuts,
        appSettingsController.settings.desktopShortcuts);
    await _chord(tester, LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.byType(DesktopSearchDialog), findsNothing);
    await _chord(tester, LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSearchDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-disable-search')));
    await tester.pumpAndSettle();
    expect(
        appSettingsController.settings.desktopShortcuts
            .containsKey(DesktopShortcutAction.search),
        isTrue);
    expect(
        appSettingsController
            .settings.desktopShortcuts[DesktopShortcutAction.search],
        isNull);
    await tester.tap(find.byKey(const Key('shortcut-reset-search')));
    await tester.pumpAndSettle();
    expect(appSettingsController.settings.desktopShortcuts, isEmpty);
  });

  _desktopTestWidgets('failed save preserves the previous shortcut',
      (tester) async {
    await tester.pumpWidget(_TestApp(client: client, shortcutsPage: true));
    store.failWrites = true;
    await tester.tap(find.byKey(const Key('shortcut-disable-search')));
    await tester.pumpAndSettle();
    expect(appSettingsController.settings.desktopShortcuts, isEmpty);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  _desktopTestWidgets(
      'reset checks conflicts and restoring all defaults persists',
      (tester) async {
    await appSettingsController
        .save(appSettingsController.settings.copyWith(desktopShortcuts: {
      DesktopShortcutAction.search:
          defaultDesktopShortcut(DesktopShortcutAction.newWindow),
      DesktopShortcutAction.newWindow: null,
    }));
    await tester.pumpWidget(_TestApp(client: client, shortcutsPage: true));
    await tester.tap(find.byKey(const Key('shortcut-reset-newWindow')));
    await tester.pumpAndSettle();
    expect(find.text('This shortcut is already assigned to Open search.'),
        findsOneWidget);
    expect(
        appSettingsController
            .settings.desktopShortcuts[DesktopShortcutAction.newWindow],
        isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Restore all defaults'), 300);
    await tester.tap(find.text('Restore all defaults'));
    await tester.pumpAndSettle();
    final restored = AppSettingsController()..debugReplaceStore(store);
    await restored.load();
    expect(restored.settings.desktopShortcuts, isEmpty);
    expect(
        resolveDesktopShortcut(restored.settings.desktopShortcuts,
            DesktopShortcutAction.newWindow),
        defaultDesktopShortcut(DesktopShortcutAction.newWindow));
  });

  _desktopTestWidgets(
      'visible hints follow remapping and sidebar buttons open their actions and guide',
      (tester) async {
    var windows = 0;
    await tester.pumpWidget(_TestApp(
      client: client,
      openWindow: () async {
        windows++;
      },
      home: Scaffold(
          body: SizedBox(
              width: 232,
              child: DesktopNavigationSidebar(
                activeRoute: AppRouteKind.home,
                onNavigateHome: () {},
                onNavigateProjects: () {},
                onNavigateSettings: () {},
                onNewSession: () {},
              ))),
    ));
    final search = find.byKey(const Key('navigation-open-search'));
    List<String> hintLabels() => tester
        .widget<ShortcutKeycaps>(
            find.descendant(of: search, matching: find.byType(ShortcutKeycaps)))
        .labels;
    expect(hintLabels(), ['Ctrl', 'P']);
    await appSettingsController
        .save(appSettingsController.settings.copyWith(desktopShortcuts: {
      DesktopShortcutAction.search:
          const DesktopKeyBinding(LogicalKeyboardKey.keyK, control: true),
    }));
    await tester.pump();
    expect(hintLabels(), ['Ctrl', 'K']);
    expect(find.byTooltip('Open search · Ctrl+K'), findsOneWidget);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSearchDialog), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await appSettingsController.save(appSettingsController.settings
        .copyWith(desktopShortcuts: {DesktopShortcutAction.search: null}));
    await tester.pump();
    expect(find.descendant(of: search, matching: find.byType(ShortcutKeycaps)),
        findsNothing);
    await tester.tap(find.byKey(const Key('navigation-new-window')));
    expect(windows, 1);
    await tester.tap(find.byKey(const Key('navigation-shortcut-guide')));
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsScreen), findsOneWidget);
    expect(find.text('Search & create'), findsOneWidget);
  });

  _desktopTestWidgets(
      'shortcut guide fits narrow windows in both themes and languages',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appSettingsController
        .save(appSettingsController.settings.copyWith(desktopShortcuts: {
      DesktopShortcutAction.search: const DesktopKeyBinding(
          LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
          alt: true,
          meta: true),
    }));
    for (final brightness in Brightness.values) {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        await tester.pumpWidget(_TestApp(
            client: client,
            shortcutsPage: true,
            brightness: brightness,
            locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('shortcut-edit-search')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    }
  });

  _desktopTestWidgets(
      'macOS Cmd shortcut works and mobile leaves app shortcuts disabled',
      (tester) async {
    var windows = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_TestApp(
        client: client,
        openWindow: () async {
          windows++;
        }));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(windows, 1);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _chord(tester, LogicalKeyboardKey.keyN);
    expect(windows, 1);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });
}

void _desktopTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, callback,
      variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false, bool alt = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

class _TestApp extends StatefulWidget {
  const _TestApp(
      {required this.client,
      this.openWindow,
      this.shortcutsPage = false,
      this.home,
      this.locale = const Locale('en'),
      this.brightness = Brightness.light});
  final BridgeClient client;
  final Future<void> Function()? openWindow;
  final bool shortcutsPage;
  final Widget? home;
  final Locale locale;
  final Brightness brightness;
  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _observer = DesktopShortcutNavigatorObserver();
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: [_observer],
        locale: widget.locale,
        theme: widget.brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (context, child) => AppDesktopShortcuts(
          navigatorKey: _navigatorKey,
          observer: _observer,
          client: widget.client,
          openWindow: widget.openWindow ?? () async {},
          child: child!,
        ),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) =>
                settings.name == KeyboardShortcutsScreen.routeName ||
                        (widget.shortcutsPage && settings.name == '/')
                    ? const KeyboardShortcutsScreen()
                    : (settings.name == '/' ? widget.home : null) ??
                        Scaffold(
                            body: Column(children: [
                          Text('route:${settings.name}'),
                          const TextField(key: Key('editor')),
                        ]))),
      );
}

class _MemoryStore implements AppSettingsStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrites) throw StateError('disk full');
    value = next;
  }
}
