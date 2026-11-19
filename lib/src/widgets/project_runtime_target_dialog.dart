import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import 'acceptance_build_form.dart';

class ProjectRuntimeTargetDialog extends StatefulWidget {
  const ProjectRuntimeTargetDialog({
    super.key,
    required this.client,
    required this.projectId,
    this.target,
    this.name = '',
    this.renameOnly = false,
  });

  final BridgeClient client;
  final String projectId, name;
  final AcceptanceBuildTarget? target;
  final bool renameOnly;

  @override
  State<ProjectRuntimeTargetDialog> createState() =>
      _ProjectRuntimeTargetDialogState();
}

class _ProjectRuntimeTargetDialogState
    extends State<ProjectRuntimeTargetDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.name);
  late final directory =
      TextEditingController(text: widget.target?.directory ?? '');
  late final fields = {
    for (final key in AcceptanceBuildConfiguration.fields)
      key: TextEditingController(
          text: widget.target?.configuration.values[key] ?? '')
  };
  bool saving = false;
  Object? error;

  @override
  void dispose() {
    name.dispose();
    directory.dispose();
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.renameOnly) {
        await widget.client.renameProjectRuntimeTarget(
            widget.projectId, widget.target!.directory, name.text.trim());
      } else {
        final target = widget.target ??
            AcceptanceBuildTarget(directory: directory.text.trim());
        await widget.client.saveProjectRuntimeTarget(
            widget.projectId,
            target.withConfiguration(AcceptanceBuildConfiguration(values: {
              for (final field in fields.entries)
                field.key: field.value.text.trim()
            })),
            name.text.trim(),
            create: widget.target == null);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = acceptanceBuildLabels(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.renameOnly
                ? l.projectRuntimeRenameTarget
                : widget.target == null
                    ? l.projectRuntimeAddTarget
                    : l.projectRuntimeEditTarget),
            if (error != null) ...[
              const SizedBox(height: 12),
              SelectableText(error.toString(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('runtime-target-name'),
                    controller: name,
                    autofocus: true,
                    enabled: !saving,
                    maxLength: 100,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l.projectRuntimeTargetRequired
                        : null,
                    decoration: InputDecoration(
                        labelText: l.projectRuntimeTargetName,
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  if (widget.renameOnly)
                    Text(widget.target!.directory)
                  else ...[
                    TextFormField(
                      key: const Key('runtime-target-directory'),
                      controller: directory,
                      enabled: !saving,
                      readOnly: widget.target != null,
                      autocorrect: false,
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? l.projectRuntimeTargetRequired
                          : null,
                      decoration: InputDecoration(
                          labelText: l.projectRuntimeTargetDirectory,
                          helperText: l.projectRuntimeTargetDirectoryHint,
                          helperMaxLines: 3,
                          border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Text(l.projectRuntimeTargetCommandsHint),
                    for (final key in AcceptanceBuildConfiguration.fields) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: Key('runtime-target-$key'),
                        controller: fields[key],
                        enabled: !saving,
                        minLines: 1,
                        maxLines: key.endsWith('command') ? 4 : 1,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                            labelText: labels[key],
                            border: const OutlineInputBorder()),
                      ),
                    ],
                  ],
                  if (saving) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(),
              child: Text(l.cancel)),
          FilledButton(
              key: const Key('runtime-target-save'),
              onPressed: saving ? null : save,
              child: Text(l.save)),
        ],
      ),
    );
  }
}
