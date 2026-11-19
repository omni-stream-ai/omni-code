import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'app_snack_bar.dart';
import 'project_avatar.dart';
import 'workspace_agent_composer.dart';
import 'workspace_dispatch_panel.dart';
import 'workspace_conversation_actions.dart';
import 'workspace_home_skeleton.dart';
import 'message_markdown.dart';
import 'workspace_project_context.dart';
import 'session_file_preview.dart';
import '../services/session_file_access.dart';
import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../utils/time_format.dart';
import '../workspace_agent_models.dart';

String agentText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

class WorkspaceAgentPanel extends StatefulWidget {
  const WorkspaceAgentPanel(
      {super.key,
      required this.client,
      this.projects = const [],
      this.projectId,
      this.sessionId,
      this.revision,
      this.homeDashboard = false,
      this.showMainAgent = true,
      this.showRecentTracking = true,
      this.recentSessions,
      this.emptyHome = const SizedBox.shrink(),
      this.homeSurface = false});
  final BridgeClient client;
  final List<ProjectSummary> projects;
  final String? projectId, sessionId;
  final Object? revision;
  final bool homeSurface;
  final bool showRecentTracking;
  final bool homeDashboard;
  final bool showMainAgent;
  final Widget? recentSessions;
  final Widget emptyHome;
  @override
  State<WorkspaceAgentPanel> createState() => _WorkspaceAgentPanelState();
}

class _WorkspaceAgentPanelState extends State<WorkspaceAgentPanel> {
  final _homeConversationKey = GlobalKey();
  WorkspaceAgentSnapshot? _data;
  String? _projectId;
  Object? _error;
  Timer? _poll;
  Timer? _timeTicker;
  bool _loading = false;
  bool _showAll = false;
  String _taskStatusFilter = 'open';
  Object? _expandedTask;
  final _taskOverrides = <(String, String), WorkspaceTask>{};
  final _taskPending = <(String, String)>{};
  bool _openingChat = false;
  WorkspaceAgentComposerController? _homeDraft;
  WorkspaceAgentComposerController get _homeComposer =>
      _homeDraft ??= WorkspaceAgentComposerController(widget.client);
  int _generation = 0;
  int _connectionFailures = 0;
  String? _pendingForceRequestId;
  late int _connectionRevision;
  bool _autoAnalysisEnabled =
      appSettingsController.settings.autoTaskAnalysisEnabled;
  bool get _compact => widget.sessionId != null;
  String? get _chatProjectId => widget.homeDashboard ? null : _projectId;
  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _connectionRevision = widget.client.connectionRevision;
    widget.client.sessionCacheRevision.addListener(_connectionChanged);
    appSettingsController.addListener(_analysisSettingChanged);
    _timeTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_load(analyze: true));
  }

  @override
  void didUpdateWidget(covariant WorkspaceAgentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _homeDraft?.dispose();
      _homeDraft = null;
      oldWidget.client.sessionCacheRevision.removeListener(_connectionChanged);
      widget.client.sessionCacheRevision.addListener(_connectionChanged);
      _connectionRevision = widget.client.connectionRevision;
    }
    if (oldWidget.client != widget.client ||
        oldWidget.projectId != widget.projectId ||
        oldWidget.sessionId != widget.sessionId) {
      _projectId = widget.projectId;
      _data = null;
      _generation++;
      _loading = false;
      _connectionFailures = 0;
      _pendingForceRequestId = null;
      _taskOverrides.clear();
      _expandedTask = null;
      _taskPending.clear();
      unawaited(_load(analyze: true));
    } else if (oldWidget.revision != widget.revision) {
      unawaited(_load(analyze: true));
    }
  }

  String _projectName(WorkspaceTask task) {
    final name = _data?.projects[task.projectId]?.name;
    if (name?.trim().isNotEmpty == true) return name!;
    return widget.projects
            .where((p) => p.id == task.projectId)
            .firstOrNull
            ?.name ??
        '';
  }

  void _analysisSettingChanged() {
    final enabled = appSettingsController.settings.autoTaskAnalysisEnabled;
    if (!mounted || enabled == _autoAnalysisEnabled) return;
    _generation++;
    _poll?.cancel();
    setState(() {
      _autoAnalysisEnabled = enabled;
      _loading = false;
      _pendingForceRequestId = null;
      _connectionFailures = 0;
      _error = null;
      _taskPending.clear();
      _taskOverrides.clear();
      _expandedTask = null;
    });
    if (enabled) unawaited(_load(analyze: true));
  }

  Widget _projectAvatar(WorkspaceTask task) {
    final project = _data?.projects[task.projectId];
    ProjectSummary? listed;
    for (final item in widget.projects) {
      if (item.id == task.projectId) {
        listed = item;
        break;
      }
    }
    return ProjectAvatar(
      name: project?.name ?? listed?.name ?? '',
      iconDataUri: project != null ? project.iconDataUri : listed?.iconDataUri,
      size: _compact ? 28 : 34,
    );
  }

  void _connectionChanged() {
    if (!mounted || _connectionRevision == widget.client.connectionRevision) {
      return;
    }
    _connectionRevision = widget.client.connectionRevision;
    _generation++;
    setState(() {
      _data = null;
      _error = null;
      _loading = false;
      _connectionFailures = 0;
      _pendingForceRequestId = null;
      _taskOverrides.clear();
      _expandedTask = null;
      _taskPending.clear();
    });
    unawaited(_load(analyze: true));
  }

  @override
  void dispose() {
    appSettingsController.removeListener(_analysisSettingChanged);
    widget.client.sessionCacheRevision.removeListener(_connectionChanged);
    _poll?.cancel();
    _timeTicker?.cancel();
    _homeDraft?.dispose();
    super.dispose();
  }

  Future<void> _load(
      {bool analyze = false, bool force = false, String? requestId}) async {
    if (_loading || !_autoAnalysisEnabled) return;
    if (force) _pendingForceRequestId ??= const Uuid().v4();
    if (_pendingForceRequestId != null) {
      analyze = true;
      force = true;
      requestId = _pendingForceRequestId;
    }
    if (analyze) requestId ??= const Uuid().v4();
    final generation = _generation;
    final client = widget.client;
    final projectId = widget.homeSurface ? null : _projectId;
    final sessionId = widget.sessionId;
    var analysisAccepted = !analyze;
    _poll?.cancel();
    setState(() {
      _loading = true;
      if (_connectionFailures == 0) _error = null;
    });
    try {
      if (analyze) {
        await client.workspaceAgentRequest(
            action: '/analyze',
            method: 'POST',
            projectId: projectId,
            force: force,
            requestId: requestId);
        if (!mounted || generation != _generation) return;
        analysisAccepted = true;
        if (_pendingForceRequestId == requestId) _pendingForceRequestId = null;
      }
      final response = await client.workspaceAgentRequest(
          projectId: projectId, sessionId: sessionId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data =
            WorkspaceAgentSnapshot.fromJson(response as Map<String, dynamic>);
        _connectionFailures = 0;
        _error = null;
        for (final task in _data!.tasks) {
          final key = (task.sessionId, task.id);
          final override = _taskOverrides[key];
          if (override?.status == task.status &&
              override?.archived == task.archived) {
            _taskOverrides.remove(key);
          }
        }
      });
      // Refresh derived titles without overwriting newer conversation metadata.
      for (final task in _data!.tasks) {
        final cached = widget.client.peekSessionById(task.sessionId);
        if (cached != null &&
            task.updatedAt == cached.updatedAt &&
            task.sessionTitle.isNotEmpty &&
            task.sessionTitle != cached.title) {
          widget.client.syncSessionSummary(
              cached.copyWith(title: task.sessionTitle),
              authoritative: true);
        }
      }
      _poll = Timer(Duration(seconds: _data!.running ? 2 : 60),
          () => _load(analyze: !(_data?.running ?? false)));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (BridgeClient.isWorkspaceAgentConnectionError(error)) {
        setState(() {
          _connectionFailures++;
          _error = _connectionFailures >= 3 ? error : null;
        });
        final seconds =
            [1, 2, 4, 8, 16, 30][(_connectionFailures - 1).clamp(0, 5)];
        _poll = Timer(
            Duration(seconds: seconds),
            () => _load(
                analyze: !analysisAccepted,
                force: force && !analysisAccepted,
                requestId: requestId));
      } else {
        _pendingForceRequestId = null;
        _connectionFailures = 0;
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  List<WorkspaceTask> get _effectiveTasks =>
      sortWorkspaceTasks((_data?.tasks ?? <WorkspaceTask>[])
          .map((task) => _taskOverrides[(task.sessionId, task.id)] ?? task));

  Future<void> _changeTaskStatus(List<WorkspaceTask> tasks, String status,
      {bool mixedStates = false}) async {
    if (tasks.isEmpty ||
        tasks.any((task) =>
            (!mixedStates && task.status != tasks.first.status) ||
            _taskPending.contains((task.sessionId, task.id)))) {
      return;
    }
    final generation = _generation;
    final client = widget.client;
    final keys = tasks.map((task) => (task.sessionId, task.id)).toSet();
    setState(() => _taskPending.addAll(keys));
    try {
      final response = await client.workspaceAgentRequest(
          action: '/tasks/actions',
          method: 'POST',
          body: {
            'request_id': const Uuid().v4(),
            'expected_status': tasks.first.status,
            'status': status,
            'tasks': tasks
                .map((task) => {
                      'session_id': task.sessionId,
                      'task_id': task.id,
                      if (mixedStates) 'expected_status': task.status
                    })
                .toList(),
          }) as Map<String, dynamic>;
      if (!mounted || generation != _generation || client != widget.client) {
        return;
      }
      final now = DateTime.now();
      setState(() {
        for (final task in tasks) {
          _taskOverrides[(task.sessionId, task.id)] =
              task.withState(status, now);
        }
      });
      final count = tasks.length;
      final message = agentText(
          context,
          '已将 $count 项任务标记为“${_taskStatusText(context, status)}”',
          'Marked $count tasks as ${_taskStatusText(context, status)}');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
          content: Text(message),
          action: SnackBarAction(
              label: agentText(context, '撤销', 'Undo'),
              onPressed: () {
                if (mounted &&
                    generation == _generation &&
                    client == widget.client) {
                  unawaited(
                      _undoTaskStatus(response['action_id'] as String, tasks));
                }
              })));
      unawaited(_load());
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
            isError: true,
            content: Text(agentText(context, '操作未完成，请刷新后重试。',
                'Could not update tasks. Refresh and retry.'))));
        unawaited(_load());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _taskPending.removeAll(keys));
      }
    }
  }

  Future<void> _undoTaskStatus(
      String actionId, List<WorkspaceTask> before) async {
    final generation = _generation;
    final client = widget.client;
    final keys = before.map((task) => (task.sessionId, task.id)).toSet();
    if (keys.any(_taskPending.contains)) return;
    setState(() => _taskPending.addAll(keys));
    try {
      await client.workspaceAgentRequest(
          action: '/tasks/actions/$actionId/undo', method: 'POST');
      if (!mounted || generation != _generation || client != widget.client) {
        return;
      }
      setState(() {
        for (final task in before) {
          _taskOverrides[(task.sessionId, task.id)] = task;
        }
      });
      unawaited(_load());
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
            isError: true,
            content: Text(agentText(context, '无法撤销，任务可能已有新的处理。',
                'Could not undo; the tasks may have newer decisions.'))));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _taskPending.removeAll(keys));
      }
    }
  }

  Widget _buildTaskBundle(WorkspaceTaskBundle bundle,
      {bool prominent = false, bool minimal = false}) {
    final task = bundle.displayTask;
    final related = bundle.isGroup
        ? bundle.members
        : _effectiveTasks
            .where((other) => other.sessionId == task.sessionId)
            .toList();
    final expanded = _expandedTask == bundle.key;
    void toggle() =>
        setState(() => _expandedTask = expanded ? null : bundle.key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _TaskTile(
          task: task,
          projectAvatar: _projectAvatar(task),
          projectName: _projectName(task),
          actionPending: bundle.members.any(
              (member) => _taskPending.contains((member.sessionId, member.id))),
          groupCanComplete: bundle.members
              .where((member) => member.isOpen)
              .every((member) =>
                  member.status == 'awaiting_review' ||
                  member.status == 'blocked'),
          onStatusChanged: bundle.isGroup
              ? (status) => _changeTaskStatus(
                  bundle.members
                      .where((member) =>
                          member.status != status || member.archived)
                      .toList(),
                  status,
                  mixedStates: true)
              : (status) => _changeTaskStatus([task], status),
          relatedCount: related.length > 1 ? related.length : 0,
          isGroup: bundle.isGroup,
          expanded: expanded,
          onRelatedTap: toggle,
          prominent: prominent,
          minimal: minimal,
          onTap: _compact
              ? null
              : widget.homeSurface
                  ? toggle
                  : () => _openTask(bundle.latestSessionTask)),
      if (expanded && widget.homeSurface)
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (task.summary.isNotEmpty && related.length <= 1)
              Text(task.summary),
            TextButton.icon(
                onPressed: () => _openTask(bundle.latestSessionTask),
                icon: const Icon(Icons.arrow_outward_rounded, size: 16),
                label: Text(agentText(context, '进入会话', 'Open conversation'))),
          ]),
        ),
      if (expanded && related.length > 1)
        _RelatedTasks(
            key: ValueKey(bundle.key),
            tasks: related,
            group: bundle.isGroup,
            pending: _taskPending,
            onChange: _changeTaskStatus,
            onOpen: _openTask),
    ]);
  }

  Future<void> _openTask(WorkspaceTask task) async {
    try {
      final detail = await widget.client.getSession(task.sessionId);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
          AppRoutes.session(task.projectId, task.sessionId),
          arguments: detail.session);
      if (mounted) unawaited(_load(analyze: true));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    }
  }

  Future<void> _settings() async {
    final scope = await showDialog<AgentAnalysisScope>(
        context: context,
        builder: (_) =>
            _ScopeDialog(scope: _data?.scope ?? const AgentAnalysisScope()));
    if (scope == null || !mounted) return;
    try {
      await widget.client.workspaceAgentRequest(
          action: '/scope',
          method: 'PUT',
          projectId: _projectId,
          body: scope.toJson());
      if (mounted) await _load(analyze: true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _chat({String? message, bool sendDraft = false}) async {
    if (_openingChat ||
        (sendDraft && message == null && !_homeComposer.hasContent)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _openingChat = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
          settings: const RouteSettings(name: '/workspace-agent'),
          builder: (_) => WorkspaceAgentChat(
              client: widget.client,
              projectId: _chatProjectId,
              projects: widget.projects,
              initialMessage: message,
              composerController: message == null ? _homeComposer : null,
              fullPage: true,
              autoSend: sendDraft)));
      if (mounted) {
        unawaited(_homeDraft?.refreshModels());
        unawaited(_load());
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _showHomeTaskDetails() async {
    final data = _data;
    final hasError = _error != null || data?.errors.isNotEmpty == true;
    final retry = await showDialog<bool>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Text(agentText(context, '任务详情', 'Task details')),
            content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(agentText(context, '分析范围', 'Analysis range'),
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      Text(agentText(
                          context, '本应用会话全部纳入', 'All app conversations')),
                      const SizedBox(height: 6),
                      Text(agentText(
                          context,
                          data?.scope.includeOtherSessions != true
                              ? '不分析外部会话'
                              : '外部：最近 ${data?.scope.recentDays ?? 5} 天 · 最多 ${data?.scope.maxSessions ?? 15} 个会话',
                          data?.scope.includeOtherSessions != true
                              ? 'External conversations excluded'
                              : 'External: last ${data?.scope.recentDays ?? 5} days · Up to ${data?.scope.maxSessions ?? 15} conversations')),
                      if (data != null) ...[
                        const SizedBox(height: 6),
                        Text(agentText(
                            context,
                            '已纳入 ${data.participatedSessions} 个本应用会话 · ${data.externalSessions} 个外部会话',
                            'Included: ${data.participatedSessions} app conversations · ${data.externalSessions} external conversations')),
                      ],
                      if (data != null) ...[
                        const SizedBox(height: 6),
                        Text(agentText(
                            context,
                            '已有分析结果：${data.cachedSessions} / ${data.selectedSessions} 个会话',
                            'Cached analyses: ${data.cachedSessions} / ${data.selectedSessions} conversations')),
                        if (data.running &&
                            _error == null &&
                            _connectionFailures == 0) ...[
                          const SizedBox(height: 16),
                          Text(agentText(context, '后台正在逐个整理会话，已有任务可以继续使用。',
                              'Conversations are being organized in the background. Existing tasks remain available.')),
                        ],
                      ],
                      if (hasError || _connectionFailures > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                            _connectionFailures > 0
                                ? agentText(context, '暂时无法连接 Bridge',
                                    'Bridge is temporarily unavailable')
                                : agentText(context, '部分任务尚未更新',
                                    'Some tasks could not be updated'),
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColors.warningTextFor(
                                    theme.brightness))),
                        const SizedBox(height: 8),
                        if (_connectionFailures > 0)
                          Text(agentText(context, '正在自动重试，已有任务会保留。',
                              'Retrying automatically. Existing tasks are retained.'))
                        else ...[
                          if (_error != null)
                            SelectableText(
                                _error is WorkspaceAgentIncompatibleException
                                    ? context.l10n.localBridgeIncompatibleError
                                    : _error.toString(),
                                style: theme.textTheme.bodySmall),
                          for (final error
                              in data?.errors.values ?? const <dynamic>[])
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SelectableText(error.toString(),
                                    style: theme.textTheme.bodySmall)),
                        ],
                      ],
                    ]))),
            actions: [
              if (hasError || _connectionFailures > 0)
                TextButton(
                    onPressed:
                        _loading ? null : () => Navigator.pop(context, true),
                    child: Text(agentText(context, '重试', 'Retry'))),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(agentText(context, '关闭', 'Close'))),
            ],
          );
        });
    if (retry == true && mounted) unawaited(_load(analyze: true, force: true));
  }

  Widget _buildTaskStatusFilter(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    String label(String value) => switch (value) {
          'open' => agentText(context, '未结束', 'Open tasks'),
          'all' => agentText(context, '全部状态', 'All statuses'),
          _ => _taskStatusText(context, value),
        };
    return PopupMenuButton<String>(
        key: const Key('home-task-status-filter'),
        tooltip: agentText(context, '筛选状态', 'Filter status'),
        initialValue: _taskStatusFilter,
        onSelected: (value) => setState(() {
              _taskStatusFilter = value;
              _showAll = false;
              _expandedTask = null;
            }),
        itemBuilder: (_) => [
              for (final value in ['open', 'all', ..._taskStatuses])
                CheckedPopupMenuItem(
                    key: ValueKey(('task-status-filter-option', value)),
                    value: value,
                    checked: _taskStatusFilter == value,
                    child: Text(label(value))),
            ],
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                    color: muted.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.outlineFor(theme.brightness)
                            .withValues(alpha: .55))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.filter_list_rounded, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(label(_taskStatusFilter),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 11, color: muted))),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, size: 16, color: muted),
                ]))));
  }

  Widget _buildHomeSurface(BuildContext context) {
    if (_data == null &&
        _loading &&
        _error == null &&
        _connectionFailures == 0) {
      return const SizedBox(
          key: ValueKey('home-agent-tasks'),
          child: WorkspaceTasksSkeleton(key: Key('home-tasks-skeleton')));
    }
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final accent = AppColors.accentBlueFor(brightness);
    final muted = AppColors.mutedSoftFor(brightness);
    final line = AppColors.outlineFor(brightness).withValues(alpha: .55);
    final scopedTasks = _effectiveTasks
        .where((task) => _projectId == null || task.projectId == _projectId)
        .toList();
    final tasks = _taskStatusFilter == 'open'
        ? WorkspaceTaskBundle.fromTasks(scopedTasks)
            .where((bundle) =>
                bundle.members.any((task) => !task.archived && task.isOpen))
            .toList()
        : WorkspaceTaskBundle.fromTasks(scopedTasks
            .where((task) =>
                _taskStatusFilter == 'all' || task.status == _taskStatusFilter)
            .toList());
    final visible = _showAll ? tasks : tasks.take(6).toList();
    final running = _data?.running == true;
    final selectedProject =
        widget.projects.where((p) => p.id == _projectId).firstOrNull;
    return Column(
        key: const ValueKey('home-agent-tasks'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Row(children: [
              Flexible(
                  child: Text(agentText(context, '任务', 'Tasks'),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 14,
                          color: muted,
                          fontWeight: FontWeight.w500))),
              if (_data != null) ...[
                const SizedBox(width: 10),
                Text(tasks.length.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ],
            ])),
            IconButton(
                tooltip: agentText(context, '更新任务', 'Refresh tasks'),
                onPressed:
                    _loading ? null : () => _load(analyze: true, force: true),
                icon: Icon(Icons.refresh_rounded, size: 20, color: muted)),
            IconButton(
                tooltip: agentText(context, '分析范围', 'Analysis range'),
                onPressed: _settings,
                icon: Icon(Icons.tune_rounded, size: 20, color: muted)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: LayoutBuilder(builder: (context, constraints) {
              final hasError =
                  _error != null || _data?.errors.isNotEmpty == true;
              final reconnecting = _connectionFailures > 0;
              // Snapshot polling is silent when cached tasks are visible.
              // A failed read must not keep animating an old running snapshot.
              final analyzing = running && _error == null && !reconnecting;
              final initialLoading = _loading && _data == null && !hasError;
              final busy = analyzing || initialLoading || reconnecting;
              final showStatusText = constraints.maxWidth >= 500;
              final statusColor =
                  hasError ? AppColors.warningTextFor(brightness) : muted;
              final status = reconnecting
                  ? agentText(context, '正在重连', 'Reconnecting')
                  : analyzing
                      ? agentText(context, '后台整理中', 'Organizing tasks')
                      : initialLoading
                          ? agentText(context, '加载中', 'Loading')
                          : hasError
                              ? agentText(context, '部分待更新', 'Updates pending')
                              : null;
              return Row(children: [
                Expanded(
                    child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                      if (widget.projects.isNotEmpty)
                        ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * .55),
                            child: PopupMenuButton<String>(
                                tooltip: agentText(
                                    context, '筛选项目', 'Filter projects'),
                                initialValue: _projectId ?? '',
                                itemBuilder: (context) => [
                                      PopupMenuItem(
                                          value: '',
                                          child: Text(agentText(context, '全部项目',
                                              'All projects'))),
                                      for (final project in widget.projects)
                                        PopupMenuItem(
                                            value: project.id,
                                            child: Text(project.name)),
                                    ],
                                onSelected: (value) {
                                  setState(() {
                                    _projectId = value.isEmpty ? null : value;
                                    _data = null;
                                    _generation++;
                                    _loading = false;
                                    _connectionFailures = 0;
                                    _pendingForceRequestId = null;
                                    _taskOverrides.clear();
                                    _expandedTask = null;
                                    _taskPending.clear();
                                  });
                                  unawaited(_load(analyze: true));
                                },
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                              child: Text(
                                                  selectedProject?.name ??
                                                      agentText(context, '全部项目',
                                                          'All projects'),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          color: muted))),
                                          const SizedBox(width: 4),
                                          Icon(Icons.expand_more_rounded,
                                              size: 16, color: muted),
                                        ])))),
                      _buildTaskStatusFilter(context),
                    ])),
                if (busy)
                  Tooltip(
                      message: status!,
                      child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: reconnecting ? statusColor : accent))),
                if (showStatusText && status != null) ...[
                  const SizedBox(width: 8),
                  Text(status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: statusColor)),
                ],
                IconButton(
                    key: const Key('home-task-details-button'),
                    tooltip: agentText(context, '任务详情', 'Task details'),
                    onPressed: _showHomeTaskDetails,
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        side: BorderSide.none,
                        minimumSize: const Size(36, 36)),
                    icon: Icon(
                        hasError
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        size: 17,
                        color: statusColor)),
              ]);
            }),
          ),
          if (tasks.isEmpty &&
              !running &&
              !_loading &&
              _connectionFailures == 0 &&
              _error == null &&
              _data?.errors.isEmpty == true)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  Icon(Icons.task_alt_rounded, size: 28, color: muted),
                  const SizedBox(height: 12),
                  Text(
                      _taskStatusFilter == 'open'
                          ? agentText(context, '暂时没有待办，留一点空间给新的想法。',
                              'Nothing pending. A little space for your next idea.')
                          : agentText(context, '没有符合当前状态的任务',
                              'No tasks match this status'),
                      textAlign: TextAlign.center,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: muted)),
                ])),
          for (final task in visible) ...[
            Divider(height: 1, color: line),
            _buildTaskBundle(task, prominent: true, minimal: true),
          ],
          if (tasks.length > 6)
            _TaskListToggle(
                expanded: _showAll,
                onPressed: () => setState(() => _showAll = !_showAll)),
          const SizedBox(height: 32),
        ]);
  }

  Widget _buildHomeAgentEntry(BuildContext context) => ListenableBuilder(
      listenable: _homeComposer,
      builder: (context, _) => _homeComposer.isInitializing
          ? const SizedBox(
              key: Key('home-main-agent-conversation'),
              child: WorkspaceMainAgentSkeleton(
                  key: Key('home-main-agent-skeleton')))
          : _buildReadyHomeAgentEntry(context));

  Widget _buildReadyHomeAgentEntry(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accentBlueFor(theme.brightness);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    return Column(
      key: const Key('home-main-agent-conversation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: accent.withValues(alpha: .10)),
              child: Icon(Icons.auto_awesome_rounded, size: 19, color: accent)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(agentText(context, '助手', 'Assistant'),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.3)),
                const SizedBox(height: 3),
                Text(
                    agentText(context, '聊聊想法，继续手头的事',
                        'A new idea, or the next step.'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ])),
          WorkspaceConversationActions(
              client: widget.client,
              projectId: _chatProjectId,
              projects: widget.projects,
              enabled: !_openingChat,
              onConversationOpened: () => unawaited(_chat())),
          IconButton(
              key: const Key('home-agent-open-conversation'),
              tooltip: agentText(context, '打开助手对话', 'Open conversation'),
              onPressed: _openingChat ? null : () => unawaited(_chat()),
              icon: const Icon(Icons.arrow_outward_rounded, size: 19)),
        ]),
        const SizedBox(height: 12),
        WorkspaceAgentComposer(
            controller: _homeComposer,
            projects: widget.projects,
            projectId: _chatProjectId,
            onConversationOpened: () => unawaited(_chat()),
            home: true,
            prominent: true,
            maxLines: 2,
            enabled: !_openingChat,
            onSend: () => unawaited(_chat(sendDraft: true))),
        WorkspaceDispatchPanel(
            key: Key(_autoAnalysisEnabled
                ? 'home-main-agent-linked-tasks'
                : 'home-main-agent-linked-sessions'),
            client: widget.client,
            projectId: _chatProjectId,
            projects: widget.projects,
            compact: true,
            dense: true,
            recentTaskLimit: 2,
            showSessionsOnly: !_autoAnalysisEnabled,
            onConversationOpened: () => unawaited(_chat())),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.homeSurface) {
      final showTasks = _autoAnalysisEnabled && widget.showRecentTracking;
      if (widget.homeDashboard) {
        return LayoutBuilder(builder: (context, constraints) {
          final conversation = Visibility(
              key: _homeConversationKey,
              visible: widget.showMainAgent,
              maintainState: true,
              child: _buildHomeAgentEntry(context));
          final tasks = _buildHomeSurface(context);
          final secondary = <Widget>[
            if (widget.recentSessions != null) widget.recentSessions!,
            if (showTasks) tasks,
          ];
          Widget stack(List<Widget> children) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0) const SizedBox(height: 24),
                  child,
                ]
              ]);
          Widget row(List<Widget> children) =>
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0) const SizedBox(width: 24),
                  Expanded(child: child),
                ]
              ]);
          Widget layout;
          if (!widget.showMainAgent && secondary.isEmpty) {
            layout = widget.emptyHome;
          } else {
            layout = stack([
              if (widget.showMainAgent) conversation,
              if (secondary.isNotEmpty)
                if (secondary.length == 2 && constraints.maxWidth >= 760)
                  row(secondary)
                else
                  stack(secondary),
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.showMainAgent) conversation,
                layout,
              ]);
        });
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showMainAgent) _buildHomeAgentEntry(context),
        if (widget.showMainAgent && showTasks) const SizedBox(height: 24),
        if (showTasks) _buildHomeSurface(context),
      ]);
    }
    if (!_autoAnalysisEnabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = _data;
    final tasks = WorkspaceTaskBundle.fromTasks(_effectiveTasks)
        .where((bundle) => bundle.members
            .any((task) => !task.archived && (_compact || task.isOpen)))
        .toList();
    final visible = _showAll ? tasks : tasks.take(_compact ? 5 : 6).toList();
    final accent = AppColors.accentBlueFor(theme.brightness);
    final running = data?.running == true;
    return Container(
      key: ValueKey(_compact ? 'session-agent-tasks' : 'home-agent-tasks'),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    accent.withValues(alpha: .08), colors.surfaceContainerLow),
                colors.surfaceContainerLow
              ]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: .19))),
      child: Padding(
          padding: EdgeInsets.all(_compact ? 16 : 22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.auto_awesome_rounded,
                      color: accent, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        agentText(context, _compact ? '会话任务' : '待办任务',
                            _compact ? 'Conversation tasks' : 'Your tasks'),
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: _compact ? null : 22)),
                    const SizedBox(height: 3),
                    Text(
                        agentText(context, '工作区助手 · 从对话整理进展',
                            'Workspace agent · Progress from conversations'),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ])),
              IconButton(
                  tooltip: agentText(context, '分析范围', 'Analysis range'),
                  onPressed: _settings,
                  icon: const Icon(Icons.tune_rounded, size: 20)),
            ]),
            const SizedBox(height: 16),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!_compact && widget.projects.isNotEmpty)
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_projectId),
                          initialValue: _projectId ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          items: [
                            DropdownMenuItem(
                                value: '',
                                child: Text(agentText(
                                    context, '全部项目', 'All projects'))),
                            ...widget.projects.map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name,
                                    overflow: TextOverflow.ellipsis)))
                          ],
                          onChanged: (value) {
                            setState(() {
                              _projectId = value == '' ? null : value;
                              _data = null;
                              _generation++;
                              _loading = false;
                              _connectionFailures = 0;
                              _pendingForceRequestId = null;
                              _taskOverrides.clear();
                              _expandedTask = null;
                              _taskPending.clear();
                            });
                            unawaited(_load(analyze: true));
                          },
                        )),
                  Text(agentText(context, '本应用会话全部纳入', 'All app conversations'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  Text(
                      agentText(
                          context,
                          data?.scope.includeOtherSessions != true
                              ? '不分析外部会话'
                              : '外部：最近 ${data?.scope.recentDays ?? 5} 天 · 最多 ${data?.scope.maxSessions ?? 15} 个会话',
                          data?.scope.includeOtherSessions != true
                              ? 'External conversations excluded'
                              : 'External: last ${data?.scope.recentDays ?? 5} days · Up to ${data?.scope.maxSessions ?? 15} conversations'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ]),
            if (data != null) ...[
              const SizedBox(height: 6),
              Text(
                  agentText(
                      context,
                      '已纳入 ${data.participatedSessions} 个本应用会话 · ${data.externalSessions} 个外部会话',
                      'Included: ${data.participatedSessions} app conversations · ${data.externalSessions} external conversations'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
            const SizedBox(height: 14),
            if (_connectionFailures > 0 && _connectionFailures < 3) ...[
              Text(
                  agentText(context, '连接暂时中断，正在重试…',
                      'Connection interrupted. Reconnecting…'),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            if (running || (_loading && data == null)) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 10),
              Text(
                  agentText(
                      context, '正在整理会话任务…', 'Organizing conversation tasks…'),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            if (_error != null || data?.errors.isNotEmpty == true) ...[
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _connectionFailures > 0
                                ? agentText(context, '暂时无法连接 Bridge',
                                    'Bridge is temporarily unavailable')
                                : agentText(context, '部分任务尚未更新',
                                    'Some tasks could not be updated'),
                            style: TextStyle(
                                color: colors.error,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            _connectionFailures > 0
                                ? agentText(context, '正在自动重试，已有任务会保留。',
                                    'Retrying automatically. Existing tasks are retained.')
                                : _error?.toString() ??
                                    data!.errors.values.first.toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ])),
              const SizedBox(height: 10),
            ],
            if (tasks.isEmpty &&
                !running &&
                !_loading &&
                _connectionFailures == 0 &&
                _error == null &&
                data?.errors.isEmpty == true)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(children: [
                    Icon(
                        _error != null || data?.errors.isNotEmpty == true
                            ? Icons.cloud_off_outlined
                            : Icons.task_alt_rounded,
                        size: 30,
                        color: colors.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text(
                        agentText(
                            context,
                            _compact ? '当前范围内还没有此会话的任务记录' : '当前范围内没有待继续的任务',
                            _compact
                                ? 'No task memory for this conversation in the current range'
                                : 'No open tasks in the current range'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 5),
                    Text(
                        agentText(context, '可以调整分析范围，或直接询问助手。',
                            'Adjust the range or ask your workspace agent.'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ])),
            LayoutBuilder(builder: (context, constraints) {
              final twoColumns = !_compact && constraints.maxWidth >= 760;
              final width = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final task in visible)
                  SizedBox(
                      width: width,
                      child: _buildTaskBundle(task, prominent: !_compact)),
              ]);
            }),
            if (tasks.length > (_compact ? 5 : 6))
              _TaskListToggle(
                  expanded: _showAll,
                  onPressed: () => setState(() => _showAll = !_showAll)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                          backgroundColor: accent.withValues(alpha: .14),
                          foregroundColor: accent),
                      onPressed: _chat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 18),
                      label: Text(agentText(
                          context, '问问工作区助手', 'Ask workspace agent')))),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: agentText(context, '更新任务', 'Refresh tasks'),
                  onPressed:
                      _loading ? null : () => _load(analyze: true, force: true),
                  icon: const Icon(Icons.refresh_rounded))
            ]),
          ])),
    );
  }
}

class _TaskListToggle extends StatelessWidget {
  const _TaskListToggle({required this.expanded, required this.onPressed});
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final muted = AppColors.mutedSoftFor(brightness);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          key: const Key('task-list-toggle'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            foregroundColor: muted,
            backgroundColor: muted.withValues(alpha: .045),
            side: BorderSide(
                color: AppColors.outlineFor(brightness).withValues(alpha: .55)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18),
          label: Text(expanded
              ? agentText(context, '收起', 'Show less')
              : agentText(context, '查看全部任务', 'Show all tasks')),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile(
      {required this.task,
      required this.projectAvatar,
      this.projectName = '',
      this.actionPending = false,
      this.onStatusChanged,
      this.relatedCount = 0,
      this.isGroup = false,
      this.groupCanComplete = true,
      this.expanded = false,
      this.onRelatedTap,
      this.onTap,
      this.prominent = false,
      this.minimal = false});
  final WorkspaceTask task;
  final Widget projectAvatar;
  final String projectName;
  final bool actionPending, isGroup, expanded, groupCanComplete;
  final int relatedCount;
  final ValueChanged<String>? onStatusChanged;
  final VoidCallback? onRelatedTap;
  final VoidCallback? onTap;
  final bool prominent, minimal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final language = Localizations.localeOf(context).languageCode;
    final now = DateTime.now();
    final elapsed = task.elapsedAt(now);
    final updated = task.lastUpdatedAt;
    final relative = updated == null
        ? null
        : formatRelativeTime(updated, now: now, languageCode: language);
    final duration = elapsed == null
        ? null
        : formatElapsedDuration(elapsed, languageCode: language);
    Widget status() => _TaskStatusIndicator(status: task.status);
    Widget meta(IconData icon, String text, {String? tooltip}) {
      final content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: muted),
        const SizedBox(width: 5),
        Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontSize: 11, color: muted, height: 1.4))),
      ]);
      return tooltip == null
          ? content
          : Tooltip(message: tooltip, child: content);
    }

    return Material(
      color:
          minimal ? Colors.transparent : colors.surface.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
              padding: minimal
                  ? const EdgeInsets.symmetric(vertical: 14, horizontal: 4)
                  : EdgeInsets.all(prominent ? 18 : 13),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: projectAvatar),
                const SizedBox(width: 11),
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final inlineStatus = constraints.maxWidth >= 480;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(task.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: prominent ? 14 : null,
                                              height: 1.4))),
                              if (inlineStatus) ...[
                                const SizedBox(width: 16),
                                status()
                              ],
                            ]),
                        if (task.summary.trim().isNotEmpty && !minimal) ...[
                          const SizedBox(height: 5),
                          Text(task.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w400,
                                  fontSize: prominent ? 13 : null,
                                  height: 1.5)),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                            spacing: 14,
                            runSpacing: 7,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (!inlineStatus) status(),
                              if (projectName.trim().isNotEmpty)
                                meta(Icons.folder_open_rounded, projectName),
                              if (duration != null)
                                meta(
                                    Icons.hourglass_empty_rounded,
                                    agentText(
                                        context,
                                        '${task.isOpen ? '持续' : '历时'} $duration',
                                        'Elapsed $duration'),
                                    tooltip: agentText(
                                        context,
                                        '从任务提出起计算，包含等待时间。',
                                        'Wall-clock time since the task was requested, including waits.')),
                              if (relative != null)
                                meta(
                                    Icons.schedule_rounded,
                                    task.taskUpdatedAt != null
                                        ? relative
                                        : agentText(context, '会话 $relative',
                                            'Conversation $relative')),
                              if (task.stale)
                                meta(Icons.update_rounded,
                                    agentText(context, '待同步', 'Needs sync')),
                              if (relatedCount > 1)
                                TextButton.icon(
                                  key: ValueKey((
                                    'related-tasks',
                                    task.sessionId,
                                    task.id
                                  )),
                                  onPressed: onRelatedTap,
                                  style: TextButton.styleFrom(
                                      foregroundColor: muted,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      minimumSize: const Size(0, 32)),
                                  icon: Icon(
                                      expanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 16),
                                  label: Text(
                                      isGroup
                                          ? agentText(
                                              context,
                                              '$relatedCount 个子任务',
                                              '$relatedCount subtasks')
                                          : agentText(
                                              context,
                                              '会话任务 $relatedCount',
                                              '$relatedCount session tasks'),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: muted)),
                                ),
                            ]),
                      ]);
                })),
                if (onStatusChanged != null) ...[
                  const SizedBox(width: 4),
                  _TaskActionMenu(
                      task: task,
                      pending: actionPending,
                      group: isGroup,
                      canComplete: groupCanComplete,
                      onSelected: onStatusChanged!),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                      isGroup
                          ? (expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded)
                          : Icons.arrow_outward_rounded,
                      size: 17,
                      color: muted),
                ],
              ]))),
    );
  }
}

const _taskStatuses = [
  'pending',
  'in_progress',
  'awaiting_review',
  'blocked',
  'completed',
  'cancelled'
];

String _taskStatusText(BuildContext context, String status) => switch (status) {
      'awaiting_review' => agentText(context, '待验收', 'Awaiting review'),
      'in_progress' => agentText(context, '进行中', 'In progress'),
      'blocked' => agentText(context, '待解决', 'Blocked'),
      'completed' => agentText(context, '已完成', 'Completed'),
      'cancelled' => agentText(context, '已取消', 'Cancelled'),
      _ => agentText(context, '待继续', 'Pending'),
    };

class _TaskStatusIndicator extends StatelessWidget {
  const _TaskStatusIndicator({required this.status, this.showLabel = true});
  final String status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final (icon, color) = switch (status) {
      'completed' => (Icons.check_circle_outline, const Color(0xff369e77)),
      'cancelled' => (Icons.remove_circle_outline, muted),
      'awaiting_review' => (Icons.fact_check_outlined, const Color(0xff8d85d6)),
      'blocked' => (Icons.pause_circle_outline, const Color(0xffcf8a36)),
      'in_progress' => (
          Icons.timelapse_rounded,
          AppColors.accentBlueFor(theme.brightness)
        ),
      _ => (Icons.radio_button_unchecked, muted),
    };
    final label = _taskStatusText(context, status);
    if (!showLabel) {
      return Tooltip(
          message: label,
          child: Icon(icon, size: 17, color: color, semanticLabel: label));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600))),
    ]);
  }
}

class _TaskActionMenu extends StatelessWidget {
  const _TaskActionMenu(
      {required this.task,
      required this.pending,
      required this.onSelected,
      this.group = false,
      this.canComplete = true});
  final WorkspaceTask task;
  final bool pending;
  final bool group, canComplete;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedSoftFor(Theme.of(context).brightness);
    PopupMenuItem<String> item(
            String value, IconData icon, String zh, String en) =>
        PopupMenuItem(
            value: value,
            child: Row(children: [
              Icon(icon, size: 18),
              const SizedBox(width: 10),
              Text(agentText(context, zh, en))
            ]));
    return PopupMenuButton<String>(
      key: ValueKey(
          (group ? 'group-actions' : 'task-actions', task.sessionId, task.id)),
      tooltip: agentText(context, '任务操作', 'Task actions'),
      enabled: !pending,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
          foregroundColor: muted,
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          shape: const CircleBorder()),
      constraints: const BoxConstraints(minWidth: 160),
      icon: pending
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))
          : Icon(Icons.more_horiz_rounded, size: 20, color: muted),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (canComplete && task.status == 'awaiting_review' && !task.archived)
          item(
              'completed',
              Icons.check_circle_outline_rounded,
              group ? '整组验收通过' : '验收通过',
              group ? 'Accept group' : 'Accept task'),
        if (canComplete && task.status == 'blocked' && !task.archived)
          item(
              'completed',
              Icons.check_circle_outline_rounded,
              group ? '整组标记完成' : '标记完成',
              group ? 'Complete group' : 'Mark complete'),
        if (task.isOpen && !task.archived)
          item('cancelled', Icons.cancel_outlined, group ? '取消整组任务' : '取消任务',
              group ? 'Cancel group' : 'Cancel task'),
        if (!task.isOpen || task.archived)
          item(
              !group && task.status == 'completed'
                  ? 'awaiting_review'
                  : 'pending',
              Icons.undo_rounded,
              '重新打开',
              'Reopen task'),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
            enabled: false,
            child: Text(agentText(context, group ? '整组修改状态' : '修改状态',
                group ? 'Change group status' : 'Change status'))),
        for (final status in _taskStatuses)
          PopupMenuItem<String>(
              key: ValueKey(('set-task-status', status)),
              value: status,
              enabled: group || task.archived || task.status != status,
              child: Row(children: [
                Icon(
                    task.status == status ? Icons.check : Icons.circle_outlined,
                    size: 18),
                const SizedBox(width: 10),
                Text(_taskStatusText(context, status)),
              ])),
      ],
    );
  }
}

class _RelatedTasks extends StatefulWidget {
  const _RelatedTasks(
      {super.key,
      required this.tasks,
      required this.group,
      required this.pending,
      required this.onChange,
      required this.onOpen});
  final List<WorkspaceTask> tasks;
  final bool group;
  final Set<(String, String)> pending;
  final void Function(List<WorkspaceTask>, String) onChange;
  final ValueChanged<WorkspaceTask> onOpen;
  @override
  State<_RelatedTasks> createState() => _RelatedTasksState();
}

class _RelatedTasksState extends State<_RelatedTasks> {
  String? _status;
  static const _statuses = [
    'awaiting_review',
    'in_progress',
    'blocked',
    'pending',
    'completed',
    'cancelled'
  ];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final foreground = AppColors.textFor(theme.brightness);
    final line = AppColors.outlineFor(theme.brightness).withValues(alpha: .55);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final selected = _status ??
        _statuses.firstWhere(
            (status) => widget.tasks.any((task) => task.status == status),
            orElse: () => widget.tasks.first.status);
    final tasks =
        widget.tasks.where((task) => task.status == selected).toList();
    final busy =
        tasks.any((task) => widget.pending.contains((task.sessionId, task.id)));
    final actionStyle = TextButton.styleFrom(
        foregroundColor: muted,
        textStyle: theme.textTheme.bodySmall,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    return Container(
      key: const Key('related-task-panel'),
      margin: EdgeInsets.fromLTRB(narrow ? 16 : 48, 0, 4, 20),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
                widget.group
                    ? agentText(context, '原任务', 'Original tasks')
                    : agentText(
                        context, '会话关联任务', 'Tasks in this conversation'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted))),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final status in _statuses)
            if (widget.tasks.any((task) => task.status == status) ||
                status == selected)
              Semantics(
                  selected: status == selected,
                  child: TextButton(
                      key: ValueKey(('related-status', status)),
                      onPressed: () => setState(() => _status = status),
                      style: TextButton.styleFrom(
                          foregroundColor:
                              status == selected ? foreground : muted,
                          backgroundColor: status == selected
                              ? muted.withValues(alpha: .12)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7)),
                          textStyle: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: status == selected
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                      child: Text(
                          '${_taskStatusText(context, status)}  ${widget.tasks.where((task) => task.status == status).length}'))),
        ]),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                  agentText(context, '该状态暂无任务', 'No tasks with this status'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted))),
        for (final task in tasks)
          _RelatedTaskRow(
              key: ValueKey(('related-task', task.sessionId, task.id)),
              task: task,
              pending: widget.pending.contains((task.sessionId, task.id)),
              onOpen: () => widget.onOpen(task),
              onChange: (status) => widget.onChange([task], status)),
        const SizedBox(height: 8),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<String>(
                  key: const Key('set-related-task-status'),
                  tooltip: agentText(
                      context, '批量修改状态', 'Change status for selected tasks'),
                  enabled: tasks.isNotEmpty && !busy,
                  onSelected: (status) => widget.onChange(tasks, status),
                  itemBuilder: (_) => [
                        for (final status in _taskStatuses)
                          PopupMenuItem(
                              value: status,
                              enabled: status != selected,
                              child: Text(_taskStatusText(context, status)))
                      ],
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: Text(
                                agentText(context, '批量修改状态', 'Change status'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: tasks.isEmpty || busy
                                        ? muted.withValues(alpha: .5)
                                        : muted))),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more_rounded, size: 14, color: muted),
                      ]))),
              if (selected == 'awaiting_review' || selected == 'blocked')
                TextButton.icon(
                    key: const Key('accept-related-tasks'),
                    style: actionStyle.copyWith(
                        foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? muted.withValues(alpha: .5)
                                : foreground)),
                    onPressed: tasks.isEmpty || busy
                        ? null
                        : () => widget.onChange(tasks, 'completed'),
                    icon: const Icon(Icons.done_all_rounded, size: 15),
                    label: Text(selected == 'blocked'
                        ? agentText(context, '一键完成', 'Complete this status')
                        : agentText(context, '一键验收', 'Accept this status'))),
              if (selected != 'completed' && selected != 'cancelled')
                TextButton.icon(
                    key: const Key('cancel-related-tasks'),
                    style: actionStyle,
                    onPressed: tasks.isEmpty || busy
                        ? null
                        : () => widget.onChange(tasks, 'cancelled'),
                    icon: const Icon(Icons.cancel_outlined, size: 15),
                    label:
                        Text(agentText(context, '一键取消', 'Cancel this status'))),
            ]),
      ]),
    );
  }
}

class _RelatedTaskRow extends StatelessWidget {
  const _RelatedTaskRow(
      {super.key,
      required this.task,
      required this.pending,
      required this.onOpen,
      required this.onChange});
  final WorkspaceTask task;
  final bool pending;
  final VoidCallback onOpen;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final canAccept = task.status == 'awaiting_review';
    final showSummary = task.summary.trim().isNotEmpty &&
        task.summary.trim() != task.title.trim();
    Widget acceptAction() => TextButton.icon(
        key: ValueKey(('accept-related-task', task.sessionId, task.id)),
        onPressed: pending ? null : () => onChange('completed'),
        style: TextButton.styleFrom(
            foregroundColor: AppColors.textFor(theme.brightness),
            disabledForegroundColor: muted.withValues(alpha: .5),
            textStyle: theme.textTheme.bodySmall,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(Icons.check_rounded, size: 15),
        label: Text(agentText(context, '验收', 'Accept')));
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: AppColors.outlineFor(theme.brightness)
                        .withValues(alpha: .35)))),
        child: LayoutBuilder(builder: (context, constraints) {
          final inlineAction = constraints.maxWidth >= 480 &&
              MediaQuery.textScalerOf(context).scale(14) < 20;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _TaskStatusIndicator(
                    status: task.status, showLabel: false)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  InkWell(
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.title,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        height: 1.45)),
                                if (showSummary) ...[
                                  const SizedBox(height: 5),
                                  Text(task.summary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: muted, height: 1.5)),
                                ],
                              ]))),
                  if (canAccept && !inlineAction) acceptAction(),
                ])),
            const SizedBox(width: 8),
            if (canAccept && inlineAction) acceptAction(),
            _TaskActionMenu(task: task, pending: pending, onSelected: onChange),
          ]);
        }));
  }
}

class _ScopeDialog extends StatefulWidget {
  const _ScopeDialog({required this.scope});
  final AgentAnalysisScope scope;
  @override
  State<_ScopeDialog> createState() => _ScopeDialogState();
}

class _ScopeDialogState extends State<_ScopeDialog> {
  final _form = GlobalKey<FormState>();
  late bool _include = widget.scope.includeOtherSessions;
  late final _days =
      TextEditingController(text: widget.scope.recentDays.toString());
  late final _count =
      TextEditingController(text: widget.scope.maxSessions.toString());
  @override
  void dispose() {
    _days.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(agentText(
            context, '让助手专注于相关会话', 'Focus on relevant conversations')),
        content: SizedBox(
            width: 430,
            child: Form(
                key: _form,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(agentText(
                      context,
                      '所选项目中，通过 Bridge 交流的会话全部纳入，按内容变化增量分析。默认不分析未通过 Bridge 交流的外部会话；开启后，以下时间和数量限制仅用于外部会话。',
                      'All conversations used through Bridge are included within the selected project and analyzed incrementally. External conversations are excluded by default. When enabled, the limits below apply only to external conversations.')),
                  const SizedBox(height: 16),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(agentText(context, '也分析未参与过的会话',
                          'Include conversations not used in this app')),
                      subtitle: Text(agentText(
                          context,
                          '默认关闭，例如未通过 Bridge 交流的导入会话',
                          'Off by default, including imported history not used through Bridge')),
                      value: _include,
                      onChanged: (v) => setState(() => _include = v)),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: agentText(
                              context, '外部会话：最近多少天', 'External: recent days'),
                          helperText: '1–365',
                          border: const OutlineInputBorder()),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 365
                            ? agentText(context, '请输入 1–365 的整数',
                                'Enter a whole number from 1 to 365')
                            : null;
                      }),
                  const SizedBox(height: 18),
                  TextFormField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: agentText(context, '外部会话：最多多少个',
                              'External: maximum conversations'),
                          helperText: '1–100',
                          border: const OutlineInputBorder()),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 100
                            ? agentText(context, '请输入 1–100 的整数',
                                'Enter a whole number from 1 to 100')
                            : null;
                      }),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(agentText(context, '取消', 'Cancel'))),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(
                      context,
                      AgentAnalysisScope(
                          includeOtherSessions: _include,
                          recentDays: int.parse(_days.text),
                          maxSessions: int.parse(_count.text)));
                }
              },
              child: Text(agentText(context, '保存并更新', 'Save and refresh')))
        ],
      );
}

class _WorkspaceAgentAvatar extends StatelessWidget {
  const _WorkspaceAgentAvatar({this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.auto_awesome_outlined,
        size: size,
        color: AppColors.mutedSoftFor(Theme.of(context).brightness));
  }
}

class WorkspaceAgentChat extends StatefulWidget {
  const WorkspaceAgentChat(
      {super.key,
      required this.client,
      this.projectId,
      this.projects = const [],
      this.initialMessage,
      this.composerController,
      this.autoSend = false,
      this.inline = false,
      this.fullPage = false,
      this.progress});
  final String? initialMessage;
  final WorkspaceAgentComposerController? composerController;
  final bool autoSend;
  final bool inline;
  final bool fullPage;
  final Widget? progress;
  final BridgeClient client;
  final String? projectId;
  final List<ProjectSummary> projects;
  @override
  State<WorkspaceAgentChat> createState() => _WorkspaceAgentChatState();
}

class _WorkspaceAgentChatState extends State<WorkspaceAgentChat> {
  bool _autoAnalysisEnabled =
      appSettingsController.settings.autoTaskAnalysisEnabled;
  late final _composer = widget.composerController ??
      WorkspaceAgentComposerController(widget.client);
  TextEditingController get _input => _composer.text;
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic> _snapshot = {};
  final _contextRevision = ValueNotifier<int>(0);
  final _projectTaskPending = <(String, String)>{};
  late String? _projectId = widget.projectId;
  bool _busy = true;
  bool _awayFromLatest = false;
  late int _connectionRevision;
  late String _conversationId;
  String? _pending;
  List<DomainAttachment> _pendingAttachments = [];
  int _requestGeneration = 0;
  Object? _error;
  Timer? _chatPoll;
  int _chatReadVersion = 0;
  int? _chatPollRequest;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onConversationScroll);
    _connectionRevision = widget.client.connectionRevision;
    _conversationId = widget.client.workspaceConversationId;
    widget.client.sessionCacheRevision.addListener(_connectionChanged);
    widget.client.workspaceConversationRevision.addListener(_connectionChanged);
    appSettingsController.addListener(_analysisSettingChanged);
    if (widget.initialMessage != null) _input.text = widget.initialMessage!;
    unawaited(_initialize());
    _chatPoll = Timer.periodic(
        const Duration(seconds: 2), (_) => unawaited(_refreshConversation()));
  }

  Future<void> _initialize() async {
    final revision = _connectionRevision;
    final generation = _requestGeneration;
    await Future.wait([_load(), _composer.ready]);
    if (mounted &&
        revision == _connectionRevision &&
        generation == _requestGeneration &&
        _error == null &&
        (widget.autoSend || widget.initialMessage?.trim().isNotEmpty == true)) {
      await _send();
    }
  }

  void _analysisSettingChanged() {
    final enabled = appSettingsController.settings.autoTaskAnalysisEnabled;
    if (mounted && enabled != _autoAnalysisEnabled) {
      setState(() => _autoAnalysisEnabled = enabled);
      _contextRevision.value++;
    }
  }

  void _connectionChanged() {
    if (!mounted ||
        (_connectionRevision == widget.client.connectionRevision &&
            _conversationId == widget.client.workspaceConversationId)) {
      return;
    }
    _connectionRevision = widget.client.connectionRevision;
    _conversationId = widget.client.workspaceConversationId;
    _requestGeneration++;
    _chatReadVersion++;
    _chatPollRequest = null;
    setState(() {
      _messages = [];
      _replaceSnapshot({});
      _projectTaskPending.clear();
      _pending = null;
      _pendingAttachments = [];
      _busy = true;
      _error = null;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _chatPoll?.cancel();
    appSettingsController.removeListener(_analysisSettingChanged);
    widget.client.sessionCacheRevision.removeListener(_connectionChanged);
    widget.client.workspaceConversationRevision
        .removeListener(_connectionChanged);
    if (widget.composerController == null) _composer.dispose();
    _scroll.dispose();
    _contextRevision.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = _requestGeneration;
    try {
      final data =
          await widget.client.workspaceAgentRequest(projectId: _projectId);
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _replaceSnapshot(data as Map<String, dynamic>);
          _messages = WorkspaceAgentSnapshot.fromJson(_snapshot).chat;
        });
      }
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _busy = false);
      }
    }
    _scrollToEnd();
  }

  Future<void> _refreshConversation() async {
    if (_busy || _chatPollRequest != null) return;
    final generation = _requestGeneration;
    final readVersion = ++_chatReadVersion;
    _chatPollRequest = readVersion;
    try {
      final data =
          await widget.client.workspaceAgentRequest(projectId: _projectId);
      if (!mounted ||
          generation != _requestGeneration ||
          readVersion != _chatReadVersion ||
          _busy) {
        return;
      }
      final messages =
          WorkspaceAgentSnapshot.fromJson(data as Map<String, dynamic>).chat;
      if (jsonEncode(data) == jsonEncode(_snapshot)) return;
      final followTail = !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.offset < 80;
      setState(() {
        _messages = messages;
        _replaceSnapshot(data);
      });
      if (followTail) _scrollToEnd();
    } catch (_) {
      // Preserve the conversation and draft; the next poll retries the read.
    } finally {
      if (_chatPollRequest == readVersion) _chatPollRequest = null;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _onConversationScroll() {
    if (!widget.inline) return;
    final away = _scroll.hasClients && _scroll.position.extentAfter > 80;
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || !_composer.hasContent || _composer.savingModel) return;
    final references =
        _composer.references.map((item) => item.toJson()).toList();
    final generation = _requestGeneration;
    _chatReadVersion++;
    setState(() {
      _busy = true;
      _pending = text;
      _error = null;
    });
    _scrollToEnd();
    try {
      await _composer.ready;
      if (_composer.modelError != null) await _composer.refreshModels();
      if (_composer.modelError case final error?) throw error;
      final configuration = {
        'selection': _composer.selection == null
            ? null
            : Map<String, dynamic>.of(_composer.selection!),
        'agent': _composer.taskAgent,
        'approval_mode': _composer.approvalMode.name,
      };
      final attachments = await _composer.uploadAttachments();
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _pendingAttachments = attachments);
      final payload =
          '$text|${attachments.map((a) => a.id).join(',')}|$_projectId|$_connectionRevision|$_conversationId|${jsonEncode(configuration)}|${jsonEncode(references)}';
      final requestId = _composer.requestIdFor(payload);
      final data = await widget.client.workspaceAgentRequest(
          action: '/chat',
          method: 'POST',
          projectId: _projectId,
          body: {
            'request_id': requestId,
            'message': text,
            'configuration': configuration,
            if (references.isNotEmpty) 'references': references,
            'attachments': attachments.map((a) => a.toJson()).toList()
          });
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _messages = (data as List).cast<Map<String, dynamic>>();
        _composer.clear();
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _busy = false;
          _pending = null;
          _pendingAttachments = [];
        });
      }
    }
    _scrollToEnd();
  }

  Future<void> _apply(Map<String, dynamic> message) async {
    _chatReadVersion++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.workspaceAgentRequest(
          action: '/chat/${Uri.encodeComponent(message['id'] as String)}/apply',
          method: 'POST',
          projectId: _projectId);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
    }
  }

  Future<void> _undoTaskAction(String id) async {
    _chatReadVersion++;
    final generation = _requestGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.workspaceAgentRequest(
          action: '/tasks/actions/${Uri.encodeComponent(id)}/undo',
          method: 'POST');
      if (mounted && generation == _requestGeneration) await _load();
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
    }
  }

  void _replaceSnapshot(Map<String, dynamic> snapshot) {
    _snapshot = snapshot;
    _contextRevision.value++;
  }

  WorkspaceProjectContext? get _projectContext {
    final raw = _snapshot['project_context'];
    if (raw is Map && raw['project'] is Map) {
      final data =
          WorkspaceProjectContext.fromJson(Map<String, dynamic>.from(raw));
      if (_projectId == null || data.project.id == _projectId) return data;
    }
    final project = widget.projects
            .where((project) => project.id == _projectId)
            .firstOrNull ??
        (_projectId == null ? null : widget.client.peekProject(_projectId!));
    return project == null
        ? null
        : WorkspaceProjectContext(project: project, branch: project.gitBranch);
  }

  Future<void> _openProjectSession(String projectId, String sessionId) async {
    try {
      final detail = await widget.client.getSession(sessionId);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
          AppRoutes.session(projectId, sessionId),
          arguments: detail.session);
      if (mounted) await _refreshConversation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    }
  }

  Future<void> _changeProjectTaskStatus(
      WorkspaceTask task, String status) async {
    final key = (task.sessionId, task.id);
    if (_projectTaskPending.contains(key)) return;
    final generation = _requestGeneration;
    setState(() => _projectTaskPending.add(key));
    _contextRevision.value++;
    try {
      final result = await widget.client.workspaceAgentRequest(
        action: '/tasks/actions',
        method: 'POST',
        body: {
          'request_id': const Uuid().v4(),
          'expected_status': task.status,
          'status': status,
          'tasks': [
            {'session_id': task.sessionId, 'task_id': task.id}
          ],
        },
      ) as Map<String, dynamic>;
      if (!mounted || generation != _requestGeneration) return;
      await _refreshConversation();
      if (!mounted || generation != _requestGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
        content: Text(agentText(context, '任务状态已更新', 'Task status updated')),
        action: SnackBarAction(
            label: agentText(context, '撤销', 'Undo'),
            onPressed: () {
              if (mounted && generation == _requestGeneration) {
                unawaited(_undoTaskAction(result['action_id'] as String));
              }
            }),
      ));
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _projectTaskPending.remove(key));
        _contextRevision.value++;
      }
    }
  }

  Widget _buildProjectContextPanel(WorkspaceProjectContext data) =>
      WorkspaceProjectContextPanel(
        key: ValueKey(('workspace-project-context-panel', data.project.id)),
        data: data,
        snapshot: _snapshot,
        client: widget.client,
        showTasks: _autoAnalysisEnabled,
        onRefresh: _refreshConversation,
        onOpenSession: (projectId, sessionId) =>
            unawaited(_openProjectSession(projectId, sessionId)),
        taskBuilder: (task) => _RelatedTaskRow(
          key: ValueKey(('workspace-project-task', task.sessionId, task.id)),
          task: task,
          pending: _projectTaskPending.contains((task.sessionId, task.id)),
          onOpen: () =>
              unawaited(_openProjectSession(task.projectId, task.sessionId)),
          onChange: (status) =>
              unawaited(_changeProjectTaskStatus(task, status)),
        ),
      );

  Future<void> _showProjectContext() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 600),
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: ValueListenableBuilder<int>(
              valueListenable: _contextRevision,
              builder: (context, _, child) {
                final data = _projectContext;
                return data == null
                    ? Center(
                        child: Text(agentText(
                            context, '请先选择一个项目', 'Select a project first')))
                    : _buildProjectContextPanel(data);
              }),
        ),
      );

  Widget _buildProjectContextSummary(WorkspaceProjectContext data) {
    final theme = Theme.of(context);
    final git = data.gitStatus;
    final tasks = (_snapshot['tasks'] as List? ?? [])
        .whereType<Map>()
        .where((task) =>
            task['project_id'] == data.project.id && task['archived'] != true)
        .toList();
    bool isOpen(Object? status) => !['completed', 'cancelled'].contains(status);
    final open = tasks
        .where((task) => isOpen((task['task'] as Map?)?['status']))
        .toList();
    final represented = open.map((task) => task['session_id']).toSet();
    final count = open.length;
    final pending = (_snapshot['dispatch_tasks'] as List? ?? [])
        .whereType<Map>()
        .where((task) =>
            task['project_id'] == data.project.id &&
            !represented.contains(task['session_id']) &&
            isOpen(task['status']))
        .length;
    return InkWell(
      key: const Key('workspace-project-context-summary'),
      onTap: _showProjectContext,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          ProjectAvatar(
              name: data.project.name,
              iconDataUri: data.project.iconDataUri,
              size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  [
                    data.project.name,
                    if (data.branch?.isNotEmpty == true) data.branch!
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall)),
          if (git != null) ...[
            const SizedBox(width: 8),
            Icon(git.dirty ? Icons.edit_outlined : Icons.check_circle_outline,
                size: 16,
                color: git.dirty
                    ? AppColors.warningTextFor(theme.brightness)
                    : AppColors.successTextFor(theme.brightness)),
          ],
          const SizedBox(width: 8),
          Text(
              _autoAnalysisEnabled
                  ? agentText(context, '任务 ${count + pending}',
                      'Tasks ${count + pending}')
                  : agentText(context, '会话 ${data.sessions.length}',
                      'Conversations ${data.sessions.length}'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final brightness = theme.brightness;
    final muted = AppColors.mutedSoftFor(brightness);
    final accent = AppColors.accentBlueFor(brightness);
    final line = AppColors.outlineFor(brightness).withValues(alpha: .6);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final horizontal = compact ? 16.0 : 28.0;
    final selectedProject =
        widget.projects.where((p) => p.id == _projectId).firstOrNull;
    final projectContext = _projectContext;
    final wideContext = widget.fullPage &&
        MediaQuery.sizeOf(context).width >= 1120 &&
        projectContext != null;
    final allProjectsLabel = _autoAnalysisEnabled
        ? agentText(context, '全部项目 · 全局任务', 'All projects · Global tasks')
        : agentText(context, '全部项目', 'All projects');
    if (widget.inline) return _buildInline(context);
    final conversation = LayoutBuilder(builder: (context, constraints) {
      final availableHeight = widget.fullPage
          ? constraints.maxHeight
          : constraints.maxHeight.clamp(0.0, 760.0);
      return SizedBox(
          key: widget.fullPage
              ? const Key('main-agent-conversation-page')
              : null,
          width: widget.fullPage ? double.infinity : 800,
          height: widget.fullPage ? availableHeight : 760,
          child: Column(children: [
            Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 12, 12, 4),
                child: Row(children: [
                  if (widget.fullPage)
                    IconButton(
                        key: const Key('main-agent-conversation-back'),
                        tooltip: agentText(context, '返回', 'Back'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded)),
                  const _WorkspaceAgentAvatar(size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          agentText(context, '工作区助手', 'Workspace agent'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600))),
                  WorkspaceConversationActions(
                      client: widget.client,
                      enabled: !_busy,
                      projectId: _projectId,
                      projects: widget.projects),
                  if (projectContext != null && !wideContext)
                    IconButton(
                        key: const Key('workspace-project-context-button'),
                        tooltip: agentText(context, '项目概览', 'Project overview'),
                        onPressed: _showProjectContext,
                        icon: const Icon(Icons.info_outline_rounded, size: 20)),
                  if (!widget.fullPage)
                    IconButton(
                        tooltip: agentText(context, '关闭', 'Close'),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                            foregroundColor: muted,
                            backgroundColor: Colors.transparent,
                            side: BorderSide.none),
                        icon: const Icon(Icons.close_rounded, size: 20)),
                ])),
            if (widget.projects.isNotEmpty)
              Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<String>(
                        tooltip: agentText(context, '当前项目', 'Current project'),
                        initialValue: _projectId ?? '',
                        enabled: !_busy,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: '', child: Text(allProjectsLabel)),
                          ...widget.projects.map((p) => PopupMenuItem(
                              value: p.id,
                              child: Text(p.name,
                                  overflow: TextOverflow.ellipsis)))
                        ],
                        onSelected: (value) {
                          setState(() {
                            _requestGeneration++;
                            _projectId = value == '' ? null : value;
                            _busy = true;
                            _messages = [];
                            _replaceSnapshot({});
                            _projectTaskPending.clear();
                            _error = null;
                          });
                          unawaited(_load());
                        },
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.folder_outlined,
                                  size: 16, color: muted),
                              const SizedBox(width: 8),
                              Flexible(
                                  child: Text(
                                      selectedProject?.name ?? allProjectsLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: muted))),
                              const SizedBox(width: 8),
                              Icon(Icons.expand_more_rounded,
                                  size: 16, color: muted),
                            ])),
                      ))),
            Divider(height: 1, color: line),
            if (projectContext != null &&
                !wideContext &&
                availableHeight >= 560)
              _buildProjectContextSummary(projectContext),
            Expanded(
                child: _messages.isEmpty && _pending == null && !_busy
                    ? Center(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _WorkspaceAgentAvatar(size: 32),
                                  const SizedBox(height: 20),
                                  Text(
                                      agentText(context, '从一个问题开始',
                                          'Start with a question'),
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text(
                                      _autoAnalysisEnabled
                                          ? agentText(
                                              context,
                                              '理清待办、安排工作，或聊聊下一步。',
                                              'Review your tasks, plan some work, or find your next step.')
                                          : agentText(
                                              context,
                                              '聊聊想法，或继续已有会话中的工作。',
                                              'Share an idea, or continue work in a conversation.'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: muted, height: 1.5)),
                                  const SizedBox(height: 20),
                                  Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        for (final prompt in [
                                          if (_autoAnalysisEnabled)
                                            agentText(context, '哪些任务还没完成？',
                                                'Which tasks are still unfinished?')
                                          else
                                            agentText(context, '我们下一步做什么？',
                                                'What should we do next?'),
                                          agentText(context, '当前项目有哪些设置？',
                                              'What are the current project settings?'),
                                          if (_autoAnalysisEnabled)
                                            agentText(context, '把分析范围改为最近 7 天',
                                                'Change the analysis range to the last 7 days')
                                        ])
                                          TextButton(
                                              style: TextButton.styleFrom(
                                                  foregroundColor: muted,
                                                  textStyle: theme
                                                      .textTheme.bodySmall),
                                              onPressed: () {
                                                _input.text = prompt;
                                                unawaited(_send());
                                              },
                                              child: Text(prompt)),
                                      ]),
                                ])))
                    : ListView(
                        key: const Key('agent-chat-messages'),
                        controller: _scroll,
                        padding:
                            EdgeInsets.fromLTRB(horizontal, 24, horizontal, 8),
                        children: [
                            for (var i = 0; i < _messages.length; i++)
                              _bubble(_messages[i],
                                  previous: i > 0 ? _messages[i - 1] : null),
                            if (_pending != null)
                              _bubble({
                                'role': 'user',
                                'content': _pending,
                                'attachments': _pendingAttachments
                                    .map((a) => a.toJson())
                                    .toList()
                              }),
                            if (_busy)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(children: [
                                    const _WorkspaceAgentAvatar(size: 16),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                            color: accent, strokeWidth: 1.5)),
                                    const SizedBox(width: 8),
                                    Text(
                                        agentText(
                                            context, '正在思考…', 'Thinking…'),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: muted))
                                  ])),
                          ])),
            if (_error != null)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text('$_error',
                      style: TextStyle(color: colors.error),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis)),
            Container(
                margin: EdgeInsets.fromLTRB(
                    compact ? 12 : 20, 12, compact ? 12 : 20, 16),
                child: WorkspaceAgentComposer(
                    controller: _composer,
                    projectId: _projectId,
                    projects: widget.projects,
                    maxLines: availableHeight < 600 ? 2 : 4,
                    enabled: !_busy,
                    onSend: _send)),
          ]));
    });
    if (widget.fullPage) {
      return Scaffold(
          backgroundColor: AppColors.screenFor(brightness),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: wideContext ? 1400 : 1040),
                      child: wideContext
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  Expanded(child: conversation),
                                  VerticalDivider(width: 1, color: line),
                                  SizedBox(
                                      width: 320,
                                      child: _buildProjectContextPanel(
                                          projectContext)),
                                ])
                          : conversation))));
    }
    return Dialog(
        insetPadding: EdgeInsets.all(compact ? 8 : 24),
        backgroundColor: AppColors.screenFor(brightness),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: line)),
        clipBehavior: Clip.antiAlias,
        child: conversation);
  }

  Widget _buildInline(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final accent = AppColors.accentBlueFor(theme.brightness);
    final media = MediaQuery.of(context);
    final compact = media.size.width < 600;
    final height = (media.size.height - media.viewInsets.bottom - 180)
        .clamp(compact ? 380.0 : 460.0, 800.0);
    final horizontal = compact ? 16.0 : 24.0;
    final conversationTitle =
        (_snapshot['conversation'] as Map?)?['title'] as String?;
    return Container(
      key: const Key('home-agent-workspace'),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: AppColors.panelFor(theme.brightness),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outlineFor(theme.brightness))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 16),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    Icon(Icons.auto_awesome_outlined, size: 22, color: accent)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(agentText(context, '助手', 'Assistant'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      conversationTitle?.isNotEmpty == true
                          ? conversationTitle!
                          : agentText(context, '新会话', 'New conversation'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ])),
            WorkspaceConversationActions(
                client: widget.client,
                enabled: !_busy,
                projectId: _projectId,
                projects: widget.projects),
            if (_projectContext != null)
              IconButton(
                  tooltip: agentText(context, '项目概览', 'Project overview'),
                  onPressed: _showProjectContext,
                  icon: const Icon(Icons.info_outline_rounded, size: 20)),
            if (_messages.isNotEmpty)
              IconButton(
                  key: const Key('home-agent-latest'),
                  tooltip: agentText(context, '回到最新消息', 'Latest messages'),
                  onPressed: _scrollToEnd,
                  icon: const Icon(Icons.vertical_align_bottom_rounded,
                      size: 20)),
          ]),
        ),
        Divider(height: 1, color: AppColors.outlineFor(theme.brightness)),
        Expanded(
            child: Stack(children: [
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: const Key('home-agent-messages'),
              controller: _scroll,
              primary: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_messages.isEmpty &&
                        _pending == null &&
                        !_busy &&
                        _error == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  agentText(context, '一起推进下一步',
                                      'What shall we work on?'),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              Text(
                                  agentText(context, '告诉我你的目标，或从最近的工作继续。',
                                      'Share a goal, or pick up your recent work.'),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: muted, height: 1.6)),
                              const SizedBox(height: 20),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final prompt in [
                                  agentText(context, '整理当前进展',
                                      'Review recent progress'),
                                  agentText(context, '下一步先做什么？',
                                      'What should we do next?'),
                                ])
                                  ActionChip(
                                      onPressed: () => _input.text = prompt,
                                      avatar: const Icon(
                                          Icons.arrow_outward_rounded,
                                          size: 15),
                                      label: Text(prompt)),
                              ]),
                            ]),
                      ),
                    for (var i = 0; i < _messages.length; i++)
                      _bubble(_messages[i],
                          previous: i > 0 ? _messages[i - 1] : null),
                    if (_pending != null)
                      _bubble({
                        'role': 'user',
                        'content': _pending,
                        'attachments':
                            _pendingAttachments.map((a) => a.toJson()).toList(),
                      }),
                    if (_busy)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: accent)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                                    agentText(context, '正在处理…', 'Working…'),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted))),
                          ])),
                    if (widget.progress != null) widget.progress!,
                  ]),
            ),
          ),
          if (_awayFromLatest)
            Positioned(
                bottom: 8,
                right: horizontal,
                child: FilledButton.tonalIcon(
                    key: const Key('home-agent-jump-to-latest'),
                    onPressed: _scrollToEnd,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                    label:
                        Text(agentText(context, '最新消息', 'Latest messages')))),
        ])),
        if ((_snapshot['dispatch_tasks'] as List? ?? []).isNotEmpty)
          Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * .38),
                child: SingleChildScrollView(
                    primary: false,
                    child: WorkspaceDispatchPanel(
                        key: Key(_autoAnalysisEnabled
                            ? 'home-main-agent-linked-tasks'
                            : 'home-main-agent-linked-sessions'),
                        client: widget.client,
                        projectId: _projectId,
                        projects: widget.projects,
                        compact: true,
                        recentTaskLimit: 2,
                        showSessionsOnly: !_autoAnalysisEnabled,
                        snapshot: _snapshot,
                        onRefresh: _refreshConversation)),
              )),
        if (_error != null)
          Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
              child: Row(children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('$_error',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error))),
                TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_composer.hasContent) {
                              unawaited(_send());
                            } else {
                              setState(() {
                                _busy = true;
                                _error = null;
                              });
                              unawaited(_load());
                            }
                          },
                    child: Text(agentText(context, '重试', 'Retry'))),
              ])),
        Padding(
          key: const Key('home-agent-composer-surface'),
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * .42),
            child: SingleChildScrollView(
                primary: false,
                child: WorkspaceAgentComposer(
                    controller: _composer,
                    projectId: _projectId,
                    projects: widget.projects,
                    home: true,
                    maxLines: 3,
                    enabled: !_busy,
                    onSend: _send)),
          ),
        ),
      ]),
    );
  }

  Future<void> _openMarkdownLink(String? href, {File? sourceFile}) async {
    if (href == null || href.trim().isEmpty) return;
    try {
      var uri = Uri.parse(href);
      if (sourceFile != null) uri = sourceFile.absolute.uri.resolveUri(uri);
      if (!uri.hasScheme || uri.scheme == 'file') {
        ProjectSummary? project = widget.projects
                .where((project) => project.id == _projectId)
                .firstOrNull ??
            (_projectId == null
                ? null
                : widget.client.peekProject(_projectId!)) ??
            _projectContext?.project;
        if (!uri.hasScheme && !uri.path.startsWith('/')) {
          if (project == null) {
            throw StateError(agentText(context, '请先选择项目，再打开相对文件链接。',
                'Select a project to open relative file links.'));
          }
          uri = Directory(project.rootPath).absolute.uri.resolveUri(uri);
        }
        final file = uri.scheme == 'file'
            ? File.fromUri(Uri(scheme: 'file', host: uri.host, path: uri.path))
            : File(uri.path);
        if (project == null) {
          final projects = widget.projects.isNotEmpty
              ? widget.projects
              : widget.client.peekProjects() ?? const <ProjectSummary>[];
          final matches = projects
              .where((project) => file.absolute.path.startsWith(
                  '${Directory(project.rootPath).absolute.path}${Platform.pathSeparator}'))
              .toList()
            ..sort((a, b) => b.rootPath.length.compareTo(a.rootPath.length));
          project = matches.firstOrNull;
        }
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (_) => SessionFilePreview(
                access: SessionFileAccess(
                    file: file,
                    client: widget.client,
                    projectId: project?.id,
                    rootPath: project?.rootPath),
                onOpenLink: (href) =>
                    unawaited(_openMarkdownLink(href, sourceFile: file)),
                sourceBuilder: (context, content) => SelectableText.rich(
                    MessageCodeSyntaxHighlighter(Theme.of(context))
                        .format(content),
                    key: const ValueKey('markdown-file-preview-content'))));
      } else {
        final error = agentText(context, '无法打开链接', 'Could not open the link');
        if (!await launchUrl(uri)) throw StateError(error);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    }
  }

  Widget _bubble(Map<String, dynamic> message,
      {Map<String, dynamic>? previous}) {
    final theme = Theme.of(context);
    final accent = AppColors.accentBlueFor(theme.brightness);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final user = message['role'] == 'user';
    final requestId = message['dispatch_request_id'] as String?;
    final returned =
        (message['id'] as String? ?? '').startsWith('dispatch-return-');
    final continuation = !user &&
        previous?['role'] == 'assistant' &&
        requestId != null &&
        previous?['dispatch_request_id'] == requestId;
    final origin = returned && !continuation
        ? _messages
            .where((entry) =>
                entry['role'] == 'user' &&
                entry['dispatch_request_id'] == requestId)
            .firstOrNull
        : null;
    final progressAnchor = !user &&
        requestId != null &&
        identical(
            _messages
                .where((entry) =>
                    entry['role'] == 'assistant' &&
                    entry['dispatch_request_id'] == requestId)
                .firstOrNull,
            message);
    final proposal = message['proposal'] as Map<String, dynamic>?;
    final taskAction = message['task_action'] as Map<String, dynamic>?;
    final attachments = (message['attachments'] as List? ?? [])
        .map((a) =>
            DomainAttachment.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList();
    return Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: user ? 560 : 700),
          margin: const EdgeInsets.only(bottom: 24),
          padding: user
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
              color: user
                  ? Color.alphaBlend(accent.withValues(alpha: .08),
                      AppColors.panelDeepFor(theme.brightness))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!user && !continuation) ...[
              Row(mainAxisSize: MainAxisSize.min, children: [
                const _WorkspaceAgentAvatar(size: 14),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(agentText(context, '工作区助手', 'Workspace agent'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: muted))),
              ]),
              const SizedBox(height: 8),
            ],
            if (origin != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    agentText(context, '关于：', 'Re: ') +
                        (origin['content'] as String? ?? ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            if ((message['content'] as String? ?? '').isNotEmpty)
              MessageMarkdown(
                  key: ValueKey(
                      'assistant-message-markdown-${message['id'] ?? 'pending'}'),
                  data: message['content'] as String? ?? '',
                  theme: theme,
                  textColor: theme.colorScheme.onSurface,
                  adaptiveTables: true,
                  onTapLink: (href) => unawaited(_openMarkdownLink(href))),
            if (progressAnchor)
              WorkspaceDispatchPanel(
                key: ValueKey('conversation-progress-$requestId'),
                client: widget.client,
                projectId: _projectId,
                projects: widget.projects,
                compact: true,
                showSessionsOnly: !_autoAnalysisEnabled,
                requestId: requestId,
                snapshot: _snapshot,
                onRefresh: _refreshConversation,
              ),
            for (final attachment in attachments)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        attachment.kind == 'image'
                            ? Icons.image_outlined
                            : Icons.attach_file,
                        size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(attachment.fileName,
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ])),
            if (taskAction?['id'] case final String id) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: accent),
                  onPressed: _busy || taskAction?['undone'] == true
                      ? null
                      : () => _undoTaskAction(id),
                  icon: Icon(
                      taskAction?['undone'] == true ? Icons.check : Icons.undo,
                      size: 17),
                  label: Text(taskAction?['undone'] == true
                      ? agentText(context, '任务修改已撤销', 'Task change undone')
                      : agentText(context, '撤销任务修改', 'Undo task change'))),
            ],
            if (proposal != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              Text(agentText(context, '设置修改预览', 'Settings change preview'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (proposal['analysis_scope']
                  case final Map<String, dynamic> scope) ...[
                Text(agentText(context, '最近天数：', 'Recent days: ') +
                    scope['recent_days'].toString()),
                Text(agentText(context, '最多会话：', 'Maximum conversations: ') +
                    scope['max_sessions'].toString()),
                Text(agentText(
                        context, '包含未参与会话：', 'Include other conversations: ') +
                    (scope['include_other_sessions'] == true
                        ? agentText(context, '是', 'Yes')
                        : agentText(context, '否', 'No'))),
              ],
              if (proposal['project_approval_prompt'] != null)
                SelectableText(agentText(
                        context, '项目审批说明：', 'Project approval instructions: ') +
                    proposal['project_approval_prompt'].toString()),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: .10),
                      foregroundColor: accent),
                  onPressed: _busy || message['applied'] == true
                      ? null
                      : () => _apply(message),
                  icon: Icon(
                      message['applied'] == true ? Icons.check : Icons.tune,
                      size: 17),
                  label: Text(message['applied'] == true
                      ? agentText(context, '已应用', 'Applied')
                      : agentText(context, '应用修改', 'Apply change'))),
            ],
          ]),
        ));
  }
}
