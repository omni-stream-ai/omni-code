import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../theme/app_spacing.dart';

Future<String?> showAiApprovalPromptDialog(
  BuildContext context, {
  required BridgeClient client,
  required String initialPrompt,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AiApprovalPromptDialog(
      client: client,
      initialPrompt: initialPrompt,
    ),
  );
}

class _AiApprovalPromptDialog extends StatefulWidget {
  const _AiApprovalPromptDialog({
    required this.client,
    required this.initialPrompt,
  });

  final BridgeClient client;
  final String initialPrompt;

  @override
  State<_AiApprovalPromptDialog> createState() =>
      _AiApprovalPromptDialogState();
}

class _AiApprovalPromptDialogState extends State<_AiApprovalPromptDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prompt = await widget.client.updateAiApprovalPrompt(
        _controller.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(prompt);
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
      title: Text(context.l10n.aiApprovalPrompt),
      content: SizedBox(
        width: size.width < 600 ? size.width : 720,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.65),
          child: TextField(
            key: const Key('ai-approval-prompt-field'),
            controller: _controller,
            minLines: 10,
            maxLines: null,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10n.aiApprovalPromptHint,
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
          onPressed: _saving ? null : _save,
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
