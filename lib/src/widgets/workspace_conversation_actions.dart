import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../models.dart';
import '../utils/time_format.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

Future<String?> showWorkspaceConversationLibrary(BuildContext context,
        {required BridgeClient client,
        bool memories = false,
        String? projectId,
        List<ProjectSummary> projects = const []}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _ConversationLibrary(
            client: client,
            memories: memories,
            projectId: projectId,
            projects: projects));

class WorkspaceConversationActions extends StatelessWidget {
  const WorkspaceConversationActions(
      {super.key,
      required this.client,
      this.enabled = true,
      this.projectId,
      this.onConversationOpened,
      this.projects = const []});
  final BridgeClient client;
  final bool enabled;
  final String? projectId;
  final List<ProjectSummary> projects;
  final VoidCallback? onConversationOpened;

  Future<void> _open(BuildContext context, String action) async {
    final selected = await showWorkspaceConversationLibrary(context,
        client: client,
        memories: action == 'memories',
        projectId: projectId,
        projects: projects);
    if (selected != null && context.mounted) {
      client.openWorkspaceConversation(selected);
      onConversationOpened?.call();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            key: const Key('main-agent-new-conversation'),
            tooltip: _text(context, '新会话', 'New conversation'),
            onPressed: enabled ? client.startWorkspaceConversation : null,
            icon: const Icon(Icons.add_comment_outlined, size: 19)),
        PopupMenuButton<String>(
            key: const Key('main-agent-conversation-menu'),
            enabled: enabled,
            tooltip: _text(context, '会话与记忆', 'Conversations and memory'),
            icon: const Icon(Icons.history_rounded, size: 20),
            onSelected: (action) => _open(context, action),
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'history',
                      child:
                          Text(_text(context, '历史会话', 'Conversation history'))),
                  PopupMenuItem(
                      value: 'memories',
                      child: Text(_text(context, '长期记忆', 'Long-term memory'))),
                ]),
      ]);
}

class _ConversationLibrary extends StatefulWidget {
  const _ConversationLibrary(
      {required this.client,
      required this.memories,
      this.projectId,
      required this.projects});
  final BridgeClient client;
  final bool memories;
  final String? projectId;
  final List<ProjectSummary> projects;
  @override
  State<_ConversationLibrary> createState() => _ConversationLibraryState();
}

class _ConversationLibraryState extends State<_ConversationLibrary> {
  List<Map<String, dynamic>>? _items;
  Object? _error;
  final _deleting = <String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.client.workspaceAgentRequest(
          action: widget.memories ? '/memories' : '/conversations',
          projectId: widget.memories ? widget.projectId : null);
      if (mounted) {
        setState(() {
          _items = (data as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _forget(String id) async {
    setState(() => _deleting.add(id));
    try {
      await widget.client.workspaceAgentRequest(
          action: '/memories/${Uri.encodeComponent(id)}', method: 'DELETE');
      if (mounted) {
        setState(() => _items?.removeWhere((item) => item['id'] == id));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  String _scope(Map<String, dynamic> item) {
    final id = item['project_id'] as String?;
    if (id == null) return _text(context, '全部项目', 'All projects');
    return widget.projects
            .where((project) => project.id == id)
            .firstOrNull
            ?.name ??
        _text(context, '项目记忆', 'Project memory');
  }

  @override
  Widget build(BuildContext context) {
    final memories = widget.memories;
    return Dialog(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  memories
                                      ? _text(
                                          context, '长期记忆', 'Long-term memory')
                                      : _text(context, '历史会话',
                                          'Conversation history'),
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          IconButton(
                              tooltip: _text(context, '关闭', 'Close'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ])),
                    if (memories)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: Text(
                              _text(
                                  context,
                                  '新的会话会参考这些偏好和项目约定。可以在对话中要求记住、修改或忘记。',
                                  'New conversations can refer to these preferences and project conventions. Ask the agent to remember, update, or forget them.'),
                              style: Theme.of(context).textTheme.bodySmall)),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(children: [
                            Expanded(
                                child: Text('$_error',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                            TextButton(
                                onPressed: _load,
                                child: Text(_text(context, '重试', 'Retry'))),
                          ])),
                    Expanded(
                        child: _items == null
                            ? Center(
                                child: _error == null
                                    ? const CircularProgressIndicator()
                                    : const SizedBox.shrink())
                            : _items!.isEmpty
                                ? Center(
                                    child: Text(memories
                                        ? _text(context, '还没有长期记忆',
                                            'No memories yet')
                                        : _text(context, '还没有历史会话',
                                            'No conversations yet')))
                                : ListView.separated(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    itemCount: _items!.length,
                                    separatorBuilder: (_, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final item = _items![index];
                                      final id = item['id'] as String;
                                      final updated = DateTime.tryParse(
                                          item['updated_at'] as String? ?? '');
                                      return ListTile(
                                        key: ValueKey(
                                            'main-agent-${memories ? 'memory' : 'history'}-$id'),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 24, vertical: 8),
                                        selected: !memories &&
                                            id ==
                                                widget.client
                                                    .workspaceConversationId,
                                        title: Text(
                                            (memories
                                                        ? item['content']
                                                        : item['title'])
                                                    as String? ??
                                                '',
                                            maxLines: memories ? null : 2,
                                            overflow: memories
                                                ? null
                                                : TextOverflow.ellipsis),
                                        subtitle: memories
                                            ? Text(_scope(item))
                                            : Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                    if ((item['preview']
                                                                as String?)
                                                            ?.isNotEmpty ==
                                                        true)
                                                      Text(
                                                          item['preview']
                                                              as String,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    if (updated != null)
                                                      Text(formatRelativeTime(
                                                          updated,
                                                          languageCode:
                                                              Localizations
                                                                      .localeOf(
                                                                          context)
                                                                  .languageCode)),
                                                  ]),
                                        trailing: memories
                                            ? IconButton(
                                                tooltip: _text(
                                                    context, '忘记', 'Forget'),
                                                onPressed:
                                                    _deleting.contains(id)
                                                        ? null
                                                        : () => _forget(id),
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 20))
                                            : const Icon(Icons.chevron_right),
                                        onTap: memories
                                            ? null
                                            : () => Navigator.pop(context, id),
                                      );
                                    })),
                  ]),
            )));
  }
}
