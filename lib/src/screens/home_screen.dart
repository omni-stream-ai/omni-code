import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../responsive/app_responsive_layout.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/copyable_message.dart';
import '../widgets/new_session_flow.dart';
import 'project_detail_screen.dart';
import 'settings_screen.dart';

const _bridgeRepositoryUrl =
    'https://github.com/omni-stream-ai/omni-code-bridge';

enum _HomeSurfaceState { loading, connect, waitingApproval, dashboard }

const double _homeDesktopRailWidth = 312;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.client, this.now});

  final BridgeClient? client;
  final DateTime Function()? now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _recentPageSize = 5;
  static const _progressMinHeight = AppSpacing.textStack + AppSpacing.hairline;
  static const _resumeRefreshThrottle = Duration(seconds: 15);
  static const _searchDebounceDuration = Duration(milliseconds: 300);

  final _bridgeUrlController = TextEditingController();
  final _searchController = TextEditingController();
  List<ProjectSummary>? _projects;
  List<SessionSummary>? _recentSessions;
  Object? _projectsError;
  Object? _recentSessionsError;
  Object? _authError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _needsAuthorization = false;
  bool _isWaitingAuth = false;
  bool _isAuthorizing = false;
  bool _isSavingBridgeConfig = false;
  String? _authRequestId;
  String _searchQuery = '';
  int _visibleRecentCount = _recentPageSize;
  Timer? _authPollTimer;
  Timer? _searchDebounceTimer;
  DateTime? _lastHomeDataLoadAt;

  BridgeClient get _client => widget.client ?? bridgeClient;
  DateTime Function() get _now => widget.now ?? DateTime.now;

  int _resolvedVisibleRecentCount(int totalCount) {
    if (totalCount <= 0) {
      return 0;
    }
    return min(max(_visibleRecentCount, _recentPageSize), totalCount);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridgeUrlController.text = appSettingsController.settings.bridgeUrl;
    _visibleRecentCount = 0;
    _isLoading = true;
    unawaited(_loadHomeData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authPollTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _bridgeUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearchQueryUpdate(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchQuery = value.trim();
      });
    });
  }

  void _clearSearchQuery() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    if (_isLoading ||
        _isRefreshing ||
        _needsAuthorization ||
        _isWaitingAuth ||
        _isAuthorizing ||
        _isSavingBridgeConfig) {
      return;
    }
    final lastLoadAt = _lastHomeDataLoadAt;
    if (lastLoadAt != null &&
        _now().difference(lastLoadAt) < _resumeRefreshThrottle) {
      return;
    }
    unawaited(_loadHomeData(forceRefresh: true));
  }

  Future<void> _loadHomeData({bool forceRefresh = false}) async {
    _lastHomeDataLoadAt = _now();
    setState(() {
      _projectsError = null;
      _recentSessionsError = null;
      _authError = null;
      _visibleRecentCount =
          _resolvedVisibleRecentCount(_recentSessions?.length ?? 0);
      if (_projects == null && _recentSessions == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });

    try {
      final projects = await _client.listProjects(forceRefresh: true);
      List<SessionSummary>? sessions;
      Object? sessionsError;
      try {
        sessions = await _client.listSessions(forceRefresh: true);
      } on ClientUnauthorizedException {
        rethrow;
      } catch (error) {
        sessionsError = error;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
        _recentSessions = sessions ?? _recentSessions;
        _visibleRecentCount =
            _resolvedVisibleRecentCount(_recentSessions?.length ?? 0);
        _recentSessionsError = sessionsError;
        _needsAuthorization = false;
        _isWaitingAuth = false;
        _authRequestId = null;
      });
    } on ClientUnauthorizedException {
      if (!mounted) {
        return;
      }
      await _handleUnauthorized();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _projectsError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _reloadHomeData() {
    return _loadHomeData(forceRefresh: true);
  }

  Future<void> _handleUnauthorized() async {
    final pendingRequestId =
        appSettingsController.settings.pendingClientAuthRequestId.trim();

    if (pendingRequestId.isNotEmpty) {
      try {
        final status = await _client.checkClientAuthStatus(pendingRequestId);
        if (!mounted) {
          return;
        }
        if (status.isApproved && status.token != null) {
          await _saveApprovedAuthToken(status.token!);
          unawaited(_loadHomeData(forceRefresh: true));
          return;
        }
        if (status.isPending) {
          _waitForAuthRequest(pendingRequestId);
          return;
        }
        await _clearPendingAuthRequest();
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _authError = error;
        });
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _needsAuthorization = true;
      _isWaitingAuth = false;
      _authRequestId = null;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  Future<void> _startAuthorization() async {
    if (_isAuthorizing || _isSavingBridgeConfig) {
      return;
    }
    if (_hasPendingBridgeConfigChanges) {
      final saved = await _saveBridgeConfig(showFeedback: false);
      if (!saved) {
        return;
      }
    }
    setState(() {
      _authError = null;
      _isAuthorizing = true;
    });
    try {
      await _registerClientAuthRequest();
    } finally {
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
        });
      }
    }
  }

  Future<void> _registerClientAuthRequest() async {
    try {
      final authRequest = await _client.registerClient();
      if (!mounted) {
        return;
      }
      _waitForAuthRequest(authRequest.requestId);
      unawaited(_savePendingAuthRequest(authRequest.requestId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _needsAuthorization = true;
        _isWaitingAuth = false;
        _authError = error;
      });
    }
  }

  void _waitForAuthRequest(String requestId) {
    setState(() {
      _authRequestId = requestId;
      _needsAuthorization = false;
      _isWaitingAuth = true;
      _isLoading = false;
      _isRefreshing = false;
    });
    _startAuthPolling();
  }

  void _startAuthPolling() {
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _authRequestId == null) {
        timer.cancel();
        return;
      }
      try {
        final status = await _client.checkClientAuthStatus(_authRequestId!);
        if (!mounted) {
          return;
        }
        if (status.isApproved && status.token != null) {
          timer.cancel();
          await _saveApprovedAuthToken(status.token!);
          setState(() {
            _isWaitingAuth = false;
            _authRequestId = null;
          });
          unawaited(_loadHomeData(forceRefresh: true));
        }
      } catch (_) {}
    });
  }

  Future<void> _retryAuth() async {
    setState(() {
      _authError = null;
      _isAuthorizing = true;
    });
    _authPollTimer?.cancel();
    _authPollTimer = null;
    _clearPendingAuthRequest().catchError((_) {});
    try {
      await _registerClientAuthRequest();
    } finally {
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
        });
      }
    }
  }

  Future<void> _returnToWelcome() async {
    _authPollTimer?.cancel();
    _authPollTimer = null;
    try {
      await _clearPendingAuthRequest();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _authError = null;
      _needsAuthorization = true;
      _isWaitingAuth = false;
      _authRequestId = null;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  Future<void> _savePendingAuthRequest(String requestId) async {
    await appSettingsController.save(
      appSettingsController.settings.copyWith(
        pendingClientAuthRequestId: requestId,
      ),
    );
  }

  Future<void> _clearPendingAuthRequest() {
    return appSettingsController.save(
      appSettingsController.settings.copyWith(
        pendingClientAuthRequestId: '',
      ),
    );
  }

  Future<void> _saveApprovedAuthToken(String token) {
    return appSettingsController.save(
      appSettingsController.settings.copyWith(
        bridgeToken: token,
        pendingClientAuthRequestId: '',
      ),
    );
  }

  bool get _hasPendingBridgeConfigChanges {
    return _bridgeUrlController.text.trim() !=
        appSettingsController.settings.bridgeUrl.trim();
  }

  Future<bool> _saveBridgeConfig({required bool showFeedback}) async {
    if (_isSavingBridgeConfig) {
      return false;
    }
    final nextBridgeUrl = _bridgeUrlController.text.trim();
    if (!_hasPendingBridgeConfigChanges) {
      return true;
    }

    setState(() {
      _isSavingBridgeConfig = true;
      _authError = null;
    });
    try {
      await appSettingsController.save(
        appSettingsController.settings.copyWith(
          bridgeUrl: nextBridgeUrl,
        ),
      );
      if (!mounted) {
        return true;
      }
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsSaved)),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.settingsSaveFailed('$error')),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBridgeConfig = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed(SettingsScreen.routeName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openBridgeDownloads() async {
    await launchUrl(
      Uri.parse(_bridgeRepositoryUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openProjects() async {
    await Navigator.of(context).pushNamed(AppRoutes.projects);
    if (!mounted) {
      return;
    }
    unawaited(_loadHomeData(forceRefresh: true));
  }

  Future<void> _openSession(SessionSummary session) async {
    debugPrint(
      '[nav] home open session id=${session.id} project=${session.projectId} '
      'title=${session.title}',
    );
    await Navigator.of(context).pushNamed(
      AppRoutes.session(session.projectId, session.id),
      arguments: session,
    );
    if (!mounted) {
      return;
    }
    unawaited(_loadHomeData(forceRefresh: true));
  }

  Future<void> _newSession() async {
    await startNewSessionFlow(
      context,
      client: _client,
      initialProjects: _projects,
      onSessionClosed: () => _loadHomeData(forceRefresh: true),
    );
  }

  Future<void> _newSessionForProject(ProjectSummary project) async {
    await startNewSessionFlow(
      context,
      client: _client,
      initialProject: project,
      onSessionClosed: () => _loadHomeData(forceRefresh: true),
    );
  }

  Future<void> _toggleDesktopSidebarCollapsed() async {
    await toggleDesktopNavigationCollapsed();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  _HomeSurfaceState get _surfaceState {
    if (_isLoading &&
        !_needsAuthorization &&
        !_isWaitingAuth &&
        _projects == null &&
        _recentSessions == null) {
      return _HomeSurfaceState.loading;
    }
    if (_isWaitingAuth) {
      return _HomeSurfaceState.waitingApproval;
    }
    if (_needsAuthorization) {
      return _HomeSurfaceState.connect;
    }
    return _HomeSurfaceState.dashboard;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;
    return AppNavigationScaffold(
      activeRoute: AppRouteKind.home,
      backgroundColor: AppColors.boardFor(brightness),
      recentProjects: _client.peekProjects() ?? const <ProjectSummary>[],
      recentSessions: _client.peekSessions() ?? const <SessionSummary>[],
      onNavigateHome: () {},
      onNavigateProjects: _openProjects,
      onNavigateSettings: _openSettings,
      onNewSession: _newSession,
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      showDesktopSidebar: _surfaceState == _HomeSurfaceState.dashboard,
      bodyBuilder: (context, useDesktopSidebar, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.boardGradientFor(brightness),
        ),
        child: switch (_surfaceState) {
          _HomeSurfaceState.loading => _buildLoadingState(
              useDesktopLayout: AppResponsiveLayout.isDesktopWidth(
                constraints.maxWidth,
              ),
            ),
          _HomeSurfaceState.connect => _buildConnectState(),
          _HomeSurfaceState.waitingApproval => _buildWaitingApprovalState(),
          _HomeSurfaceState.dashboard => _buildDashboardState(
              useDesktopSidebar: useDesktopSidebar,
            ),
        },
      ),
    );
  }

  Widget _buildLoadingState({required bool useDesktopLayout}) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final useWideDesktopLayout = AppResponsiveLayout.isWideDesktopWidth(
      MediaQuery.sizeOf(context).width,
    );
    if (useDesktopLayout) {
      return _DesktopHomeLoadingSkeleton(
        key: const Key('home-desktop-loading-skeleton'),
        useWideRail: useWideDesktopLayout,
        brightness: brightness,
      );
    }
    return _ShellScrollView(
      children: [
        _ShellHeader(
          title: l10n.appTitle.toUpperCase(),
          subtitle: l10n.homePrompt,
          trailing: _CircleActionButton(
            icon: Icons.settings_outlined,
            onPressed: _openSettings,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _ActionCardSkeleton(
                accentColor: AppColors.accentBlueFor(brightness),
              ),
            ),
            const SizedBox(width: AppSpacing.tileY),
            Expanded(
              child: _ActionCardSkeleton(
                accentColor: AppColors.projectsAccentFor(brightness),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.section),
        const _SearchBarSkeleton(),
        const SizedBox(height: AppSpacing.section),
        _SectionHeader(title: l10n.recentSessionsTitle),
        const SizedBox(height: AppSpacing.compact),
        const _RecentSessionsSkeleton(key: Key('home-dashboard-skeleton')),
      ],
    );
  }

  Widget _buildRecentSessionsHeader() {
    return _SectionHeader(
      title: context.l10n.recentSessionsTitle,
      trailing: _CircleActionButton(
        icon: Icons.refresh_rounded,
        onPressed: _reloadHomeData,
      ),
    );
  }

  Widget _buildRecentSessionsContent(
    BuildContext context,
    List<SessionSummary> sessions,
    List<SessionSummary> visibleSessions,
    Brightness brightness,
  ) {
    final l10n = context.l10n;
    if (_isLoading && sessions.isEmpty) {
      return const _RecentSessionsSkeleton(key: Key('home-recent-skeleton'));
    }
    if (_recentSessionsError != null && sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.compact),
        child: _ErrorPanel(
          message: l10n.loadSessionsFailed('$_recentSessionsError'),
          onRetry: _reloadHomeData,
        ),
      );
    }
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.compact),
        child: _EmptyPanel(
          title: l10n.noSessionsYet,
          body: l10n.noSessionsHelp,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.compact),
        ...visibleSessions.map(
          (session) {
            final forkSource = _forkSourceLabel(session, sessions);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.compact),
              child: _RecentSessionCard(
                title: session.title,
                preview: session.lastMessagePreview,
                metadata: _sessionMetadataLabel(session),
                forkSource: forkSource == null
                    ? null
                    : l10n.forkedFromSession(forkSource),
                accentColor: _statusColor(session.status, brightness),
                onTap: () => _openSession(session),
              ),
            );
          },
        ),
        if (_visibleRecentCount < sessions.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.micro),
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _visibleRecentCount = min(
                    _visibleRecentCount + _recentPageSize,
                    sessions.length,
                  );
                });
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
              ),
              child: Text(l10n.loadMoreSessionsLabel),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectState() {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return _ShellScrollView(
      children: [
        _ShellHeader(
          title: l10n.connectHeader.toUpperCase(),
          subtitle: l10n.connectPrompt,
        ),
        _HeroInfoCard(
          accentColor: AppColors.accentBlueFor(brightness),
          accentBackground: AppColors.tintSurfaceFor(
            brightness,
            AppColors.accentBlueFor(brightness),
            base: AppColors.panelFor(brightness),
            darkAlpha: 0.20,
            lightAlpha: 0.12,
          ),
          icon: Icons.shield_outlined,
          title: l10n.connectWelcomeTitle,
          body: l10n.connectWelcomeBody,
        ),
        _BridgeConfigCard(
          controller: _bridgeUrlController,
          saving: _isSavingBridgeConfig,
          hasPendingChanges: _hasPendingBridgeConfigChanges,
          onChanged: () {
            setState(() {
              _authError = null;
            });
          },
          onSave: () => _saveBridgeConfig(showFeedback: true),
        ),
        _DownloadCard(
          title: l10n.connectDownloadTitle,
          body: l10n.connectDownloadBody,
          repository: l10n.connectDownloadRepo,
          buttonLabel: l10n.waitingApprovalDownloadBridge,
          onPressed: _openBridgeDownloads,
        ),
        if (_authError != null)
          _ErrorPanel(
            message: '$_authError',
            onRetry: _loadHomeData,
          ),
        FilledButton(
          onPressed: (_isAuthorizing || _isSavingBridgeConfig)
              ? null
              : _startAuthorization,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
          ),
          child: _isAuthorizing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimaryFor(brightness),
                  ),
                )
              : Text(l10n.authorizeThisDevice),
        ),
        Text(
          l10n.connectNextStep,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.mutedFor(brightness),
              ),
        ),
      ],
    );
  }

  Widget _buildWaitingApprovalState() {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final approvalCommand =
        'omni-code-bridge client-auth approve --request-id $_authRequestId';

    return _ShellScrollView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AppBackHeader(
            title: l10n.backToWelcome,
            tooltip: l10n.backToWelcome,
            onTap: _returnToWelcome,
            titleStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        _ShellHeader(
          title: l10n.waitingApprovalHeader.toUpperCase(),
          subtitle: l10n.waitingApprovalHeaderSubtitle,
        ),
        _HeroInfoCard(
          accentColor: AppColors.accentBlueFor(brightness),
          accentBackground: AppColors.tintSurfaceFor(
            brightness,
            AppColors.accentBlueFor(brightness),
            base: AppColors.panelFor(brightness),
            darkAlpha: 0.20,
            lightAlpha: 0.12,
          ),
          icon: Icons.shield_outlined,
          title: l10n.waitingApprovalTitle,
          body: l10n.waitingApprovalBody,
        ),
        OutlinedButton(
          onPressed: _openBridgeDownloads,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(38),
            backgroundColor: AppColors.warningSurfaceFor(brightness),
            foregroundColor: AppColors.warningTextFor(brightness),
            side: BorderSide(
              color: AppColors.warningBorderFor(brightness),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          child: Text(l10n.connectDownloadTitle),
        ),
        const SizedBox(height: AppSpacing.stack),
        _CommandCard(
          title: l10n.waitingApprovalRunCommand,
          command: approvalCommand,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: approvalCommand));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.copied)),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accentBlueFor(brightness),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            Text(
              l10n.waitingApprovalListening,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mutedFor(brightness),
                  ),
            ),
          ],
        ),
        if (_authError != null)
          _ErrorPanel(
            message: '$_authError',
            onRetry: _retryAuth,
          ),
        const SizedBox(height: AppSpacing.stack),
        OutlinedButton(
          onPressed: _isAuthorizing ? null : _retryAuth,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          child: _isAuthorizing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.waitingApprovalRequestAgain),
        ),
      ],
    );
  }

  Widget _buildDashboardState({required bool useDesktopSidebar}) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final projects =
        (_projects ?? const <ProjectSummary>[]).where(_matchesProject).toList();
    final sessions = (_recentSessions ?? const <SessionSummary>[])
        .where(_matchesSession)
        .toList();
    final visibleProjects = projects.take(4).toList();
    final visibleSessions = sessions.take(_visibleRecentCount).toList();

    final useWideDesktopLayout = AppResponsiveLayout.isWideDesktopWidth(
        MediaQuery.sizeOf(context).width);
    return Stack(
      children: [
        if (useDesktopSidebar)
          _buildDesktopDashboardState(
            useWideRail: useWideDesktopLayout,
            brightness: brightness,
            projects: projects,
            sessions: sessions,
          )
        else
          _ShellScrollView(
            onRefresh: _reloadHomeData,
            children: [
              _ShellHeader(
                title: l10n.appTitle.toUpperCase(),
                subtitle: l10n.homePrompt,
                trailing: Builder(
                  builder: (context) => _CircleActionButton(
                    icon: Icons.menu_rounded,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.add_comment_outlined,
                      accentColor: AppColors.accentBlueFor(brightness),
                      title: l10n.newSession,
                      subtitle: l10n.homeCreateProjectHint,
                      onTap: _newSession,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.tileY),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.folder_open_outlined,
                      accentColor: AppColors.projectsAccentFor(brightness),
                      title: l10n.projectsTitle,
                      subtitle: projects.isNotEmpty
                          ? l10n.projectsCount(projects.length)
                          : l10n.homeBrowseProjects,
                      onTap: _openProjects,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _buildDashboardSearchBar(),
              if (_projectsError != null && projects.isEmpty) ...[
                const SizedBox(height: AppSpacing.stack),
                _ErrorPanel(
                  message: l10n.loadProjectsFailed('$_projectsError'),
                  onRetry: _reloadHomeData,
                ),
              ],
              if (projects.isNotEmpty || sessions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                _buildRecentSessionsHeader(),
                _buildRecentSessionsContent(
                  context,
                  sessions,
                  visibleSessions,
                  brightness,
                ),
              ] else if (_hasSearchQuery) ...[
                const SizedBox(height: AppSpacing.section),
                _buildHomeSearchEmptyState(),
              ] else ...[
                const SizedBox(height: AppSpacing.section),
                _buildRecentSessionsHeader(),
                _buildRecentSessionsContent(
                  context,
                  sessions,
                  visibleSessions,
                  brightness,
                ),
              ],
              if (projects.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                _HomeProjectsPanel(
                  projects: [...visibleProjects]
                    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
                  brightness: brightness,
                  onOpenProject: (project) =>
                      _openProjectFromHome(context, project),
                  onCreateSessionForProject: _newSessionForProject,
                  onOpenProjects: projects.length > 4 ? _openProjects : null,
                ),
              ],
            ],
          ),
        if (_isRefreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: LinearProgressIndicator(
                minHeight: _progressMinHeight,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopDashboardState({
    required bool useWideRail,
    required Brightness brightness,
    required List<ProjectSummary> projects,
    required List<SessionSummary> sessions,
  }) {
    final pinnedSession = _pinnedSession(sessions);
    final inboxSessions =
        sessions.where((session) => session.id != pinnedSession?.id).toList();
    final approvalCount = sessions
        .where((session) => session.status == SessionStatus.awaitingApproval)
        .length;
    final runningCount = sessions
        .where((session) => session.status == SessionStatus.running)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        AppSpacing.screenTop,
        AppSpacing.screenX,
        AppSpacing.screenBottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.section),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HomeDesktopInboxHeader(
                    onReload: _reloadHomeData,
                    approvalCount: approvalCount,
                    runningCount: runningCount,
                    searchBar: _buildDashboardSearchBar(),
                  ),
                  const SizedBox(height: AppSpacing.compact),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        AppSpacing.micro,
                        0,
                        AppSpacing.block,
                      ),
                      child: _HomeDesktopInbox(
                        pinnedSession: pinnedSession,
                        projects: projects,
                        sessions: sessions,
                        visibleSessions: inboxSessions,
                        hasSearchQuery: _hasSearchQuery,
                        projectsError: _projectsError,
                        recentSessionsError: _recentSessionsError,
                        brightness: brightness,
                        onOpenSession: _openSession,
                        onCreateSessionForProject: _newSessionForProject,
                        onRetry: _reloadHomeData,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (useWideRail) ...[
            const SizedBox(width: AppSpacing.card),
            SizedBox(
              width: _homeDesktopRailWidth,
              child: _HomeDesktopRail(
                brightness: brightness,
                approvalCount: approvalCount,
                projectsCount: projects.length,
                needsAuthorization: _needsAuthorization,
                isWaitingAuth: _isWaitingAuth,
                authError: _authError,
                bridgeUrl: appSettingsController.settings.bridgeUrl,
                runningCount: runningCount,
                onOpenProjects: _openProjects,
                onOpenSettings: _openSettings,
              ),
            ),
          ],
        ],
      ),
    );
  }

  SessionSummary? _pinnedSession(List<SessionSummary> sessions) {
    if (sessions.isEmpty) {
      return null;
    }
    int rank(SessionStatus status) {
      return switch (status) {
        SessionStatus.awaitingApproval => 0,
        SessionStatus.running => 1,
        SessionStatus.waiting => 2,
        SessionStatus.idle => 3,
        SessionStatus.interrupted => 4,
        SessionStatus.failed => 5,
      };
    }

    final sorted = [...sessions];
    sorted.sort((a, b) {
      final rankCompare = rank(a.status).compareTo(rank(b.status));
      if (rankCompare != 0) {
        return rankCompare;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted.first;
  }

  String _sessionMetadataLabel(SessionSummary session) {
    final parts = <String>[];
    final projectName = _projects
        ?.where((project) => project.id == session.projectId)
        .map((project) => project.name)
        .firstOrNull;
    if (projectName != null && projectName.isNotEmpty) {
      parts.add(projectName);
    }
    parts.add(_client.agentLabelFor(session.agentId));
    parts.add(_statusLabel(session.status));
    return parts.join(' · ');
  }

  bool get _hasSearchQuery => _searchQuery.trim().isNotEmpty;

  bool _matchesProject(ProjectSummary project) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return project.name.toLowerCase().contains(query) ||
        project.rootPath.toLowerCase().contains(query) ||
        (project.lastSessionPreview?.toLowerCase().contains(query) ?? false);
  }

  bool _matchesSession(SessionSummary session) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final project = _projects
        ?.where((candidate) => candidate.id == session.projectId)
        .cast<ProjectSummary?>()
        .firstOrNull;
    return session.title.toLowerCase().contains(query) ||
        (session.lastMessagePreview?.toLowerCase().contains(query) ?? false) ||
        session.id.toLowerCase().contains(query) ||
        _client.agentLabelFor(session.agentId).toLowerCase().contains(query) ||
        (project?.name.toLowerCase().contains(query) ?? false) ||
        (project?.rootPath.toLowerCase().contains(query) ?? false);
  }

  Widget _buildDashboardSearchBar() {
    final l10n = context.l10n;
    return _SearchBar(
      key: const Key('home-dashboard-search-field'),
      controller: _searchController,
      hintText: '${l10n.searchProjects} · ${l10n.searchSessions}',
      onChanged: (value) {
        _scheduleSearchQueryUpdate(value);
      },
      onClear: _clearSearchQuery,
    );
  }

  Widget _buildHomeSearchEmptyState() {
    return _EmptyPanel(
      title: context.l10n.noSearchResultsTitle,
      body: context.l10n.noSearchResultsBody,
    );
  }

  String? _forkSourceLabel(
    SessionSummary session,
    List<SessionSummary> sessions,
  ) {
    final sourceId = session.forkedFromSessionId;
    if (sourceId == null || sourceId.isEmpty) {
      return null;
    }
    final sourceSession = sessions
        .where((candidate) => candidate.id == sourceId)
        .cast<SessionSummary?>()
        .firstOrNull;
    final sourceTitle = sourceSession?.title.trim();
    if (sourceTitle != null && sourceTitle.isNotEmpty) {
      return sourceTitle;
    }
    return _shortSessionId(sourceId);
  }

  String _shortSessionId(String sessionId) {
    if (sessionId.length <= 12) {
      return sessionId;
    }
    return '${sessionId.substring(0, 8)}...';
  }

  String _statusLabel(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return context.l10n.sessionStatusIdle;
      case SessionStatus.running:
        return context.l10n.sessionStatusRunning;
      case SessionStatus.awaitingApproval:
        return context.l10n.sessionStatusAwaitingApproval;
      case SessionStatus.interrupted:
        return context.l10n.sessionStatusInterrupted;
      case SessionStatus.waiting:
        return context.l10n.sessionStatusWaiting;
      case SessionStatus.failed:
        return context.l10n.sessionStatusFailed;
    }
  }

  Color _statusColor(SessionStatus status, Brightness brightness) {
    switch (status) {
      case SessionStatus.idle:
        return AppColors.idleFor(brightness);
      case SessionStatus.running:
        return AppColors.signalFor(brightness);
      case SessionStatus.awaitingApproval:
        return AppColors.warningFor(brightness);
      case SessionStatus.interrupted:
        return AppColors.outlineStrongFor(brightness);
      case SessionStatus.waiting:
        return AppColors.outlineStrongFor(brightness);
      case SessionStatus.failed:
        return AppColors.errorFor(brightness);
    }
  }
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, this.client});

  final BridgeClient? client;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  static const _searchDebounceDuration = Duration(milliseconds: 300);

  List<ProjectSummary>? _projects;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounceTimer;

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearchQueryUpdate(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchQuery = value.trim();
      });
    });
  }

  void _clearSearchQuery() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  void _redirectToHomeForAuthorization() {
    final navigator = Navigator.of(context);
    final isFirstRoute = ModalRoute.of(context)?.isFirst ?? false;
    if (isFirstRoute) {
      unawaited(navigator.pushReplacementNamed(AppRoutes.home));
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _loadProjects({bool forceRefresh = false}) async {
    final cachedProjects = _client.peekProjects() ?? const <ProjectSummary>[];
    setState(() {
      _error = null;
      if (_projects == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });
    try {
      final projects = _mergeFreshAndCachedProjects(
        fresh: await _client.listProjects(forceRefresh: true),
        cached: cachedProjects,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
      });
    } on ClientUnauthorizedException {
      if (!mounted) {
        return;
      }
      _redirectToHomeForAuthorization();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<ProjectSummary> _mergeFreshAndCachedProjects({
    required List<ProjectSummary> fresh,
    required List<ProjectSummary> cached,
  }) {
    final cachedById = {for (final project in cached) project.id: project};
    return fresh.map((project) {
      final cachedProject = cachedById[project.id];
      if (cachedProject != null &&
          cachedProject.updatedAt.isAfter(project.updatedAt)) {
        return cachedProject;
      }
      return project;
    }).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  Future<void> _reloadProjects() {
    return _loadProjects(forceRefresh: true);
  }

  Future<void> _openProject(ProjectSummary project) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.project(project.id),
      arguments: project,
    );
    if (!mounted) {
      return;
    }
    unawaited(_loadProjects(forceRefresh: true));
  }

  Future<void> _createProject() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );
    if (result == null) {
      return;
    }

    final project = await _client.createProject(
      name: result.$1,
      rootPath: result.$2,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushNamed(
      ProjectDetailScreen.routeName,
      arguments: project,
    );
    if (!mounted) {
      return;
    }
    await _reloadProjects();
  }

  Widget _buildProjectGitBadge(
    BuildContext context,
    String branch,
    ProjectGitStatus? status,
    Brightness brightness,
  ) {
    final statusColor = status == ProjectGitStatus.dirty
        ? AppColors.warningFor(brightness)
        : AppColors.successFor(brightness);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.source_outlined,
          size: 10,
          color: AppColors.mutedSoftFor(brightness),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            branch,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedSoftFor(brightness),
                ),
          ),
        ),
        if (status != null) ...[
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final allProjects = _projects ?? const <ProjectSummary>[];
    final projects = allProjects.where((project) {
      if (_searchQuery.isEmpty) {
        return true;
      }
      final query = _searchQuery.toLowerCase();
      return project.name.toLowerCase().contains(query) ||
          project.rootPath.toLowerCase().contains(query);
    }).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;

    return AppNavigationScaffold(
      activeRoute: AppRouteKind.projects,
      backgroundColor: AppColors.boardFor(brightness),
      recentProjects: _client.peekProjects() ?? const <ProjectSummary>[],
      recentSessions: _client.peekSessions() ?? const <SessionSummary>[],
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      onNavigateHome: () => Navigator.of(context).popUntil(
        (route) => route.settings.name == AppRoutes.home || route.isFirst,
      ),
      onNavigateProjects: () {},
      onNavigateSettings: () =>
          Navigator.of(context).pushNamed(AppRoutes.settings),
      onOpenProject: _openProject,
      onOpenSession: (session) {
        Navigator.of(context).pushNamed(
          AppRoutes.session(session.projectId, session.id),
          arguments: session,
        );
      },
      onNewSession: null,
      bodyBuilder: (context, useDesktop, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.boardGradientFor(brightness),
        ),
        child: Stack(
          children: [
            _buildProjectsBody(
              context,
              projects: projects,
              allProjects: allProjects,
              brightness: brightness,
              useDesktop: useDesktop,
            ),
            if (_isRefreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: LinearProgressIndicator(
                    minHeight: AppSpacing.textStack + AppSpacing.hairline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDesktopSidebarCollapsed() async {
    await toggleDesktopNavigationCollapsed();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _buildProjectsBody(
    BuildContext context, {
    required List<ProjectSummary> projects,
    required List<ProjectSummary> allProjects,
    required Brightness brightness,
    required bool useDesktop,
  }) {
    return _ShellScrollView(
      maxWidth: useDesktop ? 1120 : AppSpacing.contentMaxWidth,
      onRefresh: _reloadProjects,
      children: [
        Row(
          children: [
            if (!useDesktop) ...[
              Builder(
                builder: (context) => _CircleActionButton(
                  icon: Icons.menu_rounded,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              const SizedBox(width: AppSpacing.tileY),
            ],
            Expanded(
              child: AppBackHeader(
                title: context.l10n.projectsTitle.toUpperCase(),
                titleStyle:
                    Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: 0.6,
                        ),
              ),
            ),
            const SizedBox(width: AppSpacing.tileY),
            _CircleActionButton(
              icon: Icons.add_rounded,
              filled: true,
              onPressed: _createProject,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.card),
        if (_isLoading)
          const _SearchBarSkeleton()
        else
          _SearchBar(
            controller: _searchController,
            hintText: context.l10n.searchProjects,
            onChanged: (value) {
              _scheduleSearchQueryUpdate(value);
            },
            onClear: _clearSearchQuery,
          ),
        const SizedBox(height: AppSpacing.compact),
        if (_isLoading)
          const AppSkeletonBlock(width: 90, height: 10)
        else
          Text(
            context.l10n.projectsCount(projects.length),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedFor(brightness),
                ),
          ),
        const SizedBox(height: AppSpacing.compact),
        if (_isLoading)
          const _ProjectsListSkeleton(
            key: Key('projects-list-skeleton'),
          )
        else if (_error != null && allProjects.isEmpty)
          _ErrorPanel(
            message: context.l10n.loadProjectsFailed('$_error'),
            onRetry: _reloadProjects,
          )
        else if (allProjects.isEmpty)
          _EmptyPanel(
            title: context.l10n.noProjectsYet,
            body: context.l10n.noProjectsHelp,
            actionLabel: context.l10n.createProject,
            onAction: _createProject,
          )
        else if (projects.isEmpty)
          _EmptyPanel(
            title: context.l10n.noProjectsYet,
            body: context.l10n.searchProjects,
          )
        else
          ...projects.map(
            (project) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.stackTight),
              child: AppCard(
                onTap: () => _openProject(project),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.tileX,
                  vertical: AppSpacing.tileY,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: AppSpacing.textStack),
                          Text(
                            project.rootPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.mutedSoftFor(brightness),
                                    ),
                          ),
                          if (project.gitBranch != null) ...[
                            const SizedBox(height: AppSpacing.textTight),
                            _buildProjectGitBadge(
                              context,
                              project.gitBranch!,
                              project.gitStatus,
                              brightness,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.tileY),
                    Text(
                      _formatTimestamp(project.updatedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedSoftFor(brightness),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShellScrollView extends StatelessWidget {
  const _ShellScrollView({
    required this.children,
    this.onRefresh,
    this.maxWidth = AppSpacing.contentMaxWidth,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scrollView = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.screenTop,
            AppSpacing.screenX,
            AppSpacing.screenBottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );

    if (onRefresh == null) {
      return scrollView;
    }
    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: scrollView,
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: 0.6,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.mutedFor(Theme.of(context).brightness),
          height: 1.4,
          letterSpacing: 0.2,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.card),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                const SizedBox(height: AppSpacing.micro),
                Text(subtitle, style: subtitleStyle),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.tileY),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final background = filled
        ? AppColors.primaryFor(brightness)
        : AppColors.panelDeepFor(brightness);
    final iconColor = filled
        ? AppColors.onPrimaryFor(brightness)
        : AppColors.mutedSoftFor(brightness);
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: background,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _HeroInfoCard extends StatelessWidget {
  const _HeroInfoCard({
    required this.accentColor,
    required this.accentBackground,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color accentColor;
  final Color accentBackground;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.tileY),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentBackground,
              borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(height: AppSpacing.tileY),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedFor(Theme.of(context).brightness),
                  height: 1.55,
                ),
          ),
        ],
      ),
    );
  }
}

class _BridgeConfigCard extends StatelessWidget {
  const _BridgeConfigCard({
    required this.controller,
    required this.saving,
    required this.hasPendingChanges,
    required this.onChanged,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final bool hasPendingChanges;
  final VoidCallback onChanged;
  final Future<bool> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.tileY),
      padding: const EdgeInsets.all(AppSpacing.tileX),
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.bridgeUrlLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSoftFor(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: (saving || !hasPendingChanges)
                      ? null
                      : () {
                          unawaited(onSave());
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.tileX,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                  ),
                  child: saving
                      ? Text(context.l10n.saving)
                      : Text(context.l10n.save),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.compact),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!saving && hasPendingChanges) {
                unawaited(onSave());
              }
            },
            decoration: const InputDecoration(
              hintText: 'http://127.0.0.1:8787',
            ),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            context.l10n.bridgeHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedFor(brightness),
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.title,
    required this.body,
    required this.repository,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String repository;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.tileY),
      padding: const EdgeInsets.all(AppSpacing.tileX),
      decoration: BoxDecoration(
        color: AppColors.warningSurfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.warningBorderFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.warningTextFor(brightness),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warningTextFor(brightness),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            repository,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warningMutedFor(brightness),
                  fontFamily: AppTheme.bodyFontFamily,
                  fontFamilyFallback: AppTheme.monoFontFamilyFallback,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.compact),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              backgroundColor: AppColors.panelFor(brightness),
              foregroundColor: AppColors.warningTextFor(brightness),
              side: BorderSide(color: AppColors.warningBorderFor(brightness)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.title,
    required this.command,
    required this.onCopy,
  });

  final String title;
  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.tileY),
      padding: const EdgeInsets.all(AppSpacing.tileX),
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSoftFor(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              OutlinedButton(
                onPressed: onCopy,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(56, 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.tileX,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusPill,
                    ),
                  ),
                ),
                child: Text(context.l10n.copy),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.compact),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.tileY),
            decoration: BoxDecoration(
              color: AppColors.screenFor(brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(
                fontFamily: AppTheme.bodyFontFamily,
                fontFamilyFallback: AppTheme.monoFontFamilyFallback,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCardSkeleton extends StatelessWidget {
  const _ActionCardSkeleton({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: AppSkeletonCard(
        padding: const EdgeInsets.all(AppSpacing.tileX),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(AppSpacing.micro),
              ),
            ),
            const Spacer(),
            const AppSkeletonBlock(width: 88, height: 12),
            const SizedBox(height: AppSpacing.micro),
            const AppSkeletonBlock(height: 10),
            const SizedBox(height: AppSpacing.textStack),
            const AppSkeletonBlock(width: 112, height: 10),
          ],
        ),
      ),
    );
  }
}

class _HomeDesktopInboxHeader extends StatelessWidget {
  const _HomeDesktopInboxHeader({
    required this.onReload,
    required this.approvalCount,
    required this.runningCount,
    required this.searchBar,
  });

  final VoidCallback onReload;
  final int approvalCount;
  final int runningCount;
  final Widget searchBar;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.block,
        0,
        AppSpacing.micro,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Return to the sessions that still need judgment.',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                letterSpacing: -0.6,
                              ),
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    Text(
                      approvalCount > 0
                          ? '$approvalCount approvals are waiting. $runningCount sessions are still moving.'
                          : '$runningCount sessions are still moving. Resume one and keep the thread intact.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mutedFor(brightness),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              _CircleActionButton(
                icon: Icons.refresh_rounded,
                onPressed: onReload,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.card),
          searchBar,
        ],
      ),
    );
  }
}

class _HomeDesktopInbox extends StatelessWidget {
  const _HomeDesktopInbox({
    required this.pinnedSession,
    required this.projects,
    required this.sessions,
    required this.visibleSessions,
    required this.hasSearchQuery,
    required this.projectsError,
    required this.recentSessionsError,
    required this.brightness,
    required this.onOpenSession,
    required this.onCreateSessionForProject,
    required this.onRetry,
  });

  final SessionSummary? pinnedSession;
  final List<ProjectSummary> projects;
  final List<SessionSummary> sessions;
  final List<SessionSummary> visibleSessions;
  final bool hasSearchQuery;
  final Object? projectsError;
  final Object? recentSessionsError;
  final Brightness brightness;
  final ValueChanged<SessionSummary> onOpenSession;
  final ValueChanged<ProjectSummary> onCreateSessionForProject;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final approvalCount = sessions
        .where((session) => session.status == SessionStatus.awaitingApproval)
        .length;
    final runningCount = sessions
        .where((session) => session.status == SessionStatus.running)
        .length;
    final idleCount = sessions
        .where((session) => session.status == SessionStatus.idle)
        .length;
    final spotlightSession = pinnedSession ??
        (visibleSessions.isNotEmpty ? visibleSessions.first : null);
    final queueSessions = visibleSessions
        .where((session) => session.id != spotlightSession?.id)
        .take(5)
        .toList();
    final recentProjects = [...projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (projectsError != null && sessions.isEmpty) {
      return _ErrorPanel(
        message: l10n.loadProjectsFailed('$projectsError'),
        onRetry: onRetry,
      );
    }
    if (recentSessionsError != null && sessions.isEmpty) {
      return _ErrorPanel(
        message: l10n.loadSessionsFailed('$recentSessionsError'),
        onRetry: onRetry,
      );
    }
    if (sessions.isEmpty && projects.isEmpty) {
      return _EmptyPanel(
        title: hasSearchQuery ? l10n.noSearchResultsTitle : l10n.noSessionsYet,
        body: hasSearchQuery ? l10n.noSearchResultsBody : l10n.noSessionsHelp,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeDesktopHero(
          projectCount: projects.length,
          sessionCount: sessions.length,
          runningCount: runningCount,
          approvalCount: approvalCount,
          idleCount: idleCount,
        ),
        const SizedBox(height: AppSpacing.section),
        if (spotlightSession != null)
          _HomeFeaturedSessionCard(
            session: spotlightSession,
            brightness: brightness,
            onOpenSession: onOpenSession,
          ),
        const SizedBox(height: AppSpacing.section),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 1080;
            final queuePanel = _HomeQueuePanel(
              sessions: queueSessions,
              brightness: brightness,
              onOpenSession: onOpenSession,
            );
            final projectsPanel = _HomeProjectsPanel(
              projects: recentProjects.take(4).toList(),
              brightness: brightness,
              onOpenProject: (project) =>
                  _openProjectFromHome(context, project),
              onCreateSessionForProject: onCreateSessionForProject,
              onOpenProjects: recentProjects.length > 4
                  ? () => _openProjectsFromHome(context)
                  : null,
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  queuePanel,
                  const SizedBox(height: AppSpacing.card),
                  projectsPanel,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: queuePanel),
                const SizedBox(width: AppSpacing.card),
                Expanded(child: projectsPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

void _openProjectFromHome(BuildContext context, ProjectSummary project) {
  Navigator.of(context).pushNamed(
    AppRoutes.project(project.id),
    arguments: project,
  );
}

void _openProjectsFromHome(BuildContext context) {
  Navigator.of(context).pushNamed(AppRoutes.projects);
}

class _HomeDesktopHero extends StatelessWidget {
  const _HomeDesktopHero({
    required this.projectCount,
    required this.sessionCount,
    required this.runningCount,
    required this.approvalCount,
    required this.idleCount,
  });

  final int projectCount;
  final int sessionCount;
  final int runningCount;
  final int approvalCount;
  final int idleCount;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.block,
        vertical: AppSpacing.tileX,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelFor(brightness).withValues(
          alpha: brightness == Brightness.dark ? 0.58 : 0.74,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Wrap(
        spacing: AppSpacing.stack,
        runSpacing: AppSpacing.compact,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _HomeInlineStat(
            label: 'Projects',
            value: '$projectCount',
          ),
          _HomeInlineStat(
            label: 'Threads',
            value: '$sessionCount',
          ),
          _HomeInlineStat(
            label: 'Active',
            value: '$runningCount',
          ),
          _HomeInlineStat(
            label: 'Review',
            value: '$approvalCount',
          ),
        ],
      ),
    );
  }
}

class _HomeInlineStat extends StatelessWidget {
  const _HomeInlineStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(width: AppSpacing.textStack),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.mutedFor(brightness),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _HomeProjectRow extends StatelessWidget {
  const _HomeProjectRow({
    required this.project,
    required this.brightness,
    required this.onTap,
    required this.onCreateSession,
  });

  final ProjectSummary project;
  final Brightness brightness;
  final VoidCallback onTap;
  final VoidCallback onCreateSession;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.compact,
          vertical: AppSpacing.tileY,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.textStack),
                  Text(
                    project.rootPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedFor(brightness),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            TextButton.icon(
              key: Key('home-project-new-session-${project.id}'),
              onPressed: onCreateSession,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.compact,
                ),
                backgroundColor: AppColors.panelDeepFor(brightness),
                foregroundColor: AppColors.accentBlueFor(brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppSpacing.radiusCapsule,
                  ),
                ),
                textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
              ),
              icon: const Icon(Icons.add_comment_outlined, size: 15),
              label: const Text('New'),
            ),
            const SizedBox(width: AppSpacing.textStack),
            Text(
              '${project.sessionCount}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.mutedSoftFor(brightness),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(width: AppSpacing.textStack),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.mutedFor(brightness),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeProjectDivider extends StatelessWidget {
  const _HomeProjectDivider({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.compact),
      child: Divider(
        height: 1,
        thickness: AppSpacing.hairline,
        color: AppColors.outlineFor(brightness),
      ),
    );
  }
}

class _HomeFeaturedSessionCard extends StatelessWidget {
  const _HomeFeaturedSessionCard({
    required this.session,
    required this.brightness,
    required this.onOpenSession,
  });

  final SessionSummary? session;
  final Brightness brightness;
  final ValueChanged<SessionSummary> onOpenSession;

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      key: const Key('home-featured-session-card'),
      onTap: () => onOpenSession(session!),
      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.section,
          AppSpacing.block,
          AppSpacing.section,
          AppSpacing.block,
        ),
        decoration: BoxDecoration(
          color: AppColors.panelFor(brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(color: AppColors.outlineFor(brightness)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'In focus',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.mutedFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.compact),
            Text(
              session!.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: AppSpacing.compact),
            Text(
              _homeSessionMetadataLabel(context, session!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedSoftFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (session!.lastMessagePreview?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.compact),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Text(
                  session!.lastMessagePreview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedFor(brightness),
                        height: 1.5,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeQueuePanel extends StatelessWidget {
  const _HomeQueuePanel({
    required this.sessions,
    required this.brightness,
    required this.onOpenSession,
  });

  final List<SessionSummary> sessions;
  final Brightness brightness;
  final ValueChanged<SessionSummary> onOpenSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.block),
      decoration: BoxDecoration(
        color: AppColors.panelFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Up next',
            trailing: _DesktopSectionMeta(label: '${sessions.length} threads'),
          ),
          const SizedBox(height: AppSpacing.compact),
          if (sessions.isEmpty)
            Text(
              'Nothing urgent is waiting right now.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedFor(brightness),
                  ),
            )
          else
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.compact),
                child: _HomeQueueItem(
                  session: session,
                  brightness: brightness,
                  onTap: () => onOpenSession(session),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeQueueItem extends StatelessWidget {
  const _HomeQueueItem({
    required this.session,
    required this.brightness,
    required this.onTap,
  });

  final SessionSummary session;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.tileX),
        decoration: BoxDecoration(
          color: AppColors.boardFor(brightness).withValues(
            alpha: brightness == Brightness.dark ? 0.44 : 0.74,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
          border: Border.all(color: AppColors.outlineFor(brightness)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: AppSpacing.textStack + 2),
            Text(
              _homeSessionMetadataLabel(context, session),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedFor(brightness),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeProjectsPanel extends StatelessWidget {
  const _HomeProjectsPanel({
    required this.projects,
    required this.brightness,
    required this.onOpenProject,
    required this.onCreateSessionForProject,
    this.onOpenProjects,
  });

  final List<ProjectSummary> projects;
  final Brightness brightness;
  final ValueChanged<ProjectSummary> onOpenProject;
  final ValueChanged<ProjectSummary> onCreateSessionForProject;
  final VoidCallback? onOpenProjects;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.block),
      decoration: BoxDecoration(
        color: AppColors.panelFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Recent projects',
            trailing: _DesktopSectionMeta(label: '${projects.length} visible'),
          ),
          const SizedBox(height: AppSpacing.compact),
          for (final indexedProject in projects.indexed) ...[
            _HomeProjectRow(
              project: indexedProject.$2,
              brightness: brightness,
              onTap: () => onOpenProject(indexedProject.$2),
              onCreateSession: () =>
                  onCreateSessionForProject(indexedProject.$2),
            ),
            if (indexedProject.$1 < projects.length - 1)
              _HomeProjectDivider(brightness: brightness),
          ],
          if (onOpenProjects != null) ...[
            const SizedBox(height: AppSpacing.compact),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onOpenProjects,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(108, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
                child: Text(context.l10n.projectsTitle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _homeSessionMetadataLabel(BuildContext context, SessionSummary session) {
  final state = context.findAncestorStateOfType<_HomeScreenState>();
  if (state == null) {
    return '';
  }
  return state._sessionMetadataLabel(session);
}

class _DesktopSectionMeta extends StatelessWidget {
  const _DesktopSectionMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.mutedFor(brightness),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _HomeDesktopRail extends StatelessWidget {
  const _HomeDesktopRail({
    required this.brightness,
    required this.approvalCount,
    required this.projectsCount,
    required this.needsAuthorization,
    required this.isWaitingAuth,
    required this.authError,
    required this.bridgeUrl,
    required this.runningCount,
    required this.onOpenProjects,
    required this.onOpenSettings,
  });

  final Brightness brightness;
  final int approvalCount;
  final int projectsCount;
  final bool needsAuthorization;
  final bool isWaitingAuth;
  final Object? authError;
  final String bridgeUrl;
  final int runningCount;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final bridgeSummary =
        switch ((needsAuthorization, isWaitingAuth, authError)) {
      (true, _, _) => 'Authorization needed',
      (_, true, _) => 'Waiting for approval',
      (_, _, final Object error) => '$error',
      _ => 'Connected • $bridgeUrl',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.compact,
        AppSpacing.block,
        0,
        AppSpacing.block,
      ),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.outlineFor(brightness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Status',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.stack),
          _HomeRailCard(
            title: 'Pending approvals',
            body: approvalCount > 0
                ? '$approvalCount waiting actions need review'
                : 'No approvals are waiting right now',
            warning: true,
          ),
          const SizedBox(height: AppSpacing.compact),
          _HomeRailCard(
            title: 'Bridge status',
            body: bridgeSummary,
          ),
          const SizedBox(height: AppSpacing.compact),
          _HomeRailCard(
            title: 'Voice / device',
            body: runningCount > 0
                ? '$runningCount active sessions • microphone ready'
                : 'Microphone ready • system speech available',
          ),
          const SizedBox(height: AppSpacing.compact),
          _HomeRailCard(
            title: 'Projects overview',
            body: '$projectsCount active projects',
          ),
          const SizedBox(height: AppSpacing.compact),
          _HomeRailCard(
            title: 'Quick actions',
            body: 'Open projects or adjust settings',
            actions: [
              TextButton(
                onPressed: onOpenProjects,
                child: Text(context.l10n.projectsTitle),
              ),
              TextButton(
                onPressed: onOpenSettings,
                child: Text(context.l10n.settingsTitle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeRailCard extends StatelessWidget {
  const _HomeRailCard({
    required this.title,
    required this.body,
    this.warning = false,
    this.actions,
  });

  final String title;
  final String body;
  final bool warning;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.tileX),
      decoration: BoxDecoration(
        color: warning
            ? AppColors.warningSurfaceFor(brightness)
            : AppColors.panelFor(brightness).withValues(
                alpha: brightness == Brightness.dark ? 0.66 : 0.88,
              ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: warning
              ? AppColors.warningBorderFor(brightness)
              : AppColors.outlineFor(brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
          ),
          const SizedBox(height: AppSpacing.textStack),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  height: 1.4,
                ),
          ),
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.compact),
            Wrap(
              spacing: AppSpacing.compact,
              runSpacing: AppSpacing.compact,
              children: actions!,
            ),
          ],
          const SizedBox(height: AppSpacing.micro),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.tileX),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accentColor),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.micro),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedFor(Theme.of(context).brightness),
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _DesktopHomeLoadingSkeleton extends StatelessWidget {
  const _DesktopHomeLoadingSkeleton({
    super.key,
    required this.useWideRail,
    required this.brightness,
  });

  final bool useWideRail;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        AppSpacing.screenTop,
        AppSpacing.screenX,
        AppSpacing.screenBottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.section),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _HomeDesktopInboxHeaderSkeleton(),
                  SizedBox(height: AppSpacing.compact),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        AppSpacing.micro,
                        0,
                        AppSpacing.block,
                      ),
                      child: _RecentSessionsSkeleton(
                        key: Key('home-dashboard-skeleton'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (useWideRail) ...[
            const SizedBox(width: AppSpacing.card),
            SizedBox(
              width: _homeDesktopRailWidth,
              child: _HomeDesktopRailSkeleton(
                key: const Key('home-desktop-rail-skeleton'),
                brightness: brightness,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeDesktopInboxHeaderSkeleton extends StatelessWidget {
  const _HomeDesktopInboxHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      padding: AppSpacing.tilePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              AppSkeletonBlock(width: 168, height: 18),
              Spacer(),
              AppSkeletonBlock(width: 44, height: 44),
            ],
          ),
          SizedBox(height: AppSpacing.stack),
          Row(
            children: [
              Expanded(child: AppSkeletonBlock(height: 34)),
              SizedBox(width: AppSpacing.tileY),
              AppSkeletonBlock(width: 104, height: 34),
              SizedBox(width: AppSpacing.tileY),
              AppSkeletonBlock(width: 104, height: 34),
            ],
          ),
          SizedBox(height: AppSpacing.stack),
          _SearchBarSkeleton(),
        ],
      ),
    );
  }
}

class _HomeDesktopRailSkeleton extends StatelessWidget {
  const _HomeDesktopRailSkeleton({super.key, required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopRailCardSkeleton(
          accentColor: AppColors.accentBlueFor(brightness),
        ),
        const SizedBox(height: AppSpacing.compact),
        _DesktopRailCardSkeleton(
          accentColor: AppColors.projectsAccentFor(brightness),
        ),
        const SizedBox(height: AppSpacing.compact),
        const Expanded(
          child: AppSkeletonCard(
            padding: AppSpacing.tilePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(width: 132, height: 14),
                SizedBox(height: AppSpacing.stack),
                AppSkeletonBlock(height: 10),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(width: 188, height: 10),
                SizedBox(height: AppSpacing.stack),
                AppSkeletonBlock(height: 34),
                Spacer(),
                AppSkeletonBlock(height: 34),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopRailCardSkeleton extends StatelessWidget {
  const _DesktopRailCardSkeleton({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      padding: AppSpacing.tilePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 4,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(height: AppSpacing.stack),
          const AppSkeletonBlock(width: 132, height: 14),
          const SizedBox(height: AppSpacing.textStack),
          const AppSkeletonBlock(height: 10),
        ],
      ),
    );
  }
}

class _RecentSessionsSkeleton extends StatelessWidget {
  const _RecentSessionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _RecentSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _RecentSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _RecentSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _RecentSessionCardSkeleton(),
      ],
    );
  }
}

class _RecentSessionCardSkeleton extends StatelessWidget {
  const _RecentSessionCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppSkeletonCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.tileY,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 24,
            margin: const EdgeInsets.only(top: AppSpacing.textStack),
            decoration: BoxDecoration(
              color: AppColors.skeletonHighlightFor(brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(width: AppSpacing.tileY),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(height: 12),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(height: 10),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(width: 140, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSessionCard extends StatelessWidget {
  const _RecentSessionCard({
    required this.title,
    required this.preview,
    required this.metadata,
    required this.forkSource,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String? preview;
  final String metadata;
  final String? forkSource;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.tileY,
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(width: AppSpacing.tileY),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (preview?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.textStack),
                  Text(
                    preview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedFor(brightness),
                          height: 1.4,
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.textStack),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (forkSource != null) ...[
                  const SizedBox(height: AppSpacing.textTight),
                  _ForkSourceLabel(label: forkSource!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForkSourceLabel extends StatelessWidget {
  const _ForkSourceLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.call_split_rounded,
          size: 12,
          color: AppColors.mutedSoftFor(brightness),
        ),
        const SizedBox(width: AppSpacing.micro),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _SearchBarSkeleton extends StatelessWidget {
  const _SearchBarSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      child: const SizedBox(
        height: 44,
        child: Row(
          children: [
            SizedBox(width: AppSpacing.tileX),
            AppSkeletonBlock(
              width: 18,
              height: 18,
              borderRadius: BorderRadius.all(
                Radius.circular(AppSpacing.micro),
              ),
            ),
            SizedBox(width: AppSpacing.tileY),
            Expanded(child: AppSkeletonBlock(height: 10)),
            SizedBox(width: AppSpacing.tileX),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(18),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: AppColors.panelFor(brightness),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.tileX,
          vertical: AppSpacing.tileY,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: AppColors.outlineFor(brightness)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: AppColors.outlineFor(brightness)),
        ),
      ),
    );
  }
}

class _ProjectsListSkeleton extends StatelessWidget {
  const _ProjectsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _ProjectListItemSkeleton(),
        SizedBox(height: AppSpacing.stackTight),
        _ProjectListItemSkeleton(),
        SizedBox(height: AppSpacing.stackTight),
        _ProjectListItemSkeleton(),
        SizedBox(height: AppSpacing.stackTight),
        _ProjectListItemSkeleton(),
      ],
    );
  }
}

class _ProjectListItemSkeleton extends StatelessWidget {
  const _ProjectListItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.tileY,
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBlock(height: 12),
                SizedBox(height: AppSpacing.textStack),
                AppSkeletonBlock(height: 10),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.tileY),
          AppSkeletonBlock(width: 84, height: 10),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: AppSpacing.blockPadding,
      decoration: BoxDecoration(
        color: AppColors.errorBgFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        border: Border.all(color: AppColors.errorBorderFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CopyableMessage(
            message: message,
            copyLabel: context.l10n.copy,
            copiedLabel: context.l10n.copied,
            backgroundColor: AppColors.errorBgFor(brightness),
            borderColor: AppColors.errorBorderFor(brightness),
            iconColor: AppColors.errorIconFor(brightness),
            textColor: AppColors.errorTextFor(brightness),
          ),
          const SizedBox(height: AppSpacing.stack),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: AppSpacing.blockPadding,
      decoration: BoxDecoration(
        color: AppColors.panelDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: AppSpacing.compact),
          Text(
            body,
            style: TextStyle(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.stack),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
