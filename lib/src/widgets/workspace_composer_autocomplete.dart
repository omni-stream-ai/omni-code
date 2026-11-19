import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge_client.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import 'anchored_overlay_panel.dart';
import 'workspace_composer_reference.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

const workspaceSlashCommands = [
  '/new',
  '/history',
  '/memory',
  '/model',
  '/help'
];

String workspaceCommandDescription(BuildContext context, String command) =>
    switch (command) {
      '/new' => _text(context, '开始新会话', 'Start a new conversation'),
      '/history' => _text(context, '打开历史会话', 'Open conversation history'),
      '/memory' => _text(context, '查看长期记忆', 'View long-term memory'),
      '/model' => _text(context, '选择模型服务和模型', 'Choose a provider and model'),
      _ => _text(context, '查看命令和引用用法', 'Show commands and reference help'),
    };

typedef _Query = ({String kind, String prefix, int start, int end});
typedef _Item = ({String label, String? description, Object value});

class WorkspaceComposerAutocomplete extends StatefulWidget {
  const WorkspaceComposerAutocomplete({
    super.key,
    required this.client,
    required this.controller,
    required this.focusNode,
    required this.agent,
    required this.onReference,
    required this.onProjectSelected,
    required this.onSubmit,
    required this.child,
    this.projectId,
    this.projects = const [],
    this.enabled = true,
    this.allowProjectChange = true,
  });
  final BridgeClient client;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String agent;
  final String? projectId;
  final List<ProjectSummary> projects;
  final ValueChanged<WorkspaceComposerReference> onReference;
  final ValueChanged<ProjectSummary> onProjectSelected;
  final VoidCallback onSubmit;
  final bool enabled;
  final bool allowProjectChange;
  final Widget child;

  @override
  State<WorkspaceComposerAutocomplete> createState() =>
      WorkspaceComposerAutocompleteState();
}

class WorkspaceComposerAutocompleteState
    extends State<WorkspaceComposerAutocomplete> {
  final _anchor = GlobalKey();
  final _overlay = OverlayPortalController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<_Item> _items = [];
  _Query? _query;
  String? _signature;
  bool _dismissed = false, _loading = false, _choosingProject = false;
  Object? _error;
  int _generation = 0, _selected = 0;
  List<ProjectSummary> get _projects => widget.projects.isNotEmpty
      ? widget.projects
      : widget.client.peekProjects() ?? [];
  String? get _projectId =>
      widget.projectId ?? (_projects.length == 1 ? _projects.single.id : null);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant WorkspaceComposerAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.agent != widget.agent ||
        oldWidget.client != widget.client ||
        oldWidget.enabled != widget.enabled) {
      _signature = null;
      _choosingProject = false;
      _refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.controller.removeListener(_refresh);
    widget.focusNode.removeListener(_focusChanged);
    _scroll.dispose();
    super.dispose();
  }

  _Query? _readQuery() {
    final value = widget.controller.value;
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return null;
    }
    final end = value.selection.baseOffset;
    if (end < 0 || end > value.text.length) return null;
    final before = value.text.substring(0, end);
    if (before.startsWith('/') && !before.contains(RegExp(r'\s'))) {
      return (kind: 'command', prefix: before, start: 0, end: end);
    }
    if (before.startsWith(r'$') && !before.contains(RegExp(r'\s'))) {
      return (kind: 'skill', prefix: before, start: 0, end: end);
    }
    final match = RegExp(r'(^|\s)@(?:"([^"]*)|([^\s"@]*))$').firstMatch(before);
    if (match == null) return null;
    final prefix = match.group(2) ?? match.group(3) ?? '';
    if (prefix.startsWith('/') || prefix.split('/').contains('..')) return null;
    return (
      kind: 'file',
      prefix: prefix,
      start: match.start + (match.group(1)?.length ?? 0),
      end: match.group(2) != null &&
              end < value.text.length &&
              value.text[end] == '"'
          ? end + 1
          : end
    );
  }

  void _focusChanged() {
    _refresh();
    _syncOverlay();
  }

  void _syncOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.enabled &&
          widget.focusNode.hasFocus &&
          _query != null &&
          !_dismissed) {
        _overlay.show();
      } else if (_overlay.isShowing) {
        _overlay.hide();
      }
    });
  }

  void _refresh() {
    final query =
        widget.enabled && widget.focusNode.hasFocus ? _readQuery() : null;
    final signature =
        '$query|$_projectId|${widget.agent}|$_choosingProject|${widget.client.connectionRevision}|${widget.client.workspaceConversationId}';
    if (signature == _signature) {
      _syncOverlay();
      return;
    }
    _signature = signature;
    final generation = ++_generation;
    _debounce?.cancel();
    setState(() {
      _query = query;
      _selected = 0;
      _dismissed = false;
      _error = null;
      _items = [];
      _loading = false;
      if (query?.kind == 'command') {
        _items = [
          for (final command in workspaceSlashCommands)
            if (command.startsWith(query!.prefix.toLowerCase()))
              (label: command, description: null, value: command)
        ];
      } else if (query?.kind == 'skill' && widget.agent != 'codex') {
        _items = [];
      } else if (query != null && (_choosingProject || _projectId == null)) {
        _items = [
          for (final project in _projects)
            (label: project.name, description: project.rootPath, value: project)
        ];
      } else if (query != null) {
        _loading = true;
        _debounce = Timer(const Duration(milliseconds: 160),
            () => unawaited(_load(query, generation)));
      }
    });
    _syncOverlay();
  }

  Future<void> _load(_Query query, int generation) async {
    final projectId = _projectId!;
    try {
      final List<_Item> items;
      if (query.kind == 'skill') {
        final commands =
            await widget.client.listAgentCommands(projectId: projectId);
        items = [
          for (final command in commands)
            if ((command.agentId == null || command.agentId == widget.agent) &&
                command.name.startsWith(r'$') &&
                command.name
                    .toLowerCase()
                    .startsWith(query.prefix.toLowerCase()))
              (
                label: command.name,
                description: command.description,
                value: command
              )
        ];
      } else {
        final files = await widget.client.listFileCompletions(
            projectId: projectId, prefix: query.prefix, limit: 12);
        items = [
          for (final file in files)
            (label: file.path, description: null, value: file)
        ];
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
    _syncOverlay();
  }

  bool acceptSuggestion() {
    if (!_overlay.isShowing || _dismissed || _items.isEmpty || _query == null) {
      return false;
    }
    final item = _items[_selected];
    if (item.value case final ProjectSummary project) {
      _choosingProject = false;
      widget.onProjectSelected(project);
      widget.focusNode.requestFocus();
      return true;
    }
    final query = _query!;
    final project = _projects.where((p) => p.id == _projectId).firstOrNull;
    String replacement;
    bool directory = false;
    WorkspaceComposerReference? reference;
    if (item.value case final FileCompletionItem file) {
      directory = file.isDir;
      final path =
          directory && !file.path.endsWith('/') ? '${file.path}/' : file.path;
      replacement = path.contains(RegExp(r'\s'))
          ? '@"$path${directory ? '' : '"'}'
          : '@$path';
      if (!directory) {
        reference = WorkspaceComposerReference(
            kind: 'file',
            projectId: _projectId!,
            projectName: project?.name ?? '',
            value: file.path);
      }
    } else if (item.value case final AgentCommand skill) {
      replacement = '${skill.name} ';
      reference = WorkspaceComposerReference(
          kind: 'skill',
          projectId: _projectId!,
          projectName: project?.name ?? '',
          value: skill.name.substring(1));
    } else {
      replacement = '${item.label} ';
    }
    final value = widget.controller.value;
    widget.controller.value = TextEditingValue(
        text: value.text.replaceRange(query.start, query.end, replacement),
        selection:
            TextSelection.collapsed(offset: query.start + replacement.length));
    if (reference != null) widget.onReference(reference);
    _dismissed = !directory;
    if (!directory) {
      _debounce?.cancel();
      _generation++;
      _loading = false;
    }
    _syncOverlay();
    widget.focusNode.requestFocus();
    return true;
  }

  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent ||
        !widget.controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_overlay.isShowing && !_dismissed) {
      if (key == LogicalKeyboardKey.escape) {
        _dismissed = true;
        _overlay.hide();
        return KeyEventResult.handled;
      }
      if (_items.isNotEmpty &&
          (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp)) {
        setState(() => _selected =
            (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
                _items.length);
        if (_scroll.hasClients) {
          _scroll.jumpTo(
              (_selected * 64.0).clamp(0, _scroll.position.maxScrollExtent));
        }
        return KeyEventResult.handled;
      }
      if (!HardwareKeyboard.instance.isShiftPressed &&
          (key == LogicalKeyboardKey.tab ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          acceptSuggestion()) {
        return KeyEventResult.handled;
      }
    }
    if (!HardwareKeyboard.instance.isShiftPressed &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final project = _projects.where((p) => p.id == _projectId).firstOrNull;
    return TextFieldTapRegion(
        child: Material(
      key: const Key('assistant-composer-suggestions'),
      color: AppColors.panelFor(theme.brightness),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.outlineFor(theme.brightness))),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_query?.kind != 'command')
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        (_choosingProject || _projectId == null)
                            ? _text(context, '选择引用的项目', 'Choose a project')
                            : project?.name ??
                                _text(context, '项目引用', 'Project references'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall)),
                if (widget.allowProjectChange &&
                    _projectId != null &&
                    _projects.length > 1)
                  TextButton(
                      key: const Key('assistant-reference-change-project'),
                      onPressed: () {
                        _choosingProject = true;
                        _signature = null;
                        _refresh();
                      },
                      child: Text(_text(context, '切换项目', 'Change project'))),
              ])),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator())
        else if (_error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Text(_text(
                        context, '加载失败，请重试', 'Could not load suggestions'))),
                TextButton(
                    onPressed: () {
                      _signature = null;
                      _refresh();
                    },
                    child: Text(_text(context, '重试', 'Retry')))
              ]))
        else if (_items.isEmpty)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_query?.kind == 'skill' && widget.agent != 'codex'
                  ? _text(context, '切换执行 Agent 为 Codex 后可选择技能',
                      'Choose Codex as the execution agent to use skills')
                  : _text(context, '没有匹配的选项', 'No matching suggestions')))
        else
          Flexible(
              child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                        key: ValueKey(('assistant-completion', item.label)),
                        dense: true,
                        selected: index == _selected,
                        title: Text(item.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: item.description != null ||
                                _query?.kind == 'command'
                            ? Text(
                                item.description ??
                                    workspaceCommandDescription(
                                        context, item.label),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: () {
                          _selected = index;
                          acceptSuggestion();
                        });
                  })),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => AnchoredOverlayPanel(
          targetKey: _anchor,
          maxWidth: 680,
          preferBelow: true,
          child: _panel(context)),
      child: KeyedSubtree(key: _anchor, child: widget.child));
}
