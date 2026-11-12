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
      this.selectedDirectory,
      this.onSelectTarget,
      this.onToggleTarget,
      this.targets = const [],
      this.reasoning = '',
      this.requirements,
      this.detection});
  final Map<String, TextEditingController> controllers;
  final VoidCallback onIdentify;
  final bool busy, detecting;
  final AcceptanceBuildDetection? detection;
  final String? selectedDirectory;
  final ValueChanged<String?>? onSelectTarget;
  final void Function(String, bool)? onToggleTarget;
  final List<AcceptanceBuildTarget> targets;
  final String reasoning;
  final TextEditingController? requirements;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final labels = acceptanceBuildLabels(context);
    final selected = detection?.candidates
        .where((candidate) => candidate.directory == selectedDirectory)
        .firstOrNull;
    final details = selected?.detection ?? detection;
    final active = targets
        .where((target) => target.directory == selectedDirectory)
        .firstOrNull;
    String targetLabel(
            String directory, AcceptanceBuildConfiguration configuration) =>
        [directory, configuration.values['language'] ?? '']
            .where((value) => value.isNotEmpty)
            .join(' · ');
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
      if (detecting) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(l.acceptanceBuildDetecting, style: theme.textTheme.bodySmall),
      ],
      if (requirements != null) ...[
        const SizedBox(height: 16),
        TextField(
            key: const Key('acceptance-build-requirements'),
            controller: requirements,
            enabled: !busy,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
                labelText: l.acceptanceBuildRequirements,
                helperText: l.acceptanceBuildContextHint,
                helperMaxLines: 3,
                border: const OutlineInputBorder())),
      ],
      if (detection?.candidates.isNotEmpty == true) ...[
        const SizedBox(height: 16),
        Text(l.acceptanceBuildRelatedProjects,
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final candidate in detection!.candidates)
            FilterChip(
                key:
                    ValueKey('acceptance-build-include-${candidate.directory}'),
                label: Text(targetLabel(
                    candidate.directory, candidate.detection.configuration)),
                selected: targets
                    .any((target) => target.directory == candidate.directory),
                onSelected: busy || onToggleTarget == null
                    ? null
                    : (included) =>
                        onToggleTarget!(candidate.directory, included)),
        ]),
      ],
      if (reasoning.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(reasoning,
            key: const Key('acceptance-build-reasoning'),
            style: theme.textTheme.bodySmall),
      ],
      if (targets.length > 1) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            key: const Key('acceptance-build-target'),
            initialValue: selectedDirectory,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: l.acceptanceBuildTargetDetails,
                border: const OutlineInputBorder()),
            items: [
              for (final target in targets)
                DropdownMenuItem(
                    value: target.directory,
                    child: Text(
                        targetLabel(target.directory, target.configuration),
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: busy ? null : onSelectTarget),
      ],
      if (active != null &&
          (active.role.isNotEmpty || active.reason.isNotEmpty)) ...[
        const SizedBox(height: 8),
        Text(
            [active.role, active.reason]
                .where((value) => value.isNotEmpty)
                .join(' · '),
            key: const Key('acceptance-build-target-reason'),
            style: theme.textTheme.bodySmall),
      ],
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
      if (details?.evidence.isNotEmpty == true) ...[
        const SizedBox(height: 16),
        Text(l.acceptanceBuildEvidence, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final name in details!.evidence)
            Chip(label: Text(name), visualDensity: VisualDensity.compact),
        ]),
      ],
      for (final warning in details?.warnings ?? <String>[]) ...[
        const SizedBox(height: 8),
        Text(warning, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
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
