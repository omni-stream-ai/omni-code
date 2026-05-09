import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/generated/app_localizations.dart';
import 'app_routes.dart';
import 'bridge_client.dart';
import 'l10n/app_locale.dart';
import 'models.dart';
import 'screens/project_detail_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/speech_settings_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_theme.dart';
import 'settings/app_settings.dart';
import 'widgets/app_skeleton.dart';

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
        final themeMode = switch (appSettingsController.settings.themeMode) {
          AppThemeModeSetting.system => ThemeMode.system,
          AppThemeModeSetting.light => ThemeMode.light,
          AppThemeModeSetting.dark => ThemeMode.dark,
        };
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
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          onGenerateInitialRoutes: _generateInitialRoutes,
          onGenerateRoute: _buildRoute,
          onUnknownRoute: _buildUnknownRoute,
        );
      },
    );
  }

  List<Route<dynamic>> _generateInitialRoutes(String initialRouteName) {
    return <Route<dynamic>>[
      _resolveRoute(RouteSettings(name: initialRouteName)),
    ];
  }

  Route<dynamic> _buildRoute(RouteSettings settings) {
    return _resolveRoute(settings);
  }

  Route<dynamic> _buildUnknownRoute(RouteSettings settings) {
    return _pageRoute(
      settings,
      _RouteStateScreen(
        title: context.l10n.appTitle,
        message: 'Unknown route: ${settings.name ?? AppRoutes.home}',
      ),
    );
  }

  Route<dynamic> _resolveRoute(RouteSettings settings) {
    final arguments = settings.arguments;
    if (settings.name == ProjectDetailScreen.routeName &&
        arguments is ProjectSummary) {
      return _pageRoute(
        settings,
        ProjectDetailScreen(project: arguments),
      );
    }
    if (settings.name == SessionDetailScreen.routeName &&
        arguments is SessionSummary) {
      return _pageRoute(
        settings,
        SessionDetailScreen(session: arguments),
      );
    }
    if (settings.name == SpeechSettingsScreen.routeName) {
      return _pageRoute(settings, const SpeechSettingsScreen());
    }

    final match = AppRoutes.parse(settings.name);
    switch (match.kind) {
      case AppRouteKind.home:
        return _pageRoute(settings, const HomeScreen());
      case AppRouteKind.settings:
        return _pageRoute(settings, const SettingsScreen());
      case AppRouteKind.projects:
        return _pageRoute(settings, const ProjectsScreen());
      case AppRouteKind.project:
        final projectId = match.projectId!;
        if (arguments is ProjectSummary && arguments.id == projectId) {
          return _pageRoute(
            settings,
            ProjectDetailScreen(project: arguments),
          );
        }
        return _pageRoute(
          settings,
          _ProjectRouteLoaderScreen(projectId: projectId),
        );
      case AppRouteKind.session:
        final projectId = match.projectId!;
        final sessionId = match.sessionId!;
        if (arguments is SessionSummary &&
            arguments.projectId == projectId &&
            arguments.id == sessionId) {
          return _pageRoute(
            settings,
            SessionDetailScreen(session: arguments),
          );
        }
        return _pageRoute(
          settings,
          _SessionRouteLoaderScreen(
            projectId: projectId,
            sessionId: sessionId,
          ),
        );
      case AppRouteKind.unknown:
        return _buildUnknownRoute(settings);
    }
  }

  MaterialPageRoute<void> _pageRoute(RouteSettings settings, Widget child) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => child,
    );
  }
}

class _ProjectRouteLoaderScreen extends StatefulWidget {
  const _ProjectRouteLoaderScreen({required this.projectId});

  final String projectId;

  @override
  State<_ProjectRouteLoaderScreen> createState() =>
      _ProjectRouteLoaderScreenState();
}

class _ProjectRouteLoaderScreenState extends State<_ProjectRouteLoaderScreen> {
  ProjectSummary? _project;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProject());
  }

  Future<void> _loadProject() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final project = await bridgeClient.getProject(widget.projectId);
      if (!mounted) {
        return;
      }
      setState(() {
        _project = project;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    if (project != null) {
      return ProjectDetailScreen(project: project);
    }

    if (_isLoading) {
      return _RouteStateScreen(
        title: context.l10n.projectsTitle,
        progress: true,
      );
    }

    return _RouteStateScreen(
      title: context.l10n.projectsTitle,
      message: context.l10n.loadProjectsFailed(_error ?? widget.projectId),
      onRetry: _loadProject,
    );
  }
}

class _SessionRouteLoaderScreen extends StatefulWidget {
  const _SessionRouteLoaderScreen({
    required this.projectId,
    required this.sessionId,
  });

  final String projectId;
  final String sessionId;

  @override
  State<_SessionRouteLoaderScreen> createState() =>
      _SessionRouteLoaderScreenState();
}

class _SessionRouteLoaderScreenState extends State<_SessionRouteLoaderScreen> {
  SessionSummary? _session;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final session = await bridgeClient.getProjectSession(
        widget.projectId,
        widget.sessionId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return SessionDetailScreen(session: session);
    }

    if (_isLoading) {
      return _RouteStateScreen(
        title: context.l10n.sessionsTitle,
        progress: true,
      );
    }

    return _RouteStateScreen(
      title: context.l10n.sessionsTitle,
      message: context.l10n.loadSessionsFailed(_error ?? widget.sessionId),
      onRetry: _loadSession,
    );
  }
}

class _RouteStateScreen extends StatelessWidget {
  const _RouteStateScreen({
    required this.title,
    this.message,
    this.onRetry,
    this.progress = false,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    if (progress) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const _RouteLoadingSkeleton(key: Key('route-loading-skeleton')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message != null) ...[
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.5),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteLoadingSkeleton extends StatelessWidget {
  const _RouteLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.boardGradientFor(brightness),
      ),
      child: ListView(
        padding: AppSpacing.screenPadding,
        children: const [
          AppSkeletonBlock(width: 160, height: 26),
          SizedBox(height: AppSpacing.compact),
          AppSkeletonBlock(width: 220, height: 10),
          SizedBox(height: AppSpacing.section),
          AppSkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(width: 104, height: 10),
                SizedBox(height: AppSpacing.compact),
                AppSkeletonBlock(height: 12),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(width: 180, height: 10),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.compact),
          AppSkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(height: 12),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(height: 10),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(width: 140, height: 10),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.compact),
          AppSkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(height: 12),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(width: 200, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
