import 'dart:async';

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
import '../widgets/app_card.dart';
import '../widgets/copyable_message.dart';
import 'project_detail_screen.dart';
import 'settings_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key, this.client});

  final BridgeClient? client;

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<ProjectSummary>? _projects;
  List<SessionSummary>? _recentSessions;
  Object? _error;
  Object? _recentSessionsError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _authRequestId;
  bool _isWaitingAuth = false;
  Timer? _authPollTimer;

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void initState() {
    super.initState();
    _projects = _client.peekProjects();
    _recentSessions = _takeRecentSessions(_client.peekSessions());
    _isLoading = _projects == null;
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _authPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProjects({bool forceRefresh = false}) async {
    final latestCachedProjects = _client.peekProjects();
    final latestCachedSessions = _takeRecentSessions(_client.peekSessions());
    final shouldRefreshFromNetwork = forceRefresh ||
        latestCachedProjects != null ||
        _projects != null ||
        latestCachedSessions != null ||
        _recentSessions != null;
    setState(() {
      _error = null;
      _recentSessionsError = null;
      _projects = latestCachedProjects ?? _projects;
      _recentSessions = latestCachedSessions ?? _recentSessions;
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
      List<SessionSummary>? recentSessions;
      Object? recentSessionsError;
      try {
        final sessions = await _client.listSessions(
          forceRefresh: shouldRefreshFromNetwork,
        );
        recentSessions = _takeRecentSessions(sessions);
      } on ClientUnauthorizedException {
        rethrow;
      } catch (error) {
        recentSessionsError = error;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
        _recentSessions =
            recentSessions ?? _takeRecentSessions(_client.peekSessions());
        _recentSessionsError = recentSessionsError;
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

  Future<void> _handleUnauthorized() async {
    final pendingRequestId =
        appSettingsController.settings.pendingClientAuthRequestId.trim();
    if (pendingRequestId.isNotEmpty) {
      debugPrint('[auth] Resuming pending request: $pendingRequestId');
      try {
        final status = await _client.checkClientAuthStatus(pendingRequestId);
        if (!mounted) {
          return;
        }
        if (status.isApproved && status.token != null) {
          await _saveApprovedAuthToken(status.token!);
          unawaited(_loadProjects(forceRefresh: true));
          return;
        }
        if (status.isPending) {
          _waitForAuthRequest(pendingRequestId);
          return;
        }
        await _clearPendingAuthRequest();
      } catch (error) {
        debugPrint('[auth] Resume pending request failed: $error');
      }
    }

    await _registerClientAuthRequest();
  }

  Future<void> _registerClientAuthRequest() async {
    debugPrint('[auth] Handling unauthorized, registering client...');
    try {
      final authRequest = await _client.registerClient();
      debugPrint(
          '[auth] Registered! RequestId: ${authRequest.requestId}, Status: ${authRequest.status}');
      if (!mounted) {
        return;
      }
      _waitForAuthRequest(authRequest.requestId);
      unawaited(_savePendingAuthRequest(authRequest.requestId));
    } catch (error) {
      debugPrint('[auth] Registration failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _waitForAuthRequest(String requestId) {
    setState(() {
      _authRequestId = requestId;
      _isWaitingAuth = true;
      _isLoading = false;
      _isRefreshing = false;
    });
    _startAuthPolling();
  }

  Future<void> _savePendingAuthRequest(String requestId) async {
    final settings = appSettingsController.settings;
    try {
      await appSettingsController.save(
        settings.copyWith(pendingClientAuthRequestId: requestId),
      );
    } catch (error) {
      debugPrint('[auth] Failed to persist pending request: $error');
    }
  }

  Future<void> _clearPendingAuthRequest() {
    final settings = appSettingsController.settings;
    return appSettingsController.save(
      settings.copyWith(pendingClientAuthRequestId: ''),
    );
  }

  Future<void> _saveApprovedAuthToken(String token) {
    final settings = appSettingsController.settings;
    return appSettingsController.save(
      settings.copyWith(
        bridgeToken: token,
        pendingClientAuthRequestId: '',
      ),
    );
  }

  void _startAuthPolling() {
    debugPrint('[auth] Starting poll for request: $_authRequestId');
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _authRequestId == null) {
        debugPrint(
            '[auth] Stopping poll: mounted=$mounted, requestId=$_authRequestId');
        timer.cancel();
        return;
      }
      try {
        final status = await _client.checkClientAuthStatus(_authRequestId!);
        debugPrint(
            '[auth] Status: ${status.status}, token: ${status.token != null ? 'present' : 'null'}, isApproved: ${status.isApproved}');
        if (!mounted) {
          return;
        }
        if (status.isApproved && status.token != null) {
          debugPrint('[auth] Approved! Saving token...');
          timer.cancel();
          await _saveApprovedAuthToken(status.token!);
          setState(() {
            _isWaitingAuth = false;
            _authRequestId = null;
          });
          unawaited(_loadProjects(forceRefresh: true));
        }
      } catch (e) {
        debugPrint('[auth] Poll error: $e');
      }
    });
  }

  Future<void> _retryAuth() async {
    setState(() {
      _error = null;
    });
    _authPollTimer?.cancel();
    _authPollTimer = null;
    _clearPendingAuthRequest().catchError((error) {
      debugPrint('[auth] Failed to clear pending request before retry: $error');
    });
    await _registerClientAuthRequest();
  }

  String _formatProjectUpdatedAt(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  String _formatSessionUpdatedAt(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  List<SessionSummary>? _takeRecentSessions(
      Iterable<SessionSummary>? sessions) {
    if (sessions == null) {
      return null;
    }
    return sessions.take(3).toList(growable: false);
  }

  String? _projectNameForSession(SessionSummary session) {
    final activeProject = (_projects ?? const <ProjectSummary>[])
        .where((project) => project.id == session.projectId)
        .cast<ProjectSummary?>()
        .firstWhere((_) => true,
            orElse: () => _client.peekProject(session.projectId));
    return activeProject?.name;
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

  Future<void> _openProject(ProjectSummary project) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.project(project.id),
      arguments: project,
    );
    if (!mounted) {
      return;
    }
    unawaited(_loadProjects());
  }

  Future<void> _openSession(SessionSummary session) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.session(session.projectId, session.id),
      arguments: session,
    );
    if (!mounted) {
      return;
    }
    unawaited(_loadProjects());
  }

  Color _statusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return AppColors.success;
      case SessionStatus.running:
        return AppColors.primary;
      case SessionStatus.awaitingApproval:
        return AppColors.warning;
      case SessionStatus.waiting:
        return AppColors.muted;
      case SessionStatus.failed:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).pushNamed(SettingsScreen.routeName);
              if (!mounted) {
                return;
              }
              setState(() {});
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: _isWaitingAuth
          ? null
          : FloatingActionButton.extended(
              onPressed: _createProject,
              label: Text(l10n.newProject),
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
      body: _isWaitingAuth
          ? _buildAuthWaitingBody()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _reloadProjects,
                  child: ListView(
                    padding: AppSpacing.pagePadding,
                    children: [
                      if (_recentSessions != null &&
                          _recentSessions!.isNotEmpty) ...[
                        Text(
                          l10n.sessionsTitle,
                          style: textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ..._recentSessions!.map(
                          (session) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: AppCard(
                              onTap: () => _openSession(session),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              session.title,
                                              style: textTheme.titleMedium,
                                            ),
                                            if (_projectNameForSession(session)
                                                case final projectName?) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                projectName,
                                                style: textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                          vertical: AppSpacing.xxs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(session.status)
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusSm),
                                          border: Border.all(
                                            color: _statusColor(session.status)
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Text(
                                          _statusLabel(session.status),
                                          style: textTheme.labelSmall?.copyWith(
                                            color: _statusColor(session.status),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    l10n.sessionUpdatedAtWithAgent(
                                      session.agent.name,
                                      _formatSessionUpdatedAt(
                                          session.updatedAt),
                                    ),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  if (session.lastMessagePreview
                                          ?.trim()
                                          .isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      session.lastMessagePreview!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ] else if (_recentSessionsError != null &&
                          !_isLoading) ...[
                        Text(
                          l10n.sessionsTitle,
                          style: textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ErrorCard(
                          message: l10n.loadSessionsFailed(
                            '$_recentSessionsError',
                          ),
                          onRetry: _reloadProjects,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text(
                        l10n.projectsTitle,
                        style: textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xl),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null &&
                          (_projects == null || _projects!.isEmpty))
                        _ErrorCard(
                          message: l10n.loadProjectsFailed('$_error'),
                          onRetry: _reloadProjects,
                        )
                      else if (_projects == null || _projects!.isEmpty)
                        _EmptyCard(onCreateProject: _createProject)
                      else
                        ..._projects!.map(
                          (project) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: AppCard(
                              onTap: () => _openProject(project),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    project.name,
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    project.rootPath,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    l10n.projectUpdatedAt(
                                      _formatProjectUpdatedAt(
                                          project.updatedAt),
                                    ),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isRefreshing)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAuthWaitingBody() {
    final l10n = context.l10n;
    final approvalCommand =
        'omni-code-bridge client-auth approve --request-id $_authRequestId';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 40,
                color: Color(0xFF818CF8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.waitingApprovalTitle,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.waitingApprovalInstallHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.waitingApprovalRunCommand,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1222),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SelectableText(
                              approvalCommand,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFE2E8F0),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: l10n.copy,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: approvalCommand),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.copied)),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final uri = Uri.parse(
                          'https://github.com/omni-stream-ai/omni-code-bridge',
                        );
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          l10n.waitingApprovalDownloadBridge,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF818CF8),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '正在等待审批...',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _retryAuth,
              child: const Text('重新请求'),
            ),
          ],
        ),
      ),
    );
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
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3F1D1D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CopyableMessage(
            message: message,
            copyLabel: context.l10n.copy,
            copiedLabel: context.l10n.copied,
            backgroundColor: const Color(0xFF3F1D1D),
            borderColor: const Color(0xFF7F1D1D),
            iconColor: const Color(0xFFFCA5A5),
            textColor: const Color(0xFFFECACA),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onCreateProject});

  final Future<void> Function() onCreateProject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.noProjectsYet),
          const SizedBox(height: 8),
          Text(
            context.l10n.noProjectsHelp,
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onCreateProject,
            child: Text(context.l10n.createProject),
          ),
        ],
      ),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      title: Text(context.l10n.newProject),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.l10n.projectName),
          ),
          const SizedBox(height: 12),
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
