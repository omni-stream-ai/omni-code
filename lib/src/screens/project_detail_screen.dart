import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
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

  late ProjectSummary _project;
  List<SessionSummary>? _sessions;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _visibleCount = _pageSize;
  Timer? _autoRefreshTimer;

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_project.name),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(
            onPressed: _reloadSessions,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshNativeSessions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSession,
        label: Text(l10n.newSession),
        icon: const Icon(Icons.add_comment_outlined),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _reloadSessions,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _project.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _project.rootPath,
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.projectIntro,
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                      _visibleCount = _pageSize;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: l10n.searchSessions,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _visibleCount = _pageSize;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.sessionsTitle,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null &&
                    (_sessions == null || _sessions!.isEmpty))
                  _ProjectErrorCard(
                    message: l10n.loadSessionsFailed('$_error'),
                    onRetry: _reloadSessions,
                  )
                else if (_sessions == null || _sessions!.isEmpty)
                  _ProjectEmptyCard(onCreateSession: _createSession)
                else if (_filterSessions(_sessions!).isEmpty)
                  const _ProjectSearchEmptyCard()
                else ...[
                  ..._visibleSessions(_filterSessions(_sessions!)).map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () async {
                          await Navigator.of(context).pushNamed(
                            AppRoutes.session(_project.id, session.id),
                            arguments: session,
                          );
                          if (!mounted) {
                            return;
                          }
                          unawaited(_reloadSessions());
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Ink(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      session.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _statusLabel(session.status),
                                    style: TextStyle(
                                      color: _statusColor(session.status),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.sessionUpdatedAtWithAgent(
                                  session.agent.name,
                                  _formatSessionUpdatedAt(session.updatedAt),
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                              if (session.lastMessagePreview
                                      ?.trim()
                                      .isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 8),
                                Text(
                                  session.lastMessagePreview!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_shouldShowLoadMore(_filterSessions(_sessions!)))
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _visibleCount += _pageSize;
                          });
                        },
                        child: Text(
                          l10n.loadMoreSessions(
                            _filterSessions(_sessions!).length -
                                _visibleSessions(_filterSessions(_sessions!))
                                    .length,
                          ),
                        ),
                      ),
                    ),
                ],
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

  Color _statusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return const Color(0xFF22C55E);
      case SessionStatus.running:
        return const Color(0xFF38BDF8);
      case SessionStatus.awaitingApproval:
        return const Color(0xFFF59E0B);
      case SessionStatus.waiting:
        return const Color(0xFF94A3B8);
      case SessionStatus.failed:
        return const Color(0xFFEF4444);
    }
  }

  List<SessionSummary> _filterSessions(List<SessionSummary> sessions) {
    if (_searchQuery.isEmpty) {
      return sessions;
    }

    return sessions.where((session) {
      final haystack =
          '${session.title} ${session.lastMessagePreview ?? ''}'.toLowerCase();
      return haystack.contains(_searchQuery);
    }).toList();
  }

  List<SessionSummary> _visibleSessions(List<SessionSummary> sessions) {
    if (_searchQuery.isNotEmpty) {
      return sessions;
    }
    return sessions.take(_visibleCount).toList();
  }

  bool _shouldShowLoadMore(List<SessionSummary> sessions) {
    return _searchQuery.isEmpty && sessions.length > _visibleCount;
  }
}

class _ProjectErrorCard extends StatelessWidget {
  const _ProjectErrorCard({required this.message, required this.onRetry});

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
          Text(context.l10n.noSessionsYet),
          const SizedBox(height: 8),
          Text(
            context.l10n.noSessionsHelp,
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Text(
        context.l10n.noSessionsMatched,
        style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
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
          const SizedBox(height: 12),
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
