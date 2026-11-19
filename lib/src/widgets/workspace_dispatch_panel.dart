import 'dart:async';
import 'package:flutter/material.dart';
import '../app_routes.dart';
import '../bridge_client.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import 'app_snack_bar.dart';
import 'composer_settings_dropdown.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// Execution has its own polling and controls, so chat remains available.
class WorkspaceDispatchPanel extends StatefulWidget {
  const WorkspaceDispatchPanel(
      {super.key,
      required this.client,
      this.projectId,
      this.projects = const [],
      this.compact = false,
      this.snapshot,
      this.requestId,
      this.onRefresh,
      this.recentTaskLimit,
      this.dense = false,
      this.showSessionsOnly = false,
      this.onConversationOpened,
      this.showReturnedAnswers = false});
  final BridgeClient client;
  final String? projectId;
  final List<ProjectSummary> projects;
  final bool compact;

  /// In conversations the parent owns polling for all turns.
  final Map<String, dynamic>? snapshot;
  final String? requestId;
  final Future<void> Function()? onRefresh;
  final bool showReturnedAnswers;

  /// Always-visible execution tasks inside the main conversation.
  final int? recentTaskLimit;
  final bool dense;
  final bool showSessionsOnly;
  final VoidCallback? onConversationOpened;
  @override
  State<WorkspaceDispatchPanel> createState() => _WorkspaceDispatchPanelState();
}

class _WorkspaceDispatchPanelState extends State<WorkspaceDispatchPanel> {
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _answers = [];
  bool _returnPending = false;
  bool _returnGenerating = false;
  final Set<String> _expandedReplies = {};
  final Set<String> _pending = {};
  Timer? _timer;
  int _generation = 0;
  int _readVersion = 0;
  late int _connectionRevision;
  bool _expanded = false;
  bool _detailsExpanded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _connectionRevision = widget.client.connectionRevision;
    widget.client.sessionCacheRevision.addListener(_connectionChanged);
    unawaited(_load());
  }

  void _connectionChanged() {
    if (_connectionRevision == widget.client.connectionRevision) return;
    _connectionRevision = widget.client.connectionRevision;
    _reset();
  }

  void _reset() {
    _generation++;
    _timer?.cancel();
    setState(() {
      _tasks = [];
      _answers = [];
      _returnPending = false;
      _returnGenerating = false;
      _expandedReplies.clear();
      _pending.clear();
      _error = null;
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkspaceDispatchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot case final data?) _readSnapshot(data);
    if (oldWidget.client != widget.client) {
      oldWidget.client.sessionCacheRevision.removeListener(_connectionChanged);
      widget.client.sessionCacheRevision.addListener(_connectionChanged);
      _connectionRevision = widget.client.connectionRevision;
    }
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.client != widget.client) {
      _reset();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.sessionCacheRevision.removeListener(_connectionChanged);
    super.dispose();
  }

  void _readSnapshot(Map<String, dynamic> data) {
    setState(() {
      _tasks = (data['dispatch_tasks'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((task) =>
              widget.requestId == null ||
              task['request_id'] == widget.requestId)
          .toList()
          .reversed
          .toList();
      _tasks.sort((a, b) {
        if (widget.recentTaskLimit != null) {
          DateTime? created(Map<String, dynamic> task) =>
              DateTime.tryParse(task['created_at'] as String? ??
                  task['updated_at'] as String? ??
                  '');
          final left = created(a);
          final right = created(b);
          return left == null
              ? (right == null ? 0 : 1)
              : right == null
                  ? -1
                  : right.compareTo(left);
        }
        int priority(Map<String, dynamic> task) => switch (task['status']) {
              'running' || 'awaiting_approval' => 0,
              'queued' || 'paused' || 'blocked' => 1,
              _ => 2,
            };
        final order = priority(a).compareTo(priority(b));
        return order != 0
            ? order
            : (b['updated_at'] as String? ?? '')
                .compareTo(a['updated_at'] as String? ?? '');
      });
      final messages =
          (data['chat'] as List? ?? []).cast<Map<String, dynamic>>();
      final seenRequests = <String>{};
      _answers = messages.reversed
          .where((message) =>
              (message['id'] as String? ?? '').startsWith('dispatch-return-'))
          .where((message) => seenRequests.add(
              message['dispatch_request_id'] as String? ??
                  message['id'] as String))
          .take(3)
          .map((message) => <String, dynamic>{
                ...message,
                '_original_request': messages
                    .where((entry) =>
                        entry['role'] == 'user' &&
                        entry['dispatch_request_id'] ==
                            message['dispatch_request_id'])
                    .firstOrNull?['content']
              })
          .toList();
      final reports = (data['dispatch_reports'] as List? ?? []).where(
          (report) =>
              widget.requestId == null ||
              report['request_id'] == widget.requestId);
      _returnPending = reports.any(
          (report) => report['pending'] == true && report['error'] != null);
      _returnGenerating = reports.any(
          (report) => report['pending'] == true && report['error'] == null);
      _error = null;
    });
  }

  Future<void> _load() async {
    if (widget.snapshot case final data?) {
      _readSnapshot(data);
      return;
    }
    final generation = _generation;
    final readVersion = ++_readVersion;
    try {
      final data =
          await widget.client.workspaceAgentRequest(projectId: widget.projectId)
              as Map<String, dynamic>;
      if (!mounted ||
          generation != _generation ||
          readVersion != _readVersion) {
        return;
      }
      _readSnapshot(data);
    } catch (error) {
      if (mounted && generation == _generation && readVersion == _readVersion) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation && readVersion == _readVersion) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), _load);
      }
    }
  }

  Future<void> _control(Map<String, dynamic> task, String action) async {
    final id = task['id'] as String;
    if (_pending.contains(id)) return;
    final generation = _generation;
    setState(() => _pending.add(id));
    try {
      await widget.client.workspaceAgentRequest(
          action: '/dispatch/${Uri.encodeComponent(id)}/control',
          method: 'POST',
          body: {'action': action});
      if (mounted && generation == _generation) {
        if (widget.snapshot != null) {
          await widget.onRefresh?.call();
        } else {
          await _load();
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _pending.remove(id));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> task) async {
    final generation = _generation;
    try {
      final detail =
          await widget.client.getSession(task['session_id'] as String);
      if (!mounted || generation != _generation) return;
      await Navigator.of(context).pushNamed(
          AppRoutes.session(
              task['project_id'] as String, task['session_id'] as String),
          arguments: detail.session);
    } catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    }
  }

  String _status(String status) => switch (status) {
        'queued' => _text(context, '排队中', 'Queued'),
        'running' => _text(context, '执行中', 'Running'),
        'awaiting_approval' => _text(context, '等待审批', 'Awaiting approval'),
        'paused' => _text(context, '已暂停', 'Paused'),
        'cancelled' => _text(context, '已取消', 'Cancelled'),
        'awaiting_review' => _text(context, '待验收', 'Ready for review'),
        'completed' => _text(context, '已完成', 'Completed'),
        'blocked' => _text(context, '待解决', 'Blocked'),
        _ => status,
      };

  String _progressLabel() {
    final finished = _tasks.every((task) =>
        ['awaiting_review', 'completed', 'cancelled'].contains(task['status']));
    if (finished) return _text(context, '查看处理过程', 'View work details');
    final attention = _tasks.any((task) =>
        ['blocked', 'paused', 'awaiting_approval'].contains(task['status']));
    return attention
        ? _text(context, '有任务需要处理', 'Needs attention')
        : _text(context, '正在处理', 'Working');
  }

  Widget _notice(String text, {bool warning = false}) {
    final theme = Theme.of(context);
    final color = warning
        ? AppColors.warningTextFor(theme.brightness)
        : AppColors.mutedSoftFor(theme.brightness);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              warning
                  ? Icons.info_outline_rounded
                  : Icons.auto_awesome_outlined,
              size: 16,
              color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: color, height: 1.5))),
        ]));
  }

  Widget _buildLinkedSessions(int limit) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final seen = <String>{};
    final sessions = _tasks
        .where((task) {
          final id = task['session_id'] as String?;
          return id != null && id.isNotEmpty && seen.add(id);
        })
        .take(limit)
        .toList();
    if (sessions.isEmpty) return const SizedBox.shrink();
    Widget entry(Map<String, dynamic> task) {
      final id = task['session_id'] as String;
      final session = widget.client.peekSessionById(id);
      final project = widget.projects
          .where((project) => project.id == task['project_id'])
          .firstOrNull;
      return InkWell(
          key: ValueKey(('assistant-linked-session', id)),
          onTap: () => _open(task),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 19, color: muted),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          session?.title ??
                              task['title'] as String? ??
                              _text(context, '会话', 'Conversation'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          [
                            if (project != null) project.name,
                            widget.client.agentLabelFor(session?.agentId ??
                                task['agent'] as String? ??
                                'pi'),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted)),
                    ])),
                const SizedBox(width: 8),
                Icon(Icons.arrow_outward_rounded, size: 16, color: muted),
              ])));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: EdgeInsets.only(top: widget.dense ? 18 : 8, bottom: 4),
          child: Text(_text(context, '关联会话', 'Linked conversations'),
              style: theme.textTheme.labelSmall?.copyWith(color: muted))),
      LayoutBuilder(builder: (context, constraints) {
        if (sessions.length == 2 && constraints.maxWidth >= 600) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: entry(sessions[0])),
            const SizedBox(width: 24),
            Expanded(child: entry(sessions[1])),
          ]);
        }
        return Column(children: [for (final task in sessions) entry(task)]);
      }),
    ]);
  }

  Widget _buildRecentTasks(int limit) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final accent = AppColors.accentBlueFor(theme.brightness);
    final tasks = _tasks.take(limit).toList();
    Widget card(Map<String, dynamic> task) {
      final id = task['id'] as String;
      final status = task['status'] as String;
      final pending = _pending.contains(id);
      final stage = switch (status) {
        'queued' => 0,
        'running' || 'awaiting_approval' || 'paused' || 'blocked' => 1,
        'awaiting_review' || 'completed' => 2,
        _ => -1,
      };
      final color = switch (status) {
        'paused' ||
        'blocked' ||
        'awaiting_approval' =>
          AppColors.warningTextFor(theme.brightness),
        'completed' ||
        'awaiting_review' =>
          AppColors.successTextFor(theme.brightness),
        'cancelled' => muted,
        _ => accent,
      };
      final summary = (task['summary'] as String? ?? '').trim();
      final progress = summary.isNotEmpty
          ? summary
          : switch (status) {
              'queued' => (task['dependencies'] as List? ?? []).isNotEmpty
                  ? _text(context, '等待前置任务完成', 'Waiting for prerequisites')
                  : _text(context, '等待开始执行', 'Waiting to start'),
              'running' => _text(context, '正在执行，等待新的进度回报',
                  'Working; waiting for a progress update'),
              'awaiting_approval' =>
                _text(context, '等待批准后继续执行', 'Waiting for approval to continue'),
              'paused' => _text(context, '任务已暂停，可从菜单继续',
                  'Paused. Resume from the task menu.'),
              'blocked' => _text(context, '任务受阻，请查看执行会话',
                  'Blocked. Check the execution conversation.'),
              'awaiting_review' => _text(
                  context, '结果已返回，等待验收', 'Results returned; ready for review'),
              'completed' => _text(context, '任务已完成', 'Task completed'),
              'cancelled' => _text(context, '执行已取消', 'Execution cancelled'),
              _ => _status(status),
            };
      return Container(
        key: ValueKey(('main-agent-task', id)),
        padding: widget.dense
            ? const EdgeInsets.symmetric(vertical: 10)
            : const EdgeInsets.fromLTRB(12, 6, 8, 12),
        decoration: widget.dense
            ? BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.outlineFor(theme.brightness)
                            .withValues(alpha: .5))))
            : BoxDecoration(
                color: AppColors.screenFor(theme.brightness),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.outlineFor(theme.brightness))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (widget.dense) ...[
              Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(
                      switch (status) {
                        'running' => Icons.sync_rounded,
                        'queued' => Icons.schedule_rounded,
                        'paused' => Icons.pause_rounded,
                        'awaiting_approval' => Icons.shield_outlined,
                        'awaiting_review' || 'completed' => Icons.check_rounded,
                        'blocked' => Icons.priority_high_rounded,
                        'cancelled' => Icons.close_rounded,
                        _ => Icons.task_alt_rounded,
                      },
                      size: 16,
                      color: color)),
              const SizedBox(width: 10),
            ],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(task['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: widget.dense ? 12 : null,
                          color: widget.dense
                              ? AppColors.textSoftFor(theme.brightness)
                              : null,
                          fontWeight: FontWeight.w600)),
                  if (widget.dense) ...[
                    const SizedBox(height: 4),
                    Tooltip(
                        message: progress,
                        child: Text.rich(
                            TextSpan(
                                text: '${_status(status)} · ',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontSize: 11, color: color),
                                children: [
                                  TextSpan(
                                      text: progress,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              fontSize: 11, color: muted))
                                ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ],
                ])),
            PopupMenuButton<String>(
                key: ValueKey(('main-agent-task-actions', id)),
                tooltip: _text(context, '任务操作', 'Task actions'),
                enabled: !pending,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                    minimumSize: const Size(32, 32),
                    maximumSize: const Size(32, 32)),
                icon: pending
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: muted))
                    : Icon(Icons.more_horiz_rounded, size: 20, color: muted),
                onSelected: (action) {
                  if (action == 'main-conversation') {
                    widget.client.openWorkspaceConversation(
                        task['conversation_id'] as String);
                    widget.onConversationOpened?.call();
                  } else if (action == 'open') {
                    _open(task);
                  } else {
                    _control(task, action);
                  }
                },
                itemBuilder: (_) => [
                      if (task['conversation_id'] is String &&
                          task['conversation_id'] !=
                              widget.client.workspaceConversationId)
                        PopupMenuItem(
                            value: 'main-conversation',
                            child: Text(_text(context, '打开来源对话',
                                'Open originating conversation'))),
                      PopupMenuItem(
                          value: 'open',
                          enabled: status != 'queued',
                          child: Text(_text(context, '打开执行会话',
                              'Open execution conversation'))),
                      if (['queued', 'running', 'awaiting_approval']
                          .contains(status))
                        PopupMenuItem(
                            value: 'pause',
                            child: Text(_text(context, '暂停', 'Pause'))),
                      if (['paused', 'blocked'].contains(status))
                        PopupMenuItem(
                            value: 'resume',
                            child: Text(_text(context, '继续', 'Resume'))),
                      if (!['cancelled', 'awaiting_review', 'completed']
                          .contains(status))
                        PopupMenuItem(
                            value: 'cancel',
                            child: Text(_text(context, '取消任务', 'Cancel task'))),
                    ]),
          ]),
          if (!widget.dense) ...[
            Text(_status(status),
                style: theme.textTheme.labelSmall?.copyWith(color: color)),
            const SizedBox(height: 6),
            Tooltip(
                message: _text(context, '排队 → 执行 → 待验收',
                    'Queued → Running → Ready for review'),
                child: Semantics(
                    label: _text(context, '执行阶段', 'Execution stage'),
                    value: _status(status),
                    child: Row(children: [
                      for (var index = 0; index < 3; index++) ...[
                        if (index > 0) const SizedBox(width: 4),
                        Expanded(
                            child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    color: stage >= index
                                        ? color
                                        : muted.withValues(alpha: .16)))),
                      ]
                    ]))),
            const SizedBox(height: 8),
            Tooltip(
                message: progress,
                child: Text(progress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, height: 1.4))),
          ],
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: EdgeInsets.only(
              top: widget.dense ? 18 : 0, bottom: widget.dense ? 2 : 8),
          child: Row(children: [
            if (!widget.dense) ...[
              Icon(Icons.account_tree_outlined, size: 14, color: muted),
              const SizedBox(width: 6),
            ],
            Expanded(
                child: Text(_text(context, '关联任务', 'Linked tasks'),
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: widget.dense ? 11 : null,
                        fontWeight: FontWeight.w500,
                        color: muted))),
            Text(
                _text(context, '最近 ${tasks.length} 项',
                    '${tasks.length} most recent'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w500, color: muted)),
          ])),
      LayoutBuilder(builder: (context, constraints) {
        if (tasks.length == 2 && constraints.maxWidth >= 600) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: card(tasks[0])),
            SizedBox(width: widget.dense ? 24 : 8),
            Expanded(child: card(tasks[1])),
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, task) in tasks.indexed) ...[
                if (index > 0 && !widget.dense) const SizedBox(height: 8),
                card(task),
              ]
            ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showSessionsOnly) {
      return _buildLinkedSessions(widget.recentTaskLimit ?? _tasks.length);
    }
    if (_tasks.isEmpty &&
        (!widget.showReturnedAnswers || _answers.isEmpty) &&
        !_returnPending &&
        !_returnGenerating) {
      return const SizedBox.shrink();
    }
    if (widget.recentTaskLimit case final limit?) {
      return _buildRecentTasks(limit);
    }
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final accent = AppColors.accentBlueFor(brightness);
    final muted = AppColors.mutedSoftFor(brightness);
    final line = AppColors.outlineFor(brightness).withValues(alpha: .6);
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), side: BorderSide(color: line));
    final showDetails = !widget.compact || _detailsExpanded;
    final visible = !showDetails
        ? const <Map<String, dynamic>>[]
        : _expanded
            ? _tasks
            : _tasks.take(4);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showReturnedAnswers)
        for (final answer in _answers)
          Card(
              margin: const EdgeInsets.only(top: 12),
              elevation: 0,
              color: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shape: const RoundedRectangleBorder(),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Icon(Icons.auto_awesome_outlined,
                              size: 16, color: muted),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  _text(context, '工作区助手答复',
                                      'Workspace assistant reply'),
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600))),
                        ]),
                        if (answer['_original_request']
                            case final String original)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(original,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: muted, height: 1.5))),
                        const SizedBox(height: 12),
                        SelectableText(answer['content'] as String? ?? '',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(height: 1.65),
                            maxLines: _expandedReplies.contains(answer['id'])
                                ? null
                                : 5),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                style: TextButton.styleFrom(
                                    foregroundColor: accent),
                                onPressed: () => setState(() {
                                      final id = answer['id'] as String;
                                      if (!_expandedReplies.add(id)) {
                                        _expandedReplies.remove(id);
                                      }
                                    }),
                                child: Text(_expandedReplies
                                        .contains(answer['id'])
                                    ? _text(context, '收起答复', 'Collapse reply')
                                    : _text(context, '展开完整答复',
                                        'Read full reply')))),
                      ]))),
      if (_returnGenerating)
        _notice(_text(context, '子任务已返回，主任务正在整理答复…',
            'Subtask results returned. The main task is preparing its reply…')),
      if (_returnPending)
        _notice(
            _text(context, '主任务答复暂未生成，正在重试…',
                'The main task is retrying its reply…'),
            warning: true),
      if (_tasks.isNotEmpty)
        Semantics(
            button: widget.compact,
            expanded: widget.compact ? _detailsExpanded : null,
            child: InkWell(
                onTap: widget.compact
                    ? () => setState(() => _detailsExpanded = !_detailsExpanded)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                    padding: widget.compact
                        ? const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 8)
                        : const EdgeInsets.only(top: 20, bottom: 2),
                    child: Row(children: [
                      Icon(Icons.account_tree_outlined, size: 16, color: muted),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              widget.requestId == null
                                  ? _text(context, '已安排的任务', 'Scheduled tasks')
                                  : _progressLabel(),
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: muted))),
                      Text('${_tasks.length}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: muted)),
                      if (widget.compact) ...[
                        const SizedBox(width: 8),
                        Icon(
                            _detailsExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: muted),
                      ],
                    ])))),
      if (_error != null)
        _notice(
            _text(context, '进度暂未更新，正在重试…', 'Progress unavailable. Retrying…'),
            warning: true),
      for (final task in visible)
        Card(
            margin: const EdgeInsets.only(top: 10),
            elevation: 0,
            color: AppColors.panelFor(brightness),
            surfaceTintColor: Colors.transparent,
            shape: shape,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                          onTap: task['status'] == 'queued'
                              ? null
                              : () => _open(task),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Text(task['title'] as String,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600))),
                                      const SizedBox(width: 8),
                                      Icon(Icons.chevron_right_rounded,
                                          size: 18, color: muted),
                                    ]),
                                const SizedBox(height: 8),
                                Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                              color:
                                                  accent.withValues(alpha: .08),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text(
                                              _status(task['status'] as String),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(color: accent))),
                                      Text(
                                          '${task['agent']} · ${widget.projects.where((p) => p.id == task['project_id']).firstOrNull?.name ?? task['project_id']}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: muted)),
                                    ]),
                                if ((task['summary'] as String? ?? '')
                                    .isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(task['summary'] as String,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: muted, height: 1.5))),
                                if (task['status'] == 'queued' &&
                                    (task['dependencies'] as List? ?? [])
                                        .isNotEmpty)
                                  Text(
                                      _text(context, '等待前置任务或项目空闲',
                                          'Waiting for prerequisites or project availability'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ])),
                      Wrap(spacing: 8, children: [
                        if (['queued', 'running', 'awaiting_approval']
                            .contains(task['status']))
                          TextButton(
                              style:
                                  TextButton.styleFrom(foregroundColor: accent),
                              onPressed: _pending.contains(task['id'])
                                  ? null
                                  : () => _control(task, 'pause'),
                              child: Text(_text(context, '暂停', 'Pause'))),
                        if (['paused', 'blocked'].contains(task['status']))
                          TextButton(
                              style:
                                  TextButton.styleFrom(foregroundColor: accent),
                              onPressed: _pending.contains(task['id'])
                                  ? null
                                  : () => _control(task, 'resume'),
                              child: Text(_text(context, '继续', 'Resume'))),
                        if (!['cancelled', 'awaiting_review']
                            .contains(task['status']))
                          TextButton(
                              style:
                                  TextButton.styleFrom(foregroundColor: muted),
                              onPressed: _pending.contains(task['id'])
                                  ? null
                                  : () => _control(task, 'cancel'),
                              child:
                                  Text(_text(context, '取消任务', 'Cancel task'))),
                      ]),
                    ]))),
      if (showDetails && _tasks.length > 4)
        TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded
                ? _text(context, '收起', 'Show less')
                : _text(context, '查看全部调度任务', 'Show all scheduled tasks'))),
    ]);
  }
}

class WorkspaceDispatchAgentOptions extends StatefulWidget {
  const WorkspaceDispatchAgentOptions(
      {super.key, required this.client, this.onSaved, this.onAgentChanged});
  final BridgeClient client;
  final VoidCallback? onSaved;
  final ValueChanged<String>? onAgentChanged;
  @override
  State<WorkspaceDispatchAgentOptions> createState() =>
      _WorkspaceDispatchAgentOptionsState();
}

class _WorkspaceDispatchAgentOptionsState
    extends State<WorkspaceDispatchAgentOptions> {
  static final _saved = ValueNotifier<int>(0);
  void _refreshSaved() {
    unawaited(_load());
  }

  String _agent = 'pi';
  bool _busy = true;
  late int _revision;
  static const _agents = {
    'pi': 'Pi',
    'codex': 'Codex',
    'claude_code': 'Claude Code',
    'open_code': 'OpenCode',
    'acp': 'ACP'
  };
  @override
  void initState() {
    super.initState();
    _revision = widget.client.connectionRevision;
    widget.client.sessionCacheRevision.addListener(_changed);
    _saved.addListener(_refreshSaved);
    unawaited(_load());
  }

  void _changed() {
    if (_revision == widget.client.connectionRevision) return;
    _revision = widget.client.connectionRevision;
    setState(() {
      _agent = 'pi';
      _busy = true;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.client.sessionCacheRevision.removeListener(_changed);
    _saved.removeListener(_refreshSaved);
    super.dispose();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final data = await widget.client.workspaceAgentRequest(
          action: '/dispatch/settings') as Map<String, dynamic>;
      if (mounted && revision == _revision) {
        setState(() => _agent = data['agent'] as String? ?? 'pi');
        widget.onAgentChanged?.call(_agent);
      }
    } catch (_) {
      // Older bridges still allow chatting; selection writes surface errors.
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _save(String value) async {
    if (_busy) return;
    final revision = _revision;
    setState(() => _busy = true);
    try {
      await widget.client.workspaceAgentRequest(
          action: '/dispatch/settings', method: 'PUT', body: {'agent': value});
      if (mounted && revision == _revision) {
        setState(() => _agent = value);
        widget.onAgentChanged?.call(value);
        _saved.value++;
        widget.onSaved?.call();
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        ScaffoldMessenger.of(context)
            .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            for (final entry in _agents.entries)
              ComposerSettingsOption(
                  key: ValueKey(['agent-dispatch-option', entry.key].join('-')),
                  label: entry.value,
                  selected: entry.key == _agent,
                  onTap: _busy ? null : () => unawaited(_save(entry.key))),
          ]);
}
