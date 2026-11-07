import 'package:flutter/material.dart';
import '../acceptance_models.dart';
import '../l10n/app_locale.dart';
import 'acceptance_ui.dart';
import 'app_card.dart';

Map<String, String> acceptanceBuildLabels(BuildContext context) {
  final l = context.l10n;
  return {
    'language': l.acceptanceBuildLanguage,
    'package_manager': l.acceptanceBuildManager,
    'install_command': l.acceptanceBuildInstall,
    'build_command': l.acceptanceBuildCommand,
    'start_command': l.acceptanceBuildStart,
    'artifact_directory': l.acceptanceBuildOutput,
  };
}

class AcceptanceBuildForm extends StatelessWidget {
  const AcceptanceBuildForm(
      {super.key,
      required this.controllers,
      required this.onIdentify,
      this.busy = false,
      this.detecting = false,
      this.detection});
  final Map<String, TextEditingController> controllers;
  final VoidCallback onIdentify;
  final bool busy, detecting;
  final AcceptanceBuildDetection? detection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final labels = acceptanceBuildLabels(context);
    Widget field(String key) => TextField(
          key: Key('acceptance-build-$key'),
          controller: controllers[key],
          enabled: !busy,
          minLines: 1,
          maxLines: key.endsWith('command') ? 4 : 1,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              labelText: labels[key],
              hintText: l.acceptanceBuildEmpty,
              border: const OutlineInputBorder()),
        );
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.inventory_2_outlined, color: acceptanceAccent(context)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(l.acceptanceBuildTitle,
                style: theme.textTheme.titleMedium)),
      ]),
      const SizedBox(height: 8),
      Text(l.acceptanceBuildHint, style: theme.textTheme.bodySmall),
      const SizedBox(height: 20),
      LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 520
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: field('language')),
                  const SizedBox(width: 12),
                  Expanded(child: field('package_manager'))
                ])
              : Column(children: [
                  field('language'),
                  const SizedBox(height: 16),
                  field('package_manager')
                ])),
      for (final key in AcceptanceBuildConfiguration.fields.skip(2)) ...[
        const SizedBox(height: 16),
        field(key),
      ],
      if (detection?.evidence.isNotEmpty == true) ...[
        const SizedBox(height: 16),
        Text(l.acceptanceBuildEvidence, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final name in detection!.evidence)
            Chip(label: Text(name), visualDensity: VisualDensity.compact),
        ]),
      ],
      for (final warning in detection?.warnings ?? <String>[]) ...[
        const SizedBox(height: 8),
        Text(warning, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      if (detecting) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(l.acceptanceBuildDetecting, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              key: const Key('acceptance-build-agent'),
              onPressed: busy ? null : onIdentify,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(l.acceptanceBuildAgent))),
    ]));
  }
}
