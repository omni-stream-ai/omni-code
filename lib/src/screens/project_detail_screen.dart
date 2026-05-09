import 'dart:async';

import 'package:flutter/material.dart';

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
import 'session_detail_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project, this.client});

  static const routeName = '/project';

  final ProjectSummary project;
  final BridgeClient? client;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  static const _pageSize = 7;
  static const _autoRefreshInterval = Duration(seconds: 5);
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

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _sessions = _client.peekProjectSessions(_project.id);
    _isLoading = _sessions == null;
    unawaited(_loadSessions());
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || _isRefreshing || _isLoading) {
        return;
      }
      unawaited(_loadSessions(forceRefresh: true));
    });
  }

  Future<void> _loadSessions({bool forceRefresh = false}) async {
    setState(() {
      _error = null;
      _visibleCount = _pageSize;
      if (_sessions == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });
    try {
      final sessions = await _client.listProjectSessions(
        _project.id,
        forceRefresh: forceRefresh,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = sessions;
        final activeProject = _client
            .peekProjects()
            ?.where((project) => project.id == _project.id)
            .cast<ProjectSummary?>()
            .firstWhere((_) => true, orElse: () => null);
        if (activeProject != null) {
          _project = activeProject;
        }
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

  Future<void> _reloadSessions() {
    return _loadSessions(forceRefresh: true);
  }

  String _formatSessionUpdatedAt(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final sessions = _sessions ?? const <SessionSummary>[];
    final filteredSessions = _filteredSessions(sessions);
    final visibleSessions = _visibleSessions(filteredSessions);
    return Scaffold(
      backgroundColor: AppColors.boardFor(brightness),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
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
                              AppCard(
                                padding: AppSpacing.cardPadding,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _project.name,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(fontSize: 14),
                                    ),
                                    const SizedBox(height: AppSpacing.compact),
                                    Text(
                                      _project.rootPath,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontFamily: AppTheme.bodyFontFamily,
                                        fontFamilyFallback:
                                            AppTheme.monoFontFamilyFallback,
                                        color: AppColors.mutedFor(brightness),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.card),
                              _buildSearchBar(
                                context,
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                hintText: l10n.searchSessions,
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value.trim().toLowerCase();
                                    _visibleCount = _pageSize;
                                  });
                                },
                                onClear: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _visibleCount = _pageSize;
                                  });
                                },
                              ),
                              const SizedBox(height: AppSpacing.tileY),
                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(
                                    top: AppSpacing.compact,
                                  ),
                                  child: _ProjectSessionListSkeleton(
                                    key: Key('project-sessions-skeleton'),
                                  ),
                                )
                              else if (_error != null &&
                                  (_sessions == null || _sessions!.isEmpty))
                                _ProjectErrorCard(
                                  message: l10n.loadSessionsFailed('$_error'),
                                  onRetry: _reloadSessions,
                                )
                              else if (_sessions == null || _sessions!.isEmpty)
                                _ProjectEmptyCard(
                                  onCreateSession: _createSession,
                                )
                              else if (filteredSessions.isEmpty)
                                const _ProjectSearchEmptyCard()
                              else ...[
                                ...visibleSessions.map(
                                  (session) => Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.compact,
                                    ),
                                    child: _SessionSummaryCard(
                                      session: session,
                                      statusLabel: _statusLabel(
                                        session.status,
                                      ),
                                      statusColor: _statusColor(
                                        session.status,
                                        brightness,
                                      ),
                                      updatedAtLabel: _formatSessionUpdatedAt(
                                        session.updatedAt,
                                      ),
                                      onTap: () async {
                                        await Navigator.of(context).pushNamed(
                                          AppRoutes.session(
                                            _project.id,
                                            session.id,
                                          ),
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
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.micro,
                                    ),
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
                            ],
                          ),
                        ),
                      ),
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
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: 0.6,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppBackHeader(
            title: 'SESSIONS',
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
        const SizedBox(width: AppSpacing.compact),
        SizedBox(
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
            onPressed: _reloadSessions,
            tooltip: context.l10n.refreshNativeSessions,
            icon: const Icon(Icons.refresh, size: 17),
          ),
        ),
      ],
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
    final result = await showDialog<(String?, String)>(
      context: context,
      builder: (context) => const _CreateSessionDialog(),
    );
    if (result == null) {
      return;
    }

    final initialTitle = result.$1?.trim();
    final placeholderSession = SessionSummary(
      id: 'local-draft-${DateTime.now().microsecondsSinceEpoch}',
      projectId: _project.id,
      title: (initialTitle != null && initialTitle.isNotEmpty)
          ? initialTitle
          : l10n.newSession,
      agent: parseAgentKind(result.$2),
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
      status: SessionStatus.idle,
      updatedAt: DateTime.now(),
      unreadCount: 0,
    );
    final sessionFuture = _client.createSession(
      projectId: _project.id,
      title: result.$1,
      agent: result.$2,
      briefReplyMode: appSettingsController.settings.compressAssistantReplies,
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
        return AppColors.successFor(brightness);
      case SessionStatus.running:
        return AppColors.primaryFor(brightness);
      case SessionStatus.awaitingApproval:
        return AppColors.warningFor(brightness);
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
      final haystack =
          '${session.title} ${session.lastMessagePreview ?? ''} ${session.agent.label}'
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
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.session,
    required this.statusLabel,
    required this.statusColor,
    required this.updatedAtLabel,
    required this.onTap,
  });

  final SessionSummary session;
  final String statusLabel;
  final Color statusColor;
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
                  '${session.agent.label} · $updatedAtLabel',
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
              ],
            ),
          ),
        ],
      ),
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
