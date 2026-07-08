import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets(
    'uses the same value text style for settings dropdowns and text fields',
    (tester) async {
      await tester.pumpWidget(
        const _TestApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      final dropdown = tester.widget<DropdownButton<String>>(
        find
            .byWidgetPredicate(
              (widget) => widget is DropdownButton<String>,
            )
            .first,
      );

      expect(textField.style, isNotNull);
      expect(dropdown.style, equals(textField.style));
    },
  );

  testWidgets('does not restore target update version from saved settings',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(updateTargetVersion: '0.2.1'),
    );

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    final matchingFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      matchingFields.any(
        (field) => field.controller?.text == '0.2.1',
      ),
      isFalse,
    );
  });

  testWidgets('shows compressed reply max chars instead of notification chars',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(compressAssistantReplyMaxChars: 75),
    );

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Compressed reply max chars'), findsOneWidget);
    expect(find.text('Notification max chars'), findsNothing);

    final matchingFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      matchingFields.any(
        (field) => field.controller?.text == '75',
      ),
      isTrue,
    );
  });

  testWidgets('desktop settings form does not overflow at narrow widths',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('SETTINGS DESK'), findsOneWidget);
  });

  testWidgets('shows an error instead of throwing when bridge sync fails',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SettingsScreen(client: _FailingSettingsBridgeClient()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Failed to save settings'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
  });

  final Widget home;

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
    );
  }
}

class _FailingSettingsBridgeClient extends BridgeClient {
  @override
  Future<void> updateBridgeSettings(
    AppSettings settings, {
    List<ModelProviderConfig>? modelProviders,
  }) async {
    throw Exception('bridge unavailable');
  }
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _body;

  @override
  Future<String?> read() async => _body;

  @override
  Future<void> write(String body) async {
    _body = body;
  }
}
