import 'dart:async';

import 'package:flutter/material.dart';

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
import '../widgets/create_session_dialog.dart';
import '../widgets/copyable_message.dart';
import '../widgets/new_session_flow.dart';
import 'session_detail_screen.dart';
import 'project_ai_approval_prompt_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project, this.client});

  static const routeName = '/project';

  final ProjectSummary project;
  final BridgeClient? client;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with WidgetsBindingObserver {
  static const double _desktopRailWidth = 304;
  static const _pageSize = 7;
  static const _autoRefreshInterval = Duration(seconds: 5);
  static const _searchDebounceDuration = Duration(milliseconds: 300);
  static const _progressMinHeight = AppSpacing.textStack + AppSpacing.hairline;

  late ProjectSummary _project;
  List<SessionSummary>? _sessions;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _visibleCount = _pageSize;
  Timer? _autoRefreshTimer;
  Timer? _searchDebounceTimer;
  bool _appIsActive = true;

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _project = widget.project;
    final hasCachedProject = _client.peekProject(_project.id) != null;
    final hasCachedSessions = _client.peekProjectSessions(_project.id) != null;
    if (hasCachedProject && hasCachedSessions) {
      unawaited(_loadCachedSessionsThenRefresh());
    } else {
      unawaited(_loadSessions(forceRefresh: true));
    }
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || !_appIsActive || _isRefreshing || _isLoading) {
        return;
      }
      unawaited(_loadSessions(forceRefresh: true));
    });
  }

  Future<void> _loadCachedSessionsThenRefresh() async {
    await _loadSessions();
    if (mounted) {
      await _loadSessions(forceRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _appIsActive;
    _appIsActive = state == AppLifecycleState.resumed;
    if (!wasActive &&
        _appIsActive &&
        mounted &&
        !_isRefreshing &&
        !_isLoading) {
      unawaited(_loadSessions(forceRefresh: true));
    }
  }

  Future<void> _loadSessions({bool forceRefresh = false}) async {
    final previousVisibleCount = _visibleCount;
    setState(() {
      _error = null;
      final availableCount = _sessions?.length ?? previousVisibleCount;
      _visibleCount = availableCount == 0
          ? 0
          : availableCount < _pageSize
              ? availableCount
              : previousVisibleCount;
      if (_sessions == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });
    try {
      final results = await Future.wait<Object>([
        _client.listProjectSessions(
          _project.id,
          forceRefresh: forceRefresh,
        ),
        _client.getProject(_project.id, forceRefresh: forceRefresh),
      ]);
      if (!mounted) {
        return;
      }
      final sessions = results[0] as List<SessionSummary>;
      final project = results[1] as ProjectSummary;
      setState(() {
        _sessions = sessions;
        _project = project;
        final availableCount = sessions.length;
        _visibleCount = availableCount == 0
            ? 0
            : availableCount < _pageSize
                ? availableCount
                : previousVisibleCount;
      });
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

  void _scheduleSearchQueryUpdate(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchQuery = value.trim().toLowerCase();
        _visibleCount = _pageSize;
      });
    });
  }

  void _clearSearchQuery() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _visibleCount = _pageSize;
    });
  }

  Future<void> _reloadSessions() {
    return _loadSessions(forceRefresh: true);
  }

  Widget _buildGitInfoRow(
    String branch,
    ProjectGitStatus? status,
    Brightness brightness,
  ) {
    final l10n = context.l10n;
    final statusColor = status == ProjectGitStatus.dirty
        ? AppColors.warningFor(brightness)
        : AppColors.successFor(brightness);
    final statusLabel =
        status == ProjectGitStatus.dirty ? l10n.gitDirty : l10n.gitClean;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.source_outlined,
          size: 12,
          color: AppColors.mutedSoftFor(brightness),
        ),
        const SizedBox(width: AppSpacing.micro),
        Flexible(
          child: Text(
            branch,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: AppTheme.bodyFontFamily,
                  fontFamilyFallback: AppTheme.monoFontFamilyFallback,
                  color: AppColors.mutedSoftFor(brightness),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (status != null) ...[
          const SizedBox(width: AppSpacing.compact),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.micro,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatSessionUpdatedAt(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  int _statusCount(List<SessionSummary> sessions, SessionStatus status) {
    return sessions.where((session) => session.status == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final sessions = _sessions ?? const <SessionSummary>[];
    final filteredSessions = _filteredSessions(sessions);
    final visibleSessions = _visibleSessions(filteredSessions);
    final recentProjects = _client.peekProjects() ?? const <ProjectSummary>[];
    final recentSessions = _client.peekSessions() ?? const <SessionSummary>[];
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;
    return AppNavigationScaffold(
      backgroundColor: AppColors.boardFor(brightness),
      activeRoute: AppRouteKind.project,
      recentProjects: recentProjects,
      recentSessions: recentSessions,
      activeProjectId: _project.id,
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      onNavigateHome: () => Navigator.of(context).popUntil(
        (route) => route.settings.name == AppRoutes.home || route.isFirst,
      ),
      onNavigateProjects: () =>
          Navigator.of(context).pushNamed(AppRoutes.projects),
      onNavigateSettings: () =>
          Navigator.of(context).pushNamed(AppRoutes.settings),
      onOpenProject: (project) {
        Navigator.of(context).pushNamed(
          AppRoutes.project(project.id),
          arguments: project,
        );
      },
      onOpenSession: (session) {
        debugPrint(
          '[nav] project rail open session id=${session.id} '
          'project=${session.projectId} title=${session.title}',
        );
        Navigator.of(context).pushNamed(
          AppRoutes.session(session.projectId, session.id),
          arguments: session,
        );
      },
      onNewSession: _createSession,
      onNewSessionForProject: _createSessionForRecentProject,
      onNewSessionForSession: _createSessionForRecentSession,
      agentLabelFor: _client.agentLabelFor,
      bodyBuilder: (context, useDesktop, constraints) {
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _reloadSessions,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenX,
                  AppSpacing.card,
                  AppSpacing.screenX,
                  AppSpacing.block,
                ),
                child: useDesktop
                    ? _buildDesktopContent(
                        context,
                        constraints: constraints,
                        sessions: sessions,
                        filteredSessions: filteredSessions,
                        visibleSessions: visibleSessions,
                      )
                    : _buildMobileContent(
                        context,
                        constraints: constraints,
                        sessions: sessions,
                        filteredSessions: filteredSessions,
                        visibleSessions: visibleSessions,
                      ),
              ),
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
      },
    );
  }

  Future<void> _toggleDesktopSidebarCollapsed() async {
    await toggleDesktopNavigationCollapsed();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _buildMobileContent(
    BuildContext context, {
    required BoxConstraints constraints,
    required List<SessionSummary> sessions,
    required List<SessionSummary> filteredSessions,
    required List<SessionSummary> visibleSessions,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: constraints.maxHeight),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: AppSpacing.card),
              _buildProjectSummaryCard(context),
              const SizedBox(height: AppSpacing.card),
              _buildAiApprovalSettingsCard(context),
              const SizedBox(height: AppSpacing.card),
              _buildSearchSection(context),
              const SizedBox(height: AppSpacing.tileY),
              _buildSessionsSection(
                context,
                sessions: sessions,
                filteredSessions: filteredSessions,
                visibleSessions: visibleSessions,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopContent(
    BuildContext context, {
    required BoxConstraints constraints,
    required List<SessionSummary> sessions,
    required List<SessionSummary> filteredSessions,
    required List<SessionSummary> visibleSessions,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: constraints.maxHeight),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDesktopHero(context, sessions),
                    const SizedBox(height: AppSpacing.card),
                    _buildSearchSection(context),
                    const SizedBox(height: AppSpacing.card),
                    _buildSessionsCard(
                      context,
                      sessions: sessions,
                      filteredSessions: filteredSessions,
                      visibleSessions: visibleSessions,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.card),
              SizedBox(
                width: _desktopRailWidth,
                child: _buildDesktopRail(context, sessions),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final useDesktop =
        AppResponsiveLayout.isDesktopWidth(MediaQuery.sizeOf(context).width);
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: 0.6,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!useDesktop) ...[
          Builder(
            builder: (context) => SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.panelDeepFor(brightness),
                  side: BorderSide.none,
                  minimumSize: const Size.square(34),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: context.l10n.openNavigation,
                icon: const Icon(Icons.menu_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
        ],
        Expanded(
          child: AppBackHeader(
            title: context.l10n.sessionsTitle.toUpperCase(),
            titleStyle: titleStyle,
          ),
        ),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              side: BorderSide.none,
              minimumSize: const Size.square(34),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            onPressed: _createSession,
            tooltip: context.l10n.newSession,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHero(
      BuildContext context, List<SessionSummary> sessions) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final activeCount = _statusCount(sessions, SessionStatus.running) +
        _statusCount(sessions, SessionStatus.waiting) +
        _statusCount(sessions, SessionStatus.awaitingApproval);
    return AppCard(
      padding: AppSpacing.blockPadding,
      borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.projectDesk.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: AppColors.mutedSoftFor(brightness),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    Text(
                      _project.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 30,
                        height: 1.04,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    Text(
                      _project.rootPath,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: AppTheme.bodyFontFamily,
                        fontFamilyFallback: AppTheme.monoFontFamilyFallback,
                        color: AppColors.mutedFor(brightness),
                        height: 1.45,
                      ),
                    ),
                    if (_project.gitBranch != null) ...[
                      const SizedBox(height: AppSpacing.stack),
                      _buildGitInfoRow(
                        _project.gitBranch!,
                        _project.gitStatus,
                        brightness,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.block),
              FilledButton.icon(
                onPressed: _createSession,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.l10n.newSession),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.block),
          Wrap(
            spacing: AppSpacing.compact,
            runSpacing: AppSpacing.compact,
            children: [
              _DesktopProjectMetricChip(
                label: context.l10n.allSessions,
                value: '${sessions.length}',
              ),
              _DesktopProjectMetricChip(
                label: context.l10n.inMotion,
                value: '$activeCount',
              ),
              _DesktopProjectMetricChip(
                label: context.l10n.sessionStatusAwaitingApproval,
                value:
                    '${_statusCount(sessions, SessionStatus.awaitingApproval)}',
              ),
              _DesktopProjectMetricChip(
                label: context.l10n.sessionStatusIdle,
                value: '${_statusCount(sessions, SessionStatus.idle)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _project.name,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            _project.rootPath,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: AppTheme.bodyFontFamily,
              fontFamilyFallback: AppTheme.monoFontFamilyFallback,
              color: AppColors.mutedFor(brightness),
            ),
          ),
          if (_project.gitBranch != null) ...[
            const SizedBox(height: AppSpacing.compact),
            _buildGitInfoRow(
              _project.gitBranch!,
              _project.gitStatus,
              brightness,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchSection(BuildContext context) {
    final l10n = context.l10n;
    return _buildSearchBar(
      context,
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: l10n.searchSessions,
      onChanged: (value) {
        _scheduleSearchQueryUpdate(value);
      },
      onClear: _clearSearchQuery,
    );
  }

  Widget _buildSessionsCard(
    BuildContext context, {
    required List<SessionSummary> sessions,
    required List<SessionSummary> filteredSessions,
    required List<SessionSummary> visibleSessions,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return AppCard(
      padding: AppSpacing.cardPadding,
      borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent sessions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.textTight),
                    Text(
                      _searchQuery.isEmpty
                          ? '${sessions.length} sessions in this project'
                          : '${filteredSessions.length} matching results',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedFor(brightness),
                      ),
                    ),
                  ],
                ),
              ),
              if (_searchQuery.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _visibleCount = _pageSize;
                    });
                  },
                  child: Text(context.l10n.clearSearch),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.card),
          _buildSessionsSection(
            context,
            sessions: sessions,
            filteredSessions: filteredSessions,
            visibleSessions: visibleSessions,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsSection(
    BuildContext context, {
    required List<SessionSummary> sessions,
    required List<SessionSummary> filteredSessions,
    required List<SessionSummary> visibleSessions,
  }) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.compact),
        child: _ProjectSessionListSkeleton(
          key: Key('project-sessions-skeleton'),
        ),
      );
    }
    if (_error != null && (_sessions == null || _sessions!.isEmpty)) {
      return _ProjectErrorCard(
        message: l10n.loadSessionsFailed('$_error'),
        onRetry: _reloadSessions,
      );
    }
    if (_sessions == null || _sessions!.isEmpty) {
      return _ProjectEmptyCard(
        onCreateSession: _createSession,
      );
    }
    if (filteredSessions.isEmpty) {
      return const _ProjectSearchEmptyCard();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...visibleSessions.map(
          (session) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.compact),
            child: _SessionSummaryCard(
              session: session,
              statusLabel: _statusLabel(session.status),
              statusColor: _statusColor(session.status, brightness),
              forkSourceLabel: _forkSourceLabel(session, sessions),
              updatedAtLabel: _formatSessionUpdatedAt(session.updatedAt),
              onTap: () async {
                debugPrint(
                  '[nav] project list open session id=${session.id} '
                  'project=${session.projectId} title=${session.title}',
                );
                await Navigator.of(context).pushNamed(
                  AppRoutes.session(_project.id, session.id),
                  arguments: session,
                );
                if (!mounted) {
                  return;
                }
                unawaited(_reloadSessions());
              },
            ),
          ),
        ),
        if (_shouldShowLoadMore(filteredSessions))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.micro),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _visibleCount += _pageSize;
                  });
                },
                child: Text(l10n.loadMoreSessionsLabel),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopRail(
      BuildContext context, List<SessionSummary> sessions) {
    final runningCount = _statusCount(sessions, SessionStatus.running);
    final waitingCount = _statusCount(sessions, SessionStatus.waiting);
    final approvalCount =
        _statusCount(sessions, SessionStatus.awaitingApproval);
    final failedCount = _statusCount(sessions, SessionStatus.failed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopProjectRailCard(
          title: context.l10n.projectContext,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DesktopProjectRailRow(
                label: context.l10n.rootPath,
                value: _project.rootPath,
                mono: true,
              ),
              if (_project.gitBranch != null) ...[
                const SizedBox(height: AppSpacing.stack),
                _DesktopProjectRailRow(
                  label: context.l10n.branch,
                  value: _project.gitBranch!,
                ),
              ],
              if (_project.gitStatus != null) ...[
                const SizedBox(height: AppSpacing.stack),
                _DesktopProjectRailRow(
                  label: context.l10n.gitState,
                  value: _project.gitStatus == ProjectGitStatus.dirty
                      ? context.l10n.gitDirty
                      : context.l10n.gitClean,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        _buildAiApprovalSettingsCard(context),
        const SizedBox(height: AppSpacing.card),
        _DesktopProjectRailCard(
          title: context.l10n.statusMix,
          child: Wrap(
            spacing: AppSpacing.compact,
            runSpacing: AppSpacing.compact,
            children: [
              _DesktopProjectMetricChip(
                  label: context.l10n.sessionStatusRunning,
                  value: '$runningCount'),
              _DesktopProjectMetricChip(
                  label: context.l10n.sessionStatusWaiting,
                  value: '$waitingCount'),
              _DesktopProjectMetricChip(
                label: context.l10n.approvals,
                value: '$approvalCount',
              ),
              _DesktopProjectMetricChip(
                label: context.l10n.sessionStatusFailed,
                value: '$failedCount',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        _DesktopProjectRailCard(
          title: context.l10n.notes,
          child: Text(
            sessions.isEmpty
                ? context.l10n.projectNotesNoActiveSessions
                : approvalCount > 0
                    ? context.l10n.projectNotesWaitingApproval
                    : runningCount > 0 || waitingCount > 0
                        ? context.l10n.projectNotesActiveWork
                        : context.l10n.projectNotesQuiet,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAiApprovalSettingsCard(BuildContext context) {
    return AppCard(
      key: const Key('project-ai-approval-prompt-entry'),
      onTap: () => showProjectAiApprovalPromptDialog(
        context,
        client: _client,
        projectId: _project.id,
      ),
      padding: AppSpacing.tilePadding,
      child: Row(
        children: [
          const Icon(Icons.rule_folder_outlined),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: Text(
              context.l10n.projectAiApprovalPrompt,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return AppCard(
      color: AppColors.panelDeepFor(brightness),
      borderSide: BorderSide(color: AppColors.outlineFor(brightness)),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      child: SizedBox(
        height: 40,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.insetWide,
                  right: AppSpacing.insetWide,
                ),
                child: Center(
                  child: TextField(
                    key: const Key('project-session-search-field'),
                    focusNode: focusNode,
                    controller: controller,
                    onChanged: onChanged,
                    cursorColor: theme.colorScheme.onSurface,
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedFor(brightness),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.tileX,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: AppColors.mutedFor(brightness),
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              Positioned(
                right: AppSpacing.compact,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _SearchClearButton(
                    onTap: onClear,
                    iconColor: AppColors.mutedFor(brightness),
                    hoverColor: AppColors.textSoftFor(brightness),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final result = await showDialog<CreateSessionDialogResult>(
      context: context,
      builder: (context) => CreateSessionDialog(
        client: _client,
        initialProviderId: appSettingsController
            .settings.lastSelectedProviderByProject[_project.id],
      ),
    );
    if (result == null) {
      return;
    }

    final savedProviderSelections = Map<String, String?>.from(
      appSettingsController.settings.lastSelectedProviderByProject,
    )..[_project.id] = result.$3;
    unawaited(
      appSettingsController.save(
        appSettingsController.settings.copyWith(
          lastSelectedAgent: result.$2,
          lastSelectedProviderByProject: savedProviderSelections,
        ),
      ),
    );

    final initialTitle = result.$1?.trim();
    final placeholderSession = SessionSummary(
      id: 'local-draft-${DateTime.now().microsecondsSinceEpoch}',
      projectId: _project.id,
      title: (initialTitle != null && initialTitle.isNotEmpty)
          ? initialTitle
          : l10n.newSession,
      agentId: result.$2,
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
      status: SessionStatus.idle,
      updatedAt: DateTime.now(),
      unreadCount: 0,
      providerId: result.$3,
      reasoningEffort: result.$4,
    );
    final sessionFuture = _client.createSession(
      projectId: _project.id,
      title: result.$1,
      agent: result.$2,
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
      providerId: result.$3,
      reasoningEffort: result.$4,
    );

    await navigator.push(
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
    unawaited(_reloadSessions());
  }

  Future<void> _createSessionForRecentProject(ProjectSummary project) async {
    if (project.id == _project.id) {
      await _createSession();
      return;
    }
    await startNewSessionFlow(
      context,
      client: _client,
      initialProject: project,
    );
  }

  Future<void> _createSessionForRecentSession(SessionSummary session) async {
    if (session.projectId == _project.id) {
      await _createSession();
      return;
    }
    await startNewSessionFlow(
      context,
      client: _client,
      initialProjects: _client.peekProjects(),
      initialProject: _client.peekProject(session.projectId),
    );
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
        return AppColors.successFor(brightness);
      case SessionStatus.running:
        return AppColors.primaryFor(brightness);
      case SessionStatus.awaitingApproval:
        return AppColors.warningFor(brightness);
      case SessionStatus.interrupted:
        return AppColors.mutedFor(brightness);
      case SessionStatus.waiting:
        return AppColors.mutedFor(brightness);
      case SessionStatus.failed:
        return AppColors.errorFor(brightness);
    }
  }

  List<SessionSummary> _filteredSessions(List<SessionSummary> sessions) {
    final query = _searchQuery;
    if (query.isEmpty) {
      return sessions;
    }
    return sessions.where((session) {
      final haystack = '${session.title} ${session.lastMessagePreview ?? ''} '
              '${_client.agentLabelFor(session.agentId)}'
          .toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  List<SessionSummary> _visibleSessions(List<SessionSummary> sessions) {
    if (_searchQuery.isNotEmpty) {
      return sessions;
    }
    return sessions.take(_visibleCount).toList(growable: false);
  }

  bool _shouldShowLoadMore(List<SessionSummary> sessions) {
    return _searchQuery.isEmpty && sessions.length > _visibleCount;
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
    final source = sourceTitle != null && sourceTitle.isNotEmpty
        ? sourceTitle
        : _shortSessionId(sourceId);
    return context.l10n.forkedFromSession(source);
  }

  String _shortSessionId(String sessionId) {
    if (sessionId.length <= 12) {
      return sessionId;
    }
    return '${sessionId.substring(0, 8)}...';
  }
}

class _DesktopProjectMetricChip extends StatelessWidget {
  const _DesktopProjectMetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.compact,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.textTight),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _DesktopProjectRailCard extends StatelessWidget {
  const _DesktopProjectRailCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.stack),
          child,
        ],
      ),
    );
  }
}

class _DesktopProjectRailRow extends StatelessWidget {
  const _DesktopProjectRailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.mutedSoftFor(brightness),
              ),
        ),
        const SizedBox(height: AppSpacing.textTight),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.45,
                fontFamily: mono ? AppTheme.bodyFontFamily : null,
                fontFamilyFallback:
                    mono ? AppTheme.monoFontFamilyFallback : null,
              ),
        ),
      ],
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.session,
    required this.statusLabel,
    required this.statusColor,
    required this.forkSourceLabel,
    required this.updatedAtLabel,
    required this.onTap,
  });

  final SessionSummary session;
  final String statusLabel;
  final Color statusColor;
  final String? forkSourceLabel;
  final String updatedAtLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final theme = Theme.of(context);

    return AppCard(
      padding: AppSpacing.tilePadding,
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.stackTight,
            height: AppSpacing.section,
            margin: const EdgeInsets.only(top: AppSpacing.textStack),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(width: AppSpacing.tileY),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        style: textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.textTight),
                Text(
                  '${bridgeClient.agentLabelFor(session.agentId)} · $updatedAtLabel',
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedFor(theme.brightness),
                  ),
                ),
                if (session.lastMessagePreview?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.textTight),
                  Text(
                    session.lastMessagePreview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(fontSize: 10),
                  ),
                ],
                if (forkSourceLabel != null) ...[
                  const SizedBox(height: AppSpacing.textTight),
                  _ForkSourceLabel(label: forkSourceLabel!),
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

class _ProjectSessionListSkeleton extends StatelessWidget {
  const _ProjectSessionListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _ProjectSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _ProjectSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _ProjectSessionCardSkeleton(),
        SizedBox(height: AppSpacing.compact),
        _ProjectSessionCardSkeleton(),
      ],
    );
  }
}

class _ProjectSessionCardSkeleton extends StatelessWidget {
  const _ProjectSessionCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppSkeletonCard(
      padding: AppSpacing.tilePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.stackTight,
            height: AppSpacing.section,
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
                Row(
                  children: [
                    Expanded(child: AppSkeletonBlock(height: 12)),
                    SizedBox(width: AppSpacing.tileY),
                    AppSkeletonBlock(width: 60, height: 9),
                  ],
                ),
                SizedBox(height: AppSpacing.textTight),
                AppSkeletonBlock(width: 180, height: 9),
                SizedBox(height: AppSpacing.textTight),
                AppSkeletonBlock(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectErrorCard extends StatelessWidget {
  const _ProjectErrorCard({required this.message, required this.onRetry});

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
          FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

class _ProjectEmptyCard extends StatelessWidget {
  const _ProjectEmptyCard({required this.onCreateSession});

  final Future<void> Function() onCreateSession;

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
          Text(context.l10n.noSessionsYet),
          const SizedBox(height: AppSpacing.compact),
          Text(
            context.l10n.noSessionsHelp,
            style: TextStyle(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.stack),
          FilledButton(
            onPressed: onCreateSession,
            child: Text(context.l10n.newSession),
          ),
        ],
      ),
    );
  }
}

class _ProjectSearchEmptyCard extends StatelessWidget {
  const _ProjectSearchEmptyCard();

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
      child: Text(
        context.l10n.noSessionsMatched,
        style: TextStyle(
          color: AppColors.mutedSoftFor(brightness),
          height: 1.4,
        ),
      ),
    );
  }
}

class _SearchClearButton extends StatefulWidget {
  const _SearchClearButton({
    required this.onTap,
    required this.iconColor,
    required this.hoverColor,
  });

  final VoidCallback onTap;
  final Color iconColor;
  final Color hoverColor;

  @override
  State<_SearchClearButton> createState() => _SearchClearButtonState();
}

class _SearchClearButtonState extends State<_SearchClearButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.controlTight),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: _hovered ? widget.hoverColor : widget.iconColor,
          ),
        ),
      ),
    );
  }
}
