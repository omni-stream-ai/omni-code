import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../theme/app_colors.dart';
import '../workspace_agent_models.dart';
import 'project_avatar.dart';
import 'workspace_dispatch_panel.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

class WorkspaceProjectContextPanel extends StatefulWidget {
  const WorkspaceProjectContextPanel({
    super.key,
    required this.data,
    required this.snapshot,
    required this.client,
    required this.showTasks,
    required this.taskBuilder,
    required this.onOpenSession,
    required this.onRefresh,
  });

  final WorkspaceProjectContext data;
  final Map<String, dynamic> snapshot;
  final BridgeClient client;
  final bool showTasks;
  final Widget Function(WorkspaceTask) taskBuilder;
  final void Function(String projectId, String sessionId) onOpenSession;
  final Future<void> Function() onRefresh;

  @override
  State<WorkspaceProjectContextPanel> createState() =>
      _WorkspaceProjectContextPanelState();
}

class _WorkspaceProjectContextPanelState
    extends State<WorkspaceProjectContextPanel> {
  bool _showEnded = false;
  bool _showAll = false;

  @override
  void didUpdateWidget(covariant WorkspaceProjectContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.project.id != widget.data.project.id) {
      _showEnded = false;
      _showAll = false;
    }
  }

  Widget _heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = AppColors.mutedSoftFor(theme.brightness);
    final data = widget.data;
    final project = data.project;
    final git = data.gitStatus;
    final tasks = (widget.snapshot['tasks'] as List? ?? [])
        .whereType<Map>()
        .where((task) => task['project_id'] == project.id)
        .map((task) => WorkspaceTask.fromJson(Map<String, dynamic>.from(task)))
        .where((task) => !task.archived)
        .toList()
      ..sort((a, b) {
        final state = (a.isOpen ? 0 : 1).compareTo(b.isOpen ? 0 : 1);
        return state != 0
            ? state
            : (b.lastUpdatedAt ?? DateTime(0))
                .compareTo(a.lastUpdatedAt ?? DateTime(0));
      });
    final visible = tasks.where((task) => _showEnded || task.isOpen).toList();
    final representedSessions = tasks
        .where((task) => task.isOpen)
        .map((task) => task.sessionId)
        .toSet();
    final dispatch = (widget.snapshot['dispatch_tasks'] as List? ?? [])
        .whereType<Map>()
        .where((task) =>
            task['project_id'] == project.id &&
            !representedSessions.contains(task['session_id']))
        .where((task) =>
            _showEnded || !['completed', 'cancelled'].contains(task['status']))
        .map((task) => Map<String, dynamic>.from(task))
        .toList();
    Widget metric(String zh, String en, int? count) =>
        Text('${_text(context, zh, en)}  ${count ?? '—'}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted));

    return SingleChildScrollView(
      key: const Key('workspace-project-context-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ProjectAvatar(
              name: project.name, iconDataUri: project.iconDataUri, size: 30),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_text(context, '当前项目', 'Current project'),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                const SizedBox(height: 3),
                Text(project.name,
                    key: const Key('workspace-context-project-name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ])),
          IconButton(
              tooltip: _text(context, '刷新项目状态', 'Refresh project status'),
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18)),
        ]),
        if (project.rootPath.isNotEmpty) ...[
          const SizedBox(height: 10),
          Tooltip(
              message: project.rootPath,
              child: Text(project.rootPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, height: 1.5))),
        ],
        _heading('Git'),
        Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (data.branch?.isNotEmpty == true)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_tree_outlined, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(data.branch!,
                          key: const Key('workspace-context-git-branch'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall)),
                ]),
              Text(
                  git == null
                      ? _text(context, 'Git 状态暂不可用', 'Git status unavailable')
                      : git.dirty
                          ? _text(context, '有未提交改动', 'Uncommitted changes')
                          : _text(context, '工作区干净', 'Working tree clean'),
                  key: const Key('workspace-context-git-state'),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: git == null
                          ? muted
                          : git.dirty
                              ? AppColors.warningTextFor(theme.brightness)
                              : AppColors.successTextFor(theme.brightness))),
            ]),
        if (git != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 8, children: [
            metric('暂存', 'Staged', git.stagedCount),
            metric('未暂存', 'Unstaged', git.unstagedCount),
            metric('未跟踪', 'Untracked', git.untrackedCount),
            if (git.ahead != null) metric('领先', 'Ahead', git.ahead),
            if (git.behind != null) metric('落后', 'Behind', git.behind),
          ]),
        ],
        if (data.commitHead != null) ...[
          const SizedBox(height: 16),
          Text(_text(context, '最近提交', 'Latest commit'),
              style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          const SizedBox(height: 6),
          SelectableText(
              data.commitHead!
                  .substring(0, data.commitHead!.length.clamp(0, 8)),
              style:
                  theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          if (data.commitSubject?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(data.commitSubject!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, height: 1.5)),
          ],
        ],
        const SizedBox(height: 20),
        Divider(height: 1, color: colors.outlineVariant.withValues(alpha: .55)),
        if (widget.showTasks) ...[
          _heading(_text(context, '相关任务', 'Related tasks')),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: Text(_text(context, '未结束', 'Open')),
                selected: !_showEnded,
                onSelected: (_) => setState(() {
                      _showEnded = false;
                      _showAll = false;
                    })),
            ChoiceChip(
                label: Text(_text(context, '全部', 'All')),
                selected: _showEnded,
                onSelected: (_) => setState(() {
                      _showEnded = true;
                      _showAll = false;
                    })),
          ]),
          if (dispatch.isNotEmpty)
            WorkspaceDispatchPanel(
              key: ValueKey(('workspace-context-dispatch', project.id)),
              client: widget.client,
              projectId: project.id,
              projects: [project],
              snapshot: {...widget.snapshot, 'dispatch_tasks': dispatch},
              onRefresh: widget.onRefresh,
              compact: true,
              recentTaskLimit: _showAll ? dispatch.length : 5,
            ),
          const SizedBox(height: 8),
          for (final task in (_showAll ? visible : visible.take(5)))
            widget.taskBuilder(task),
          if (visible.isEmpty && dispatch.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                    _text(
                        context,
                        _showEnded ? '当前项目暂无任务记录' : '当前项目暂无未结束任务',
                        _showEnded
                            ? 'No task records for this project'
                            : 'No open tasks for this project'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted))),
          if (!_showAll && (visible.length > 5 || dispatch.length > 5))
            TextButton(
                onPressed: () => setState(() => _showAll = true),
                child:
                    Text(_text(context, '查看全部相关任务', 'Show all related tasks'))),
        ] else ...[
          _heading(_text(context, '关联会话', 'Linked conversations')),
          if (data.sessions.isEmpty)
            Text(
                _text(context, '当前项目暂无关联会话',
                    'No linked conversations for this project'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          for (final session in data.sessions)
            ListTile(
                contentPadding: EdgeInsets.zero,
                key: ValueKey(('workspace-context-session', session['id'])),
                leading:
                    const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                title: Text(session['title'] as String? ?? '',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: session['preview'] == null
                    ? null
                    : Text(session['preview'] as String,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () =>
                    widget.onOpenSession(project.id, session['id'] as String)),
        ],
      ]),
    );
  }
}
