import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_snack_bar.dart';
import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';

import '../responsive/app_responsive_layout.dart';
import '../services/local_bridge_setup.dart';
import '../settings/app_settings.dart';
import '../shortcuts/desktop_shortcut.dart';
import '../shortcuts/desktop_shortcut_scope.dart';
import '../shortcuts/shortcut_keycaps.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/project_avatar.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/copyable_message.dart';
import '../widgets/new_session_flow.dart';
import '../widgets/local_bridge_setup_card.dart';
import '../widgets/session_cache_scope.dart';
import '../widgets/workspace_agent_panel.dart';
import 'project_detail_screen.dart';
import 'settings_screen.dart';
import 'bridge_setup_agent_screen.dart';

const _bridgeRepositoryUrl =
    'https://github.com/omni-stream-ai/omni-code-bridge';

enum _HomeSurfaceState { connect, waitingApproval, dashboard }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.client, this.now, this.localBridgeSetup});

  final BridgeClient? client;
  final DateTime Function()? now;
  final LocalBridgeSetupService? localBridgeSetup;

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
  List<CodexProfileSummary> _profiles = const <CodexProfileSummary>[];
  String? _selectedProfileId;
  Object? _projectsError;
  Object? _recentSessionsError;
  Object? _authError;
  bool _isLoading = true;
  bool _loadingSessions = true;
  int _homeLoadGeneration = 0;
  bool _isRefreshing = false;
  bool _needsAuthorization = false;
  bool _isWaitingAuth = false;
  bool _isAuthorizing = false;
  bool _isSavingBridgeConfig = false;
  String? _authRequestId;
  String _searchQuery = '';
  bool _showHistory = false;
  bool _savingHomeDisplay = false;
  int _visibleRecentCount = _recentPageSize;
  Timer? _authPollTimer;
  Timer? _searchDebounceTimer;
  DateTime? _lastHomeDataLoadAt;
  late final LocalBridgeSetupService _localBridgeSetup =
      widget.localBridgeSetup ?? createLocalBridgeSetupService();
  LocalBridgeSetupProgress? _localBridgeProgress;
  LocalBridgeSetupFailure? _localBridgeFailure;
  String? _localBridgeDiagnostic;

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
    appSettingsController.addListener(_onAppSettingsChanged);
    _bridgeUrlController.text = appSettingsController.settings.bridgeUrl;
    _visibleRecentCount = 0;
    _isLoading = true;
    unawaited(_loadHomeData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appSettingsController.removeListener(_onAppSettingsChanged);
    _authPollTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _bridgeUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAppSettingsChanged() {
    if (!mounted) {
      return;
    }
    final bridgeUrl = appSettingsController.settings.bridgeUrl.trim();
    if (_bridgeUrlController.text != bridgeUrl) {
      _bridgeUrlController.text = bridgeUrl;
    }
    setState(() {});
  }

  Future<void> _configureHomeDisplay() async {
    if (_savingHomeDisplay) return;
    final current = appSettingsController.settings;
    var mainAgent = current.homeShowMainAgent;
    var recentSessions = current.homeShowRecentSessions;
    var recentTasks = current.homeShowRecentTasks;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(agentText(context, '首页显示设置', 'Home display')),
                  content: SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            key: const Key('home-show-main-agent'),
                            title: Text(agentText(
                                context, '助手对话', 'Assistant conversation')),
                            value: mainAgent,
                            onChanged: (value) =>
                                update(() => mainAgent = value)),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            key: const Key('home-show-recent-sessions'),
                            title: Text(context.l10n.recentSessionsTitle),
                            value: recentSessions,
                            onChanged: (value) =>
                                update(() => recentSessions = value)),
                        if (current.autoTaskAnalysisEnabled)
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              key: const Key('home-show-recent-tasks'),
                              title: Text(agentText(context, '任务', 'Tasks')),
                              value: recentTasks,
                              onChanged: (value) =>
                                  update(() => recentTasks = value)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(agentText(context, '取消', 'Cancel'))),
                    FilledButton(
                        key: const Key('home-display-save'),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(agentText(context, '保存', 'Save'))),
                  ],
                )));
    if (save != true || !mounted) return;
    setState(() => _savingHomeDisplay = true);
    try {
      await appSettingsController.save(appSettingsController.settings.copyWith(
          homeShowMainAgent: mainAgent,
          homeShowRecentSessions: recentSessions,
          homeShowRecentTasks: recentTasks));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
            isError: true,
            content: Text(agentText(context, '显示设置保存失败，请重试。',
                'Could not save display settings. Please retry.'))));
      }
    } finally {
      if (mounted) setState(() => _savingHomeDisplay = false);
    }
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
    final generation = ++_homeLoadGeneration;
    final client = _client;
    final connectionRevision = client.connectionRevision;
    final profileId = _selectedProfileId;
    bool current() =>
        mounted &&
        generation == _homeLoadGeneration &&
        connectionRevision == client.connectionRevision;
    _lastHomeDataLoadAt = _now();
    setState(() {
      _projectsError = null;
      _recentSessionsError = null;
      _authError = null;
      _loadingSessions = true;
      _visibleRecentCount =
          _resolvedVisibleRecentCount(_recentSessions?.length ?? 0);
      _isLoading = _projects == null && _recentSessions == null;
      _isRefreshing = !_isLoading;
    });

    Future<void>? authorization;
    Future<void> unauthorized() => authorization ??= _handleUnauthorized();
    void connected() {
      if (authorization != null) return;
      _needsAuthorization = false;
      _isWaitingAuth = false;
      _authRequestId = null;
    }

    Future<void> loadProjects() async {
      try {
        final projects = await client.listProjects(forceRefresh: true);
        if (!current()) return;
        setState(() {
          _projects = projects;
          connected();
        });
      } on ClientUnauthorizedException {
        if (current()) await unauthorized();
      } catch (error) {
        if (current()) setState(() => _projectsError = error);
      }
    }

    Future<void> loadSessions() async {
      try {
        final sessions = await client.listDomainSessions(
            profileId: profileId, forceRefresh: true);
        if (!current()) return;
        setState(() {
          _recentSessions = sessions;
          _visibleRecentCount = _resolvedVisibleRecentCount(sessions.length);
          connected();
        });
      } on ClientUnauthorizedException {
        if (current()) await unauthorized();
      } catch (error) {
        if (!current()) return;
        setState(() {
          // An explicit refresh failure must not look like a fresh session list.
          if (forceRefresh || _recentSessions == null) {
            _recentSessions = const <SessionSummary>[];
          }
          _visibleRecentCount =
              _resolvedVisibleRecentCount(_recentSessions?.length ?? 0);
          _recentSessionsError = error;
        });
      } finally {
        if (current()) setState(() => _loadingSessions = false);
      }
    }

    Future<void> loadProfiles() async {
      try {
        final profiles =
            await client.listCodexProfiles(forceRefresh: forceRefresh);
        if (current()) setState(() => _profiles = profiles);
      } catch (_) {
        if (current()) {
          setState(() => _profiles = const <CodexProfileSummary>[]);
        }
      }
    }

    // Profile metadata is optional; it must not delay any home section.
    unawaited(loadProfiles());
    await Future.wait([loadProjects(), loadSessions()]);
    if (!current()) return;
    setState(() {
      _isLoading = false;
      _isRefreshing = false;
      if (authorization == null &&
          _projects == null &&
          _projectsError != null &&
          _recentSessionsError != null &&
          _localBridgeSetup.isSupported &&
          !appSettingsController.settings.relay.enabled &&
          appSettingsController.settings.bridgeToken.isEmpty) {
        _needsAuthorization = true;
      }
    });
  }

  Future<void> _reloadHomeData() {
    return _loadHomeData(forceRefresh: true);
  }

  Future<void> _selectProfile(String? profileId) async {
    if (_selectedProfileId == profileId) {
      return;
    }
    setState(() {
      _selectedProfileId = profileId;
    });
    await _loadHomeData(forceRefresh: true);
  }

  Future<void> _handleUnauthorized() async {
    _syncBridgeUrlController();
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
          AppSnackBar(content: Text(context.l10n.settingsSaved)),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            isError: true,
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
    final bridgeUrlBefore = appSettingsController.settings.connectionUrl.trim();
    final bridgeConnectionChecked = await Navigator.of(context).pushNamed(
      SettingsScreen.routeName,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    final bridgeUrlAfter = appSettingsController.settings.connectionUrl.trim();
    if (bridgeConnectionChecked is bool) {
      if (bridgeConnectionChecked) {
        unawaited(_loadHomeData(forceRefresh: true));
      } else {
        _showBridgeConnectionState();
      }
      return;
    }
    if (bridgeUrlBefore != bridgeUrlAfter) {
      unawaited(_loadHomeData(forceRefresh: true));
    }
  }

  void _showBridgeConnectionState() {
    if (appSettingsController.settings.relay.enabled) {
      _authPollTimer?.cancel();
      _authPollTimer = null;
      setState(() {
        _needsAuthorization = false;
        _isWaitingAuth = false;
        _authRequestId = null;
        _isLoading = false;
        _isRefreshing = false;
        _projectsError = context.l10n.relayCheckConnection;
        _recentSessionsError = context.l10n.relayCheckConnection;
        _authError = null;
      });
      return;
    }
    _authPollTimer?.cancel();
    _authPollTimer = null;
    setState(() {
      _bridgeUrlController.text =
          appSettingsController.settings.bridgeUrl.trim();
      _projectsError = null;
      _recentSessionsError = null;
      _authError = null;
      _needsAuthorization = true;
      _isWaitingAuth = false;
      _authRequestId = null;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  void _syncBridgeUrlController() {
    final bridgeUrl = appSettingsController.settings.bridgeUrl.trim();
    if (_bridgeUrlController.text != bridgeUrl) {
      _bridgeUrlController.text = bridgeUrl;
    }
  }

  Future<void> _openBridgeDownloads() async {
    await launchUrl(
      Uri.parse(_bridgeRepositoryUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _installLocalBridge() async {
    if (_localBridgeProgress != null ||
        _isAuthorizing ||
        _isSavingBridgeConfig) {
      return;
    }
    setState(() {
      _localBridgeFailure = null;
      _localBridgeDiagnostic = null;
      _localBridgeProgress = const LocalBridgeSetupProgress(
        LocalBridgeSetupStage.checking,
      );
    });
    try {
      final result = await _localBridgeSetup.installAndStart(
        clientId: appSettingsController.settings.clientId,
        onProgress: (progress) {
          if (mounted) setState(() => _localBridgeProgress = progress);
        },
      );
      await _applyLocalBridgeConnection(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _localBridgeFailure = error is LocalBridgeSetupException
              ? error.failure
              : LocalBridgeSetupFailure.installFailed;
          _localBridgeDiagnostic =
              error is LocalBridgeSetupException ? error.diagnostic : null;
        });
      }
    } finally {
      if (mounted) setState(() => _localBridgeProgress = null);
    }
  }

  Future<void> _applyLocalBridgeConnection(
      LocalBridgeSetupResult result) async {
    final settings = appSettingsController.settings;
    await appSettingsController.save(settings.copyWith(
      bridgeUrl: result.url,
      bridgeToken: result.token,
      pendingClientAuthRequestId: '',
      relay: settings.relay.copyWith(enabled: false),
    ));
    if (!mounted) return;
    _syncBridgeUrlController();
    await _loadHomeData(forceRefresh: true);
  }

  Future<void> _continueBridgeWithAgent() async {
    final failure = _localBridgeFailure;
    if (_localBridgeProgress != null || failure == null) return;
    final result = await Navigator.of(context).push<LocalBridgeSetupResult>(
      MaterialPageRoute(
          builder: (_) => BridgeSetupAgentScreen(
                failure: failure,
                diagnostic: _localBridgeDiagnostic,
                client: _client,
                setup: _localBridgeSetup,
              )),
    );
    if (!mounted || result == null) return;
    try {
      await _applyLocalBridgeConnection(result);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _localBridgeFailure = LocalBridgeSetupFailure.authorizationFailed);
      }
    }
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

  Future<void> _newSessionForSession(SessionSummary session) async {
    await startNewSessionFlow(
      context,
      client: _client,
      initialProjects: _projects,
      initialProject: _projectForSession(session),
      onSessionClosed: () => _loadHomeData(forceRefresh: true),
    );
  }

  ProjectSummary? _projectForSession(SessionSummary session) {
    final cached = _client.peekProject(session.projectId);
    if (cached != null) {
      return cached;
    }
    for (final project in _projects ?? const <ProjectSummary>[]) {
      if (project.id == session.projectId) {
        return project;
      }
    }
    return null;
  }

  Future<void> _toggleDesktopSidebarCollapsed() async {
    await toggleDesktopNavigationCollapsed();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  _HomeSurfaceState get _surfaceState {
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
    SessionCacheScope.watch(context);
    final brightness = Theme.of(context).brightness;
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;
    return AppNavigationScaffold(
      activeRoute: AppRouteKind.home,
      backgroundColor: _HomeStyle.canvas(brightness),
      recentProjects: _client.peekProjects() ?? const <ProjectSummary>[],
      recentSessions: _client.peekRecentSessions() ?? const <SessionSummary>[],
      onNavigateHome: () {},
      onNavigateProjects: _openProjects,
      onNavigateSettings: _openSettings,
      onNewSession: _newSession,
      onNewSessionForProject: _newSessionForProject,
      onNewSessionForSession: _newSessionForSession,
      agentLabelFor: _client.agentLabelFor,
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      showDesktopSidebar: _surfaceState == _HomeSurfaceState.dashboard,
      bodyBuilder: (context, useDesktopSidebar, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          color: _HomeStyle.canvas(brightness),
        ),
        child: switch (_surfaceState) {
          _HomeSurfaceState.connect => _buildConnectState(),
          _HomeSurfaceState.waitingApproval => _buildWaitingApprovalState(),
          _HomeSurfaceState.dashboard => Theme(
              data: Theme.of(context).copyWith(
                  iconButtonTheme: IconButtonThemeData(
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          minimumSize: const Size(44, 44)))),
              child: _buildDashboardState(useDesktopSidebar: useDesktopSidebar),
            ),
        },
      ),
    );
  }

  Widget _buildRecentSessionsHeader() {
    return _SectionHeader(
      title: context.l10n.recentSessionsTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_profiles.length > 1) _buildProfileFilterButton(),
          _CircleActionButton(
            icon: Icons.refresh_rounded,
            onPressed: _reloadHomeData,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileFilterButton() {
    final selected = _profiles
        .where((profile) => profile.id == _selectedProfileId)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: '筛选 Profile',
      initialValue: _selectedProfileId ?? '__all__',
      onSelected: (value) => _selectProfile(value == '__all__' ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: '__all__',
          child: Text('全部 Profile'),
        ),
        for (final profile in _profiles)
          PopupMenuItem<String>(
            value: profile.id,
            child: Text(profile.name),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.layers_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              selected?.name ?? '全部',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
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
    if (_loadingSessions && _recentSessions == null) {
      return const _RecentSessionsSkeleton(key: Key('home-recent-skeleton'));
    }
    if (_recentSessionsError != null && sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.compact),
        child: _ErrorPanel(
          message: l10n.loadSessionsFailed('$_recentSessionsError'),
          onRetry: _reloadHomeData,
          onOpenSettings: _openSettings,
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
                unreadCount: session.unreadCount,
                awaitingApproval:
                    session.status == SessionStatus.awaitingApproval,
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _localBridgeProgress == null ? _openSettings : null,
            icon: const Icon(Icons.settings_outlined),
            label: Text(l10n.changeBridge),
          ),
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
          body: _localBridgeSetup.isSupported
              ? l10n.connectDesktopWelcomeBody
              : l10n.connectWelcomeBody,
        ),
        if (_localBridgeSetup.isSupported) ...[
          LocalBridgeSetupCard(
            progress: _localBridgeProgress,
            failure: _localBridgeFailure,
            onContinueWithAgent: _continueBridgeWithAgent,
            onInstall: (_isAuthorizing || _isSavingBridgeConfig)
                ? null
                : _installLocalBridge,
          ),
          Text(l10n.connectExistingBridgeTitle,
              style: Theme.of(context).textTheme.titleMedium),
          Text(l10n.connectExistingBridgeBody),
        ],
        IgnorePointer(
          ignoring: _localBridgeProgress != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (!_localBridgeSetup.isSupported)
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
                onPressed: (_isAuthorizing ||
                        _isSavingBridgeConfig ||
                        _localBridgeProgress != null)
                    ? null
                    : _startAuthorization,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusControl),
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
              AppSnackBar(content: Text(l10n.copied)),
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
    final display = appSettingsController.settings;
    final brightness = Theme.of(context).brightness;
    final projects =
        (_projects ?? const <ProjectSummary>[]).where(_matchesProject).toList();
    final sessions = (_recentSessions ?? const <SessionSummary>[])
        .map((session) => session.copyWith(
            title: _client.peekSessionById(session.id)?.title ?? session.title))
        .where(_matchesSession)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Stack(children: [
      _ShellScrollView(
          maxWidth: !_showHistory &&
                  display.homeShowMainAgent &&
                  display.homeShowRecentSessions &&
                  display.autoTaskAnalysisEnabled &&
                  display.homeShowRecentTasks
              ? 1440
              : 960,
          onRefresh: _reloadHomeData,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(children: [
                if (!useDesktopSidebar)
                  Expanded(
                    child: Row(children: [
                      SvgPicture.asset(
                        'assets/app-icon-small.svg',
                        key: const Key('home-app-logo'),
                        width: 34,
                        height: 34,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(l10n.appTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4)),
                      ),
                    ]),
                  )
                else
                  const Spacer(),
                IconButton(
                    key: const Key('home-display-settings'),
                    tooltip: agentText(context, '首页显示设置', 'Home display'),
                    onPressed:
                        _savingHomeDisplay ? null : _configureHomeDisplay,
                    icon: const Icon(Icons.dashboard_customize_outlined,
                        size: 21)),
                IconButton(
                    key: const Key('home-history-button'),
                    tooltip: agentText(context, '历史会话', 'History'),
                    onPressed: () =>
                        setState(() => _showHistory = !_showHistory),
                    icon: Icon(
                        _showHistory
                            ? Icons.close_rounded
                            : Icons.history_rounded,
                        size: 21)),
                if (!useDesktopSidebar) ...[
                  IconButton(
                      tooltip: l10n.newSession,
                      onPressed: _newSession,
                      icon: const Icon(Icons.add_rounded, size: 23)),
                  Builder(
                      builder: (context) => IconButton(
                          key: const Key('home-navigation-button'),
                          tooltip: agentText(context, '导航', 'Navigation'),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: const Icon(Icons.menu_rounded, size: 21))),
                ],
              ]),
            ),
            if (_projectsError != null)
              _ErrorPanel(
                  message: l10n.loadProjectsFailed('$_projectsError'),
                  onRetry: _reloadHomeData,
                  onOpenSettings: _openSettings),
            Visibility(
              visible: !_showHistory,
              maintainState: true,
              child: WorkspaceAgentPanel(
                  client: _client,
                  homeSurface: true,
                  projects: _projects ?? const [],
                  homeDashboard: true,
                  showMainAgent: display.homeShowMainAgent,
                  showRecentTracking: display.autoTaskAnalysisEnabled &&
                      display.homeShowRecentTasks,
                  recentSessions: display.homeShowRecentSessions
                      ? Column(
                          key: const Key('home-recent-sessions'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              _buildRecentSessionsHeader(),
                              _buildRecentSessionsContent(
                                  context,
                                  sessions,
                                  sessions.take(_visibleRecentCount).toList(),
                                  brightness),
                            ])
                      : null,
                  emptyHome: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(children: [
                        Text(
                            agentText(context, '首页区域已全部隐藏',
                                'All home sections are hidden'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        TextButton.icon(
                            key: const Key('home-restore-sections'),
                            onPressed: _configureHomeDisplay,
                            icon:
                                const Icon(Icons.dashboard_customize_outlined),
                            label: Text(agentText(context, '选择要展示的区域',
                                'Choose sections to show'))),
                      ])),
                  revision: _lastHomeDataLoadAt),
            ),
            if (_showHistory) ...[
              Text(agentText(context, '历史会话', 'History'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 20),
              _buildDashboardSearchBar(),
              const SizedBox(height: 24),
              if (_hasSearchQuery && projects.isEmpty && sessions.isEmpty)
                _buildHomeSearchEmptyState()
              else ...[
                _buildRecentSessionsHeader(),
                _buildRecentSessionsContent(context, sessions,
                    sessions.take(_visibleRecentCount).toList(), brightness),
                if (projects.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _HomeProjectsPanel(
                      key: const Key('home-history-projects'),
                      projects: (projects.take(4).toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))),
                      brightness: brightness,
                      onOpenProject: (project) =>
                          _openProjectFromHome(context, project),
                      onCreateSessionForProject: _newSessionForProject,
                      onOpenProjects:
                          projects.length > 4 ? _openProjects : null),
                ],
              ],
            ],
          ]),
      if (_isRefreshing)
        const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
                child: LinearProgressIndicator(minHeight: _progressMinHeight))),
    ]);
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
    if (_profiles.length > 1 &&
        session.profileName?.trim().isNotEmpty == true) {
      parts.add('Profile: ${session.profileName}');
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
      showShortcutHint: true,
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

  Future<void> _newSessionForProject(ProjectSummary project) async {
    await startNewSessionFlow(
      context,
      client: _client,
      initialProject: project,
      onSessionClosed: () => _loadProjects(forceRefresh: true),
    );
  }

  Future<void> _newSessionForSession(SessionSummary session) async {
    await startNewSessionFlow(
      context,
      client: _client,
      initialProjects: _projects,
      initialProject: _projectForSession(session),
      onSessionClosed: () => _loadProjects(forceRefresh: true),
    );
  }

  ProjectSummary? _projectForSession(SessionSummary session) {
    final cached = _client.peekProject(session.projectId);
    if (cached != null) {
      return cached;
    }
    for (final project in _projects ?? const <ProjectSummary>[]) {
      if (project.id == session.projectId) {
        return project;
      }
    }
    return null;
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
    SessionCacheScope.watch(context);
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
      recentSessions: _client.peekRecentSessions() ?? const <SessionSummary>[],
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
      onNewSessionForProject: _newSessionForProject,
      onNewSessionForSession: _newSessionForSession,
      agentLabelFor: _client.agentLabelFor,
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
                    ProjectAvatar(
                        name: project.name, iconDataUri: project.iconDataUri),
                    const SizedBox(width: 12),
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
  });

  final String title;
  final String subtitle;

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

void _openProjectFromHome(BuildContext context, ProjectSummary project) {
  Navigator.of(context).pushNamed(
    AppRoutes.project(project.id),
    arguments: project,
  );
}

// Dashboard surfaces stay local to this screen.
abstract final class _HomeStyle {
  static Color canvas(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF111418)
      : const Color(0xFFFAFAF8);
  static Color surface(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF1A212B) : Colors.white;
  static Color border(Brightness brightness) =>
      AppColors.outlineFor(brightness).withValues(alpha: 0.55);
}

class _HomeSurface extends StatelessWidget {
  const _HomeSurface(
      {required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final radius = BorderRadius.circular(18);
    return Material(
      color: _HomeStyle.surface(brightness),
      shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: _HomeStyle.border(brightness))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child)),
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
            ProjectAvatar(name: project.name, iconDataUri: project.iconDataUri),
            const SizedBox(width: 10),
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
                backgroundColor:
                    AppColors.accentBlueFor(brightness).withValues(alpha: 0.07),
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
              label: Text(context.l10n.newLabel),
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
        color: _HomeStyle.border(brightness),
      ),
    );
  }
}

class _HomeProjectsPanel extends StatelessWidget {
  const _HomeProjectsPanel({
    super.key,
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
    return _HomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: context.l10n.recentProjectsTitle,
            trailing: _DesktopSectionMeta(
              label: context.l10n.visibleProjectsCount(projects.length),
            ),
          ),
          const SizedBox(height: AppSpacing.block),
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
                  fontSize: 14,
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
    required this.forkSource,
    required this.accentColor,
    required this.unreadCount,
    required this.awaitingApproval,
    required this.onTap,
  });

  final String title;
  final String? preview;
  final String metadata;
  final String? forkSource;
  final Color accentColor;
  final int unreadCount;
  final bool awaitingApproval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _HomeSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 32,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (awaitingApproval || unreadCount > 0) ...[
                  const SizedBox(height: AppSpacing.textTight),
                  _SessionAttentionIndicator(
                    awaitingApproval: awaitingApproval,
                  ),
                ],
                if (preview?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
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
                const SizedBox(height: 6),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        fontSize: 11,
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

class _SessionAttentionIndicator extends StatelessWidget {
  const _SessionAttentionIndicator({required this.awaitingApproval});

  final bool awaitingApproval;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: awaitingApproval
            ? AppColors.warningFor(brightness)
            : AppColors.accentBlueFor(brightness),
        shape: BoxShape.circle,
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
    this.showShortcutHint = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool showShortcutHint;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: appSettingsController,
        builder: (context, _) {
          final brightness = Theme.of(context).brightness;
          final scope = DesktopShortcutScope.maybeOf(context);
          final showHint = showShortcutHint &&
              supportsDesktopShortcuts &&
              scope != null &&
              resolveDesktopShortcut(
                      appSettingsController.settings.desktopShortcuts,
                      DesktopShortcutAction.search) !=
                  null;
          return TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: controller.text.isEmpty && !showHint
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (controller.text.isNotEmpty)
                        IconButton(
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
                      if (showHint)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: shortcutTooltip(
                                context.l10n.shortcutSearch,
                                DesktopShortcutAction.search),
                            child: TextButton(
                              key: const Key('home-search-shortcut-hint'),
                              onPressed: () =>
                                  scope.onInvoke(DesktopShortcutAction.search),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6)),
                              child: const ActionShortcutHint(
                                  action: DesktopShortcutAction.search),
                            ),
                          ),
                        ),
                    ]),
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
        });
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
    this.onOpenSettings,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onOpenSettings;

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
          Wrap(
            spacing: AppSpacing.compact,
            runSpacing: AppSpacing.compact,
            children: [
              FilledButton(
                onPressed: onRetry,
                child: Text(context.l10n.retry),
              ),
              if (onOpenSettings != null)
                OutlinedButton(
                  onPressed: onOpenSettings,
                  child: Text(context.l10n.changeBridge),
                ),
            ],
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
