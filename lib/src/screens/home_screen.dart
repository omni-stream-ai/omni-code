import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/copyable_message.dart';
import 'project_detail_screen.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';

const _bridgeRepositoryUrl =
    'https://github.com/omni-stream-ai/omni-code-bridge';

enum _HomeSurfaceState { loading, connect, waitingApproval, dashboard }

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

  final _bridgeUrlController = TextEditingController();
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
  int _visibleRecentCount = _recentPageSize;
  Timer? _authPollTimer;
  DateTime? _lastHomeDataLoadAt;

  BridgeClient get _client => widget.client ?? bridgeClient;
  DateTime Function() get _now => widget.now ?? DateTime.now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridgeUrlController.text = appSettingsController.settings.bridgeUrl;
    _projects = _client.peekProjects();
    _recentSessions = _client.peekSessions();
    _visibleRecentCount = min(_recentPageSize, _recentSessions?.length ?? 0);
    _isLoading = _projects == null && _recentSessions == null;
    unawaited(_loadHomeData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authPollTimer?.cancel();
    _bridgeUrlController.dispose();
    super.dispose();
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
    final cachedProjects = _client.peekProjects();
    final cachedSessions = _client.peekSessions();
    final previousVisibleCount = _visibleRecentCount;
    final shouldRefreshFromNetwork = forceRefresh ||
        cachedProjects != null ||
        cachedSessions != null ||
        _projects != null ||
        _recentSessions != null;

    setState(() {
      _projectsError = null;
      _recentSessionsError = null;
      _authError = null;
      _projects = cachedProjects ?? _projects;
      _recentSessions = cachedSessions ?? _recentSessions;
      final availableCount = _recentSessions?.length ?? previousVisibleCount;
      _visibleRecentCount = availableCount == 0
          ? 0
          : min(max(previousVisibleCount, _recentPageSize), availableCount);
      if (_projects == null && _recentSessions == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });

    try {
      final projects = await _client.listProjects(
        forceRefresh: shouldRefreshFromNetwork,
      );
      List<SessionSummary>? sessions;
      Object? sessionsError;
      try {
        sessions = await _client.listSessions(
          forceRefresh: shouldRefreshFromNetwork,
        );
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
        _recentSessions = sessions ?? _client.peekSessions() ?? _recentSessions;
        final availableCount = _recentSessions?.length ?? 0;
        _visibleRecentCount = availableCount == 0
            ? 0
            : min(max(previousVisibleCount, _recentPageSize), availableCount);
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
    final projects = _projects;
    if (projects == null || projects.isEmpty) {
      await _createProject();
      return;
    }

    final result = await showDialog<_ProjectSelectResult>(
      context: context,
      builder: (context) => _SelectProjectDialog(projects: projects),
    );
    if (result == null || !mounted) {
      return;
    }

    ProjectSummary project;
    if (result is _SelectExistingProject) {
      project = result.project;
    } else {
      final createResult = await showDialog<(String, String)>(
        context: context,
        builder: (context) => const _CreateProjectDialog(),
      );
      if (createResult == null || !mounted) {
        return;
      }
      project = await _client.createProject(
        name: createResult.$1,
        rootPath: createResult.$2,
      );
      if (!mounted) {
        return;
      }
    }

    final l10n = context.l10n;
    final sessionResult = await showDialog<(String?, String)>(
      context: context,
      builder: (context) => const _CreateSessionDialog(),
    );
    if (sessionResult == null || !mounted) {
      return;
    }

    final initialTitle = sessionResult.$1?.trim();
    final placeholderSession = SessionSummary(
      id: 'local-draft-${DateTime.now().microsecondsSinceEpoch}',
      projectId: project.id,
      title: (initialTitle != null && initialTitle.isNotEmpty)
          ? initialTitle
          : l10n.newSession,
      agent: parseAgentKind(sessionResult.$2),
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
      status: SessionStatus.idle,
      updatedAt: DateTime.now(),
      unreadCount: 0,
    );
    final sessionFuture = _client.createSession(
      projectId: project.id,
      title: sessionResult.$1,
      agent: sessionResult.$2,
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(
          session: placeholderSession,
          sessionInitializer: sessionFuture,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    unawaited(_loadHomeData(forceRefresh: true));
  }

  Future<void> _createProject() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _CreateProjectDialog(),
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
    await _reloadHomeData();
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
    return Scaffold(
      backgroundColor: AppColors.boardFor(brightness),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.boardGradientFor(brightness),
        ),
        child: SafeArea(
          child: switch (_surfaceState) {
            _HomeSurfaceState.loading => _buildLoadingState(),
            _HomeSurfaceState.connect => _buildConnectState(),
            _HomeSurfaceState.waitingApproval => _buildWaitingApprovalState(),
            _HomeSurfaceState.dashboard => _buildDashboardState(),
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
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
          (session) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.compact),
            child: _RecentSessionCard(
              title: session.title,
              preview: session.lastMessagePreview,
              metadata: _sessionMetadataLabel(session),
              accentColor: _statusColor(session.status, brightness),
              onTap: () => _openSession(session),
            ),
          ),
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

  Widget _buildDashboardState() {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final projects = _projects ?? const <ProjectSummary>[];
    final sessions = _recentSessions ?? const <SessionSummary>[];
    final visibleSessions = sessions.take(_visibleRecentCount).toList();

    return Stack(
      children: [
        _ShellScrollView(
          onRefresh: _reloadHomeData,
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
            if (_projectsError != null && projects.isEmpty) ...[
              const SizedBox(height: AppSpacing.stack),
              _ErrorPanel(
                message: l10n.loadProjectsFailed('$_projectsError'),
                onRetry: _reloadHomeData,
              ),
            ],
            const SizedBox(height: AppSpacing.section),
            _buildRecentSessionsHeader(),
            _buildRecentSessionsContent(
              context,
              sessions,
              visibleSessions,
              brightness,
            ),
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

  String _sessionMetadataLabel(SessionSummary session) {
    final parts = <String>[];
    final projectName = _projects
        ?.where((project) => project.id == session.projectId)
        .map((project) => project.name)
        .firstOrNull;
    if (projectName != null && projectName.isNotEmpty) {
      parts.add(projectName);
    }
    parts.add(session.agent.id);
    parts.add(_statusLabel(session.status));
    return parts.join(' · ');
  }

  String _statusLabel(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return context.l10n.sessionStatusIdle;
      case SessionStatus.running:
        return context.l10n.sessionStatusRunning;
      case SessionStatus.awaitingApproval:
        return context.l10n.sessionStatusAwaitingApproval;
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
  List<ProjectSummary>? _projects;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void initState() {
    super.initState();
    _projects = _client.peekProjects();
    _isLoading = _projects == null;
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final cachedProjects = _client.peekProjects();
    final shouldRefreshFromNetwork =
        forceRefresh || cachedProjects != null || _projects != null;
    setState(() {
      _error = null;
      _projects = cachedProjects ?? _projects;
      if (_projects == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });
    try {
      final projects = await _client.listProjects(
        forceRefresh: shouldRefreshFromNetwork,
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
      builder: (context) => const _CreateProjectDialog(),
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
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.boardFor(brightness),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.boardGradientFor(brightness),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              _ShellScrollView(
                onRefresh: _reloadProjects,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppBackHeader(
                          title: context.l10n.projectsTitle.toUpperCase(),
                          titleStyle: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
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
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                      onClear: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
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
                        padding: const EdgeInsets.only(
                            bottom: AppSpacing.stackTight),
                        child: AppCard(
                          onTap: () => _openProject(project),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.tileX,
                            vertical: AppSpacing.tileY,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusTile,
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontSize: 12),
                                    ),
                                    const SizedBox(
                                        height: AppSpacing.textStack),
                                    Text(
                                      project.rootPath,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.mutedSoftFor(
                                                brightness),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.tileY),
                              Text(
                                _formatTimestamp(project.updatedAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.mutedSoftFor(brightness),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
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
      ),
    );
  }
}

class _ShellScrollView extends StatelessWidget {
  const _ShellScrollView({
    required this.children,
    this.onRefresh,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

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
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.contentMaxWidth,
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
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String? preview;
  final String metadata;
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
              ],
            ),
          ),
        ],
      ),
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

sealed class _ProjectSelectResult {}

class _SelectExistingProject extends _ProjectSelectResult {
  _SelectExistingProject(this.project);

  final ProjectSummary project;
}

class _CreateNewProject extends _ProjectSelectResult {}

class _SelectProjectDialog extends StatelessWidget {
  const _SelectProjectDialog({required this.projects});

  final List<ProjectSummary> projects;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.selectProject),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: projects.length + 1,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: AppColors.outlineFor(brightness),
          ),
          itemBuilder: (context, index) {
            if (index == projects.length) {
              return ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(context.l10n.createNewProject),
                onTap: () => Navigator.of(context).pop(_CreateNewProject()),
              );
            }
            final project = projects[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                project.rootPath,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () =>
                  Navigator.of(context).pop(_SelectExistingProject(project)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}

class _CreateSessionDialog extends StatefulWidget {
  const _CreateSessionDialog();

  @override
  State<_CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<_CreateSessionDialog> {
  final _titleController = TextEditingController();
  String _agent = AgentKind.codex.id;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.newSession),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: context.l10n.sessionTitleOptional,
            ),
          ),
          const SizedBox(height: AppSpacing.stack),
          DropdownButtonFormField<String>(
            initialValue: _agent,
            items: AgentKind.selectableValues
                .map(
                  (agent) => DropdownMenuItem(
                    value: agent.id,
                    child: Text(agent.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _agent = value;
              });
            },
            decoration: InputDecoration(labelText: context.l10n.agentLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            Navigator.of(context).pop((title.isEmpty ? null : title, _agent));
          },
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.newProject),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.l10n.projectName),
          ),
          const SizedBox(height: AppSpacing.stack),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(labelText: context.l10n.localPath),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final path = _pathController.text.trim();
            if (name.isEmpty || path.isEmpty) {
              return;
            }
            Navigator.of(context).pop((name, path));
          },
          child: Text(context.l10n.createProject),
        ),
      ],
    );
  }
}
