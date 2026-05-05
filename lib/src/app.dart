import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/generated/app_localizations.dart';
import 'l10n/app_locale.dart';
import 'models.dart';
import 'screens/project_detail_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/session_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'settings/app_settings.dart';

class OmniCodeApp extends StatefulWidget {
  const OmniCodeApp({super.key});

  @override
  State<OmniCodeApp> createState() => _OmniCodeAppState();
}

class _OmniCodeAppState extends State<OmniCodeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notificationService.flushPendingNavigation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        final locale = localeFromSetting(
          appSettingsController.settings.appLanguage,
        );
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          navigatorKey: notificationService.navigatorKey,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF020617),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF38BDF8),
              secondary: Color(0xFF22C55E),
              surface: Color(0xFF0F172A),
            ),
            useMaterial3: true,
          ),
          initialRoute: '/',
          routes: {
            '/': (_) => const SessionListScreen(),
            SettingsScreen.routeName: (_) => const SettingsScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == SessionDetailScreen.routeName) {
              final session = settings.arguments! as SessionSummary;
              return MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: session),
              );
            }
            if (settings.name == ProjectDetailScreen.routeName) {
              final project = settings.arguments! as ProjectSummary;
              return MaterialPageRoute(
                builder: (_) => ProjectDetailScreen(project: project),
              );
            }
            return null;
          },
        );
      },
    );
  }
}
