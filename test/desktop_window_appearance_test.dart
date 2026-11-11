import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/shortcuts/desktop_shortcut.dart';
import 'package:omni_code/src/shortcuts/desktop_shortcut_scope.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/desktop_window_appearance.dart';
import 'package:omni_code/src/widgets/navigation_panel.dart';

void main() {
  const channel = MethodChannel('omni_code/window');
  final calls = <MethodCall>[];
  final actions = <DesktopShortcutAction>[];
  var customHeader = false;

  setUp(() {
    calls.clear();
    actions.clear();
    customHeader = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getState') {
        return customHeader ? {'customHeader': true, 'maximized': false} : null;
      }
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget app(ThemeMode mode, {Widget? home}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        builder: (context, child) => DesktopShortcutScope(
          onInvoke: actions.add,
          routeShortcuts: DesktopRouteShortcutRegistry(),
          child: DesktopWindowAppearance(child: child!),
        ),
        home: home ?? const Scaffold(body: Text('Window content')),
      );

  testWidgets('Linux titlebar follows the selected and system themes',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'setAppearance');
    expect(calls.single.arguments, {
      'dark': true,
      'background': '#17181d',
      'foreground': '#9aa9b8',
      'border': '#27313c',
    });

    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));

    await tester.pumpWidget(app(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last.arguments, {
      'dark': false,
      'background': '#ffffff',
      'foreground': '#536170',
      'border': '#cdd6e0',
    });

    await tester.pumpWidget(app(ThemeMode.system));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    expect((calls.last.arguments as Map)['dark'], isTrue);
    expect(find.text('Window content'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('other platforms retain their existing window decorations',
      (tester) async {
    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('Window content'), findsOneWidget);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }));

  testWidgets('Linux previews work when the native channel is unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Window content'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('header search and window buttons do not start a window drag',
      (tester) async {
    customHeader = true;
    await tester.pumpWidget(app(ThemeMode.dark,
        home: Scaffold(
            body: SizedBox(
                width: 232,
                child: NavigationPanel(
                  activeRoute: AppRouteKind.home,
                  onNavigateHome: () {},
                  onNavigateProjects: () {},
                  onNavigateSettings: () {},
                  showDesktopShortcuts: true,
                )))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-window-header')), findsOneWidget);
    expect(find.byKey(const Key('navigation-open-search')), findsNothing);
    expect(find.text('A quieter desk for active sessions.'), findsNothing);
    expect(find.byKey(const Key('navigation-new-window')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-window-search')));
    expect(actions, [DesktopShortcutAction.search]);
    await tester.tap(find.byKey(const Key('desktop-window-navigation')));
    expect(actions,
        [DesktopShortcutAction.search, DesktopShortcutAction.toggleNavigation]);
    for (final action in ['minimize', 'maximize', 'close']) {
      await tester.tap(find.byKey(Key('desktop-window-$action')));
      await tester.pump();
    }
    expect(
        calls
            .where((call) => call.method != 'setAppearance')
            .map((call) => call.method),
        ['minimize', 'toggleMaximize', 'close']);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'blank header supports drag and double click and tracks restore state',
      (tester) async {
    customHeader = true;
    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(140, 22));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();
    await gesture.up();
    expect(calls.where((call) => call.method == 'startDragging'), hasLength(1));
    await tester.tapAt(const Offset(140, 22));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(140, 22));
    await tester.pumpAndSettle();
    expect(
        calls.where((call) => call.method == 'toggleMaximize'), hasLength(1));
    tester.binding.channelBuffers.push(
      'omni_code/window',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('stateChanged', {'maximized': true}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(
        find.descendant(
          of: find.byKey(const Key('desktop-window-maximize')),
          matching: find.byIcon(Icons.filter_none_rounded),
        ),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('integrated header fits narrow and wide windows', (tester) async {
    customHeader = true;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [240.0, 360.0, 600.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpWidget(app(ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-window-close')), findsOneWidget);
      expect(find.text('Window content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}
