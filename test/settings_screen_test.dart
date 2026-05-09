import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
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
