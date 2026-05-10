import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/screens/speech_settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('shows Linux system speech availability hints', (tester) async {
    await tester.pumpWidget(
      const _TestApp(
        home: SpeechSettingsScreen(
          debugPlatformOverride: TargetPlatform.linux,
          debugIsWebOverride: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'System TTS is not available on Linux yet. Choose a cloud provider to enable playback.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'System ASR is not available on Linux yet. Choose a cloud provider to enable voice input.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'uses the same value text style for speech dropdowns and text fields',
    (tester) async {
      await tester.pumpWidget(
        const _TestApp(
          home: SpeechSettingsScreen(),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      final dropdown = tester.widget<DropdownButton<TtsProvider>>(
        find
            .byWidgetPredicate(
              (widget) => widget is DropdownButton<TtsProvider>,
            )
            .first,
      );

      expect(textField.style, isNotNull);
      expect(dropdown.style, equals(textField.style));
    },
  );

  testWidgets('shows Tencent Cloud streaming ASR as a provider option',
      (tester) async {
    await tester.pumpWidget(
      const _TestApp(
        home: SpeechSettingsScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('System').last);
    await tester.pumpAndSettle();

    expect(find.text('Tencent Cloud Streaming'), findsOneWidget);
  });

  testWidgets('shows Tencent Cloud credential fields',
      (tester) async {
    await tester.pumpWidget(
      const _TestApp(
        home: SpeechSettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(TextField, 'App ID'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Secret ID'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Secret Key'), findsOneWidget);
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
