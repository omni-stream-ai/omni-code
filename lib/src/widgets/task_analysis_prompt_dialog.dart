import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import 'app_snack_bar.dart';

Future<bool?> showTaskAnalysisPromptDialog(
  BuildContext context, {
  required BridgeClient client,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _TaskAnalysisPromptDialog(client: client),
    );

class _TaskAnalysisPromptDialog extends StatefulWidget {
  const _TaskAnalysisPromptDialog({required this.client});

  final BridgeClient client;

  @override
  State<_TaskAnalysisPromptDialog> createState() =>
      _TaskAnalysisPromptDialogState();
}

class _TaskAnalysisPromptDialogState extends State<_TaskAnalysisPromptDialog> {
  final _controller = TextEditingController();
  String _defaultPrompt = '';
  bool _loading = true;
  bool _saving = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await widget.client
          .workspaceAgentRequest(action: '/analysis-settings');
      if (settings is! Map ||
          settings['prompt'] is! String ||
          settings['default_prompt'] is! String ||
          (settings['default_prompt'] as String).trim().isEmpty) {
        throw const FormatException('Invalid task analysis settings response');
      }
      if (!mounted) return;
      setState(() {
        _controller.text = settings['prompt'] as String;
        _defaultPrompt = settings['default_prompt'] as String;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _loadError != null) return;
    setState(() => _saving = true);
    try {
      await widget.client.workspaceAgentRequest(
        action: '/analysis-settings',
        method: 'PUT',
        body: {'prompt': _controller.text.trim()},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(isError: true, content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = !_loading && _loadError == null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(l10n.taskAnalysisPrompt),
        content: SizedBox(
          width: 720,
          child: _loading
              ? Row(children: [
                  const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.taskAnalysisPromptLoading)),
                ])
              : _loadError != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$_loadError'),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                    ])
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.taskAnalysisPromptEditorHelp),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('task-analysis-prompt-field'),
                          controller: _controller,
                          enabled: !_saving,
                          minLines: 6,
                          maxLines: 14,
                          maxLength: 12000,
                          decoration: InputDecoration(
                            hintText: l10n.taskAnalysisPromptHelp,
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
            key: const Key('task-analysis-prompt-reset'),
            onPressed: !ready || _saving
                ? null
                : () => _controller.text = _defaultPrompt,
            child: Text(l10n.taskAnalysisPromptReset),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            key: const Key('task-analysis-prompt-save'),
            onPressed: ready && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
