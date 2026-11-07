import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import '../screens/keyboard_shortcuts_screen.dart';
import 'shortcut_keycaps.dart';

class DesktopSearchDialog extends StatefulWidget {
  const DesktopSearchDialog({super.key, required this.client});

  final BridgeClient client;

  @override
  State<DesktopSearchDialog> createState() => _DesktopSearchDialogState();
}

class _DesktopSearchDialogState extends State<DesktopSearchDialog> {
  final _scrollController = ScrollController();
  late final _searchFocusNode = FocusNode(onKeyEvent: _handleSearchKey);
  List<ProjectSummary> _projects = const [];
  List<SessionSummary> _sessions = const [];
  String _query = '';
  String? _error;
  bool _loading = true;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _projects = widget.client.peekProjects() ?? const [];
    _sessions = widget.client.peekSessions() ?? const [];
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.client.listProjects(),
        widget.client.listSessions(),
      ]);
      if (!mounted) return;
      setState(() {
        _projects = results[0] as List<ProjectSummary>;
        _sessions = results[1] as List<SessionSummary>;
        _loading = false;
        _selected = 0;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  List<Object> get _results {
    final query = _query.trim().toLowerCase();
    final projectNames = {
      for (final project in _projects) project.id: project.name
    };
    return [
      ..._projects.where((project) =>
          '${project.name} ${project.rootPath}'.toLowerCase().contains(query)),
      ..._sessions.where((session) =>
          '${session.title} ${projectNames[session.projectId] ?? ''}'
              .toLowerCase()
              .contains(query)),
    ];
  }

  void _moveSelection(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    if (_scrollController.hasClients) {
      final top = _selected * 64.0;
      final position = _scrollController.position;
      if (top < position.pixels ||
          top + 64 > position.pixels + position.viewportDimension) {
        _scrollController.jumpTo(top.clamp(0.0, position.maxScrollExtent));
      }
    }
  }

  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, _results.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, _results.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final results = _results;
      if (results.isNotEmpty) Navigator.pop(context, results[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final l10n = context.l10n;
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                    child: TextField(
                  focusNode: _searchFocusNode,
                  key: const Key('desktop-search-field'),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.shortcutSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() {
                    _query = value;
                    _selected = 0;
                  }),
                  onSubmitted: (_) {
                    if (results.isNotEmpty) {
                      Navigator.pop(context, results[_selected]);
                    }
                  },
                )),
                IconButton(
                  tooltip: l10n.cancel,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Row(children: [
                  Expanded(
                      child: Text(l10n.loadProjectsFailed(_error!),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: _load, child: Text(l10n.retry)),
                ]),
              const SizedBox(height: 8),
              Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Text(_loading
                              ? l10n.shortcutSearchHint
                              : l10n.noSearchResultsTitle))
                      : ListView.builder(
                          controller: _scrollController,
                          itemExtent: 64,
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index];
                            final project =
                                item is ProjectSummary ? item : null;
                            final session =
                                item is SessionSummary ? item : null;
                            return ListTile(
                              selected: index == _selected,
                              selectedColor: AppColors.textFor(
                                  Theme.of(context).brightness),
                              selectedTileColor: AppColors.accentBlueFor(
                                      Theme.of(context).brightness)
                                  .withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              leading: Icon(project != null
                                  ? Icons.folder_outlined
                                  : Icons.chat_bubble_outline_rounded),
                              title: Text(project?.name ?? session!.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                project?.rootPath ??
                                    _projects
                                        .where(
                                            (p) => p.id == session!.projectId)
                                        .firstOrNull
                                        ?.name ??
                                    session!.projectId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        )),
              Divider(
                  height: 24,
                  color: AppColors.outlineFor(Theme.of(context).brightness)),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _keyHint(context, const ['↑', '↓'], l10n.shortcutSelect),
                  _keyHint(context, const ['Enter'], l10n.shortcutOpen),
                  _keyHint(context, const ['Esc'], l10n.close),
                  TextButton.icon(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.pushNamed(KeyboardShortcutsScreen.routeName);
                    },
                    icon: const Icon(Icons.keyboard_outlined, size: 16),
                    label: Text(l10n.shortcutGuide),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyHint(BuildContext context, List<String> keys, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShortcutKeycaps(labels: keys, compact: true),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
