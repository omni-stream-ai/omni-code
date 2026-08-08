import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_spacing.dart';

Future<ProjectAiApprovalSettings?> showProjectAiApprovalPromptDialog(
  BuildContext context, {
  required BridgeClient client,
  required String projectId,
}) {
  return showDialog<ProjectAiApprovalSettings>(
    context: context,
    builder: (_) => _ProjectAiApprovalPromptDialog(
      client: client,
      projectId: projectId,
    ),
  );
}

class _ProjectAiApprovalPromptDialog extends StatefulWidget {
  const _ProjectAiApprovalPromptDialog({
    required this.client,
    required this.projectId,
  });

  final BridgeClient client;
  final String projectId;

  @override
  State<_ProjectAiApprovalPromptDialog> createState() =>
      _ProjectAiApprovalPromptDialogState();
}

class _ProjectAiApprovalPromptDialogState
    extends State<_ProjectAiApprovalPromptDialog> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings =
          await widget.client.getProjectAiApprovalSettings(widget.projectId);
      if (!mounted) return;
      _controller.text = settings.prompt;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.client.updateProjectAiApprovalSettings(
        widget.projectId,
        ProjectAiApprovalSettings(prompt: _controller.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(context.l10n.projectAiApprovalPrompt),
      content: SizedBox(
        width: size.width < 600 ? size.width : 720,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.65),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _load();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.l10n.retry),
                      ),
                    )
                  : TextField(
                      key: const Key('project-ai-approval-prompt-field'),
                      controller: _controller,
                      minLines: 10,
                      maxLines: null,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: context.l10n.projectAiApprovalPromptHint,
                        alignLabelWithHint: true,
                      ),
                    ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _loading || _error != null || _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(context.l10n.save),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        0,
        AppSpacing.card,
        AppSpacing.card,
      ),
    );
  }
}
