import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../widgets/app_card.dart';
import '../widgets/acceptance_ui.dart';
import '../widgets/acceptance_build_form.dart';

const _dockerfileTemplate =
    'FROM {{BASE_IMAGE}}\nUSER root\nRUN apt-get update && apt-get install -y --no-install-recommends git unzip xz-utils && rm -rf /var/lib/apt/lists/*\nUSER x11box\nWORKDIR /workspace\n';

class AcceptanceEnvironmentScreen extends StatefulWidget {
  const AcceptanceEnvironmentScreen(
      {super.key,
      required this.client,
      required this.projectId,
      this.sessionId,
      this.requirements,
      this.onRequirementsSaved,
      this.reviewBeforeStart = false});
  final BridgeClient client;
  final String projectId;
  final String? sessionId, requirements;
  final ValueChanged<String>? onRequirementsSaved;
  final bool reviewBeforeStart;
  @override
  State<AcceptanceEnvironmentScreen> createState() =>
      _AcceptanceEnvironmentScreenState();
}

class _AcceptanceEnvironmentScreenState
    extends State<AcceptanceEnvironmentScreen> {
  AcceptanceEnvironmentSettings? settings;
  AcceptanceBuildDetection? detection;
  String? selectedDirectory;
  List<AcceptanceBuildTarget> targets = [];
  String buildReasoning = '';
  late final requirements =
      TextEditingController(text: widget.requirements ?? '');
  final buildFields = {
    for (final key in AcceptanceBuildConfiguration.fields)
      key: TextEditingController()
  };
  bool detecting = false;
  AcceptanceBuildConfiguration get editedConfiguration =>
      AcceptanceBuildConfiguration(values: {
        for (final entry in buildFields.entries)
          entry.key: entry.value.text.trim()
      });
  List<AcceptanceBuildTarget> get buildTargets => [
        for (final target in targets)
          target.directory == selectedDirectory
              ? target.withConfiguration(editedConfiguration)
              : target
      ];
  AcceptanceBuildConfiguration get buildConfiguration =>
      buildTargets.firstOrNull?.configuration ?? editedConfiguration;
  void applyBuild(AcceptanceBuildConfiguration value) {
    for (final entry in buildFields.entries) {
      entry.value.text = value.values[entry.key] ?? '';
    }
  }

  void selectTarget(String? directory) {
    final edited = buildTargets;
    final target =
        edited.where((target) => target.directory == directory).firstOrNull;
    if (target != null) {
      setState(() {
        targets = edited;
        selectedDirectory = directory;
        applyBuild(target.configuration);
      });
      return;
    }
    toggleTarget(directory, true);
  }

  void toggleTarget(String? directory, bool included) {
    final candidate = detection?.candidates
        .where((candidate) => candidate.directory == directory)
        .firstOrNull;
    if (candidate == null) return;
    setState(() {
      targets = buildTargets;
      if (included) {
        if (!targets.any((target) => target.directory == directory)) {
          targets.add(AcceptanceBuildTarget(
              directory: candidate.directory,
              configuration: candidate.detection.configuration));
        }
        selectedDirectory = directory;
      } else {
        targets.removeWhere((target) => target.directory == directory);
        if (selectedDirectory == directory) {
          selectedDirectory = targets.firstOrNull?.directory;
        }
      }
      buildReasoning = '';
      applyBuild(targets
              .where((target) => target.directory == selectedDirectory)
              .firstOrNull
              ?.configuration ??
          const AcceptanceBuildConfiguration());
    });
  }

  void applyTargets(List<AcceptanceBuildTarget> values, String reasoning,
      AcceptanceBuildConfiguration fallback) {
    targets = List.of(values);
    buildReasoning = reasoning;
    selectedDirectory = targets.firstOrNull?.directory;
    applyBuild(targets.firstOrNull?.configuration ?? fallback);
  }

  final dockerfile = TextEditingController();
  final image = TextEditingController();
  String mode = 'auto';
  bool loading = true, saving = false, rebuild = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    for (final controller in buildFields.values) {
      controller.dispose();
    }
    dockerfile.dispose();
    image.dispose();
    requirements.dispose();
    super.dispose();
  }

  Future<void> load() async {
    var identifyAutomatically = false;
    try {
      final value =
          await widget.client.getAcceptanceEnvironment(widget.projectId);
      if (!mounted) return;
      setState(() {
        settings = value;
        detection = value.detection;
        applyTargets(
            value.config.buildTargets,
            value.config.buildReasoning,
            value.config.build ??
                value.detection?.configuration ??
                const AcceptanceBuildConfiguration());
        if (targets.isEmpty &&
            value.config.build == null &&
            detection?.candidates.length == 1 &&
            detection!.configuration.values.values.any((v) => v.isNotEmpty)) {
          final candidate = detection!.candidates.single;
          targets = [
            AcceptanceBuildTarget(
                directory: candidate.directory,
                configuration: detection!.configuration)
          ];
          selectedDirectory = candidate.directory;
        }
        mode = value.config.mode;
        dockerfile.text = value.config.dockerfile.isEmpty
            ? _dockerfileTemplate
            : value.config.dockerfile;
        image.text = value.config.image;
        error = null;
        identifyAutomatically = mode == 'auto' &&
            (requirements.text.trim().isNotEmpty || widget.sessionId != null) &&
            ((detection?.candidates.length ?? 0) > 1 ||
                detection?.configuration.values.values
                        .every((v) => v.isEmpty) ==
                    true) &&
            (widget.reviewBeforeStart ||
                (value.config.build == null &&
                    value.config.buildTargets.isEmpty));
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (identifyAutomatically && mounted) await identify(automatic: true);
  }

  Future<void> save() async {
    if ((mode == 'image' && image.text.trim().isEmpty) ||
        (mode == 'dockerfile' && dockerfile.text.trim().isEmpty)) {
      setState(() => error = context.l10n.acceptanceEnvironmentRequired);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.client.saveAcceptanceEnvironment(
          widget.projectId,
          AcceptanceEnvironmentConfig(
              mode: mode,
              build: buildConfiguration,
              buildTargets: buildTargets,
              buildReasoning: buildReasoning,
              dockerfile: mode == 'dockerfile' ? dockerfile.text : '',
              image: mode == 'image' ? image.text.trim() : ''),
          rebuild: rebuild);
      if (!mounted) return;
      widget.onRequirementsSaved?.call(requirements.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.acceptanceEnvironmentSaved)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> identify({bool automatic = false}) async {
    if (saving || detecting) return;
    setState(() {
      detecting = true;
      error = null;
    });
    try {
      final result = await widget.client.detectAcceptanceBuild(widget.projectId,
          agent: true,
          sessionId: widget.sessionId,
          requirements: requirements.text.trim(),
          currentTargets: buildTargets,
          current: buildConfiguration);
      if (!mounted) return;
      if (automatic) {
        setState(() {
          detection = result;
          applyTargets(result.targets, result.reasoning, result.configuration);
        });
        return;
      }
      setState(() => detecting = false);
      final labels = acceptanceBuildLabels(context);
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(context.l10n.acceptanceBuildProposal),
                content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (result.reasoning.isNotEmpty) ...[
                          Text(result.reasoning),
                          const SizedBox(height: 16),
                        ],
                        for (final target in result.targets) ...[
                          Text(target.directory,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text([target.role, target.reason]
                              .where((v) => v.isNotEmpty)
                              .join(' · ')),
                          for (final key in AcceptanceBuildConfiguration.fields)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: SelectableText(
                                    '${labels[key]}: ${target.configuration.values[key]?.isNotEmpty == true ? target.configuration.values[key] : context.l10n.acceptanceBuildEmpty}')),
                          const SizedBox(height: 16),
                        ],
                        if (result.targets.isEmpty)
                          for (final key in AcceptanceBuildConfiguration.fields)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(labels[key]!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge),
                                      const SizedBox(height: 4),
                                      SelectableText(result.configuration
                                                  .values[key]?.isNotEmpty ==
                                              true
                                          ? result.configuration.values[key]!
                                          : context.l10n.acceptanceBuildEmpty),
                                    ]))
                      ],
                    ))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(context.l10n.cancel)),
                  FilledButton(
                      key: const Key('acceptance-build-apply'),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(context.l10n.acceptanceBuildApply)),
                ],
              ));
      if (accepted == true && mounted) {
        setState(() {
          detection = result;
          applyTargets(result.targets, result.reasoning, result.configuration);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString(),
                maxLines: 3, overflow: TextOverflow.ellipsis)));
      }
    } finally {
      if (mounted) setState(() => detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final hints = {
      'auto': l.acceptanceEnvironmentAutoHint,
      'base': l.acceptanceEnvironmentBaseHint,
      'dockerfile': l.acceptanceEnvironmentDockerfileHint,
      'image': l.acceptanceEnvironmentImageHint
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.acceptanceEnvironmentTitle)),
      bottomNavigationBar: settings == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 728),
                          child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                  key: const Key('acceptance-environment-save'),
                                  onPressed: saving || detecting ? null : save,
                                  icon: saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.check),
                                  label:
                                      Text(l.acceptanceEnvironmentSave))))))),
      body: SafeArea(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          AcceptanceIntro(
                              title: l.acceptanceEnvironmentOverview,
                              subtitle: widget.reviewBeforeStart
                                  ? l.acceptanceBuildReview
                                  : l.acceptanceEnvironmentHint,
                              icon: Icons.layers_outlined),
                          const SizedBox(height: 16),
                          if (error != null) ...[
                            SelectableText(error.toString(),
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 12),
                            if (settings == null)
                              TextButton(onPressed: load, child: Text(l.retry)),
                          ],
                          if (settings != null) ...[
                            if (mode == 'auto') ...[
                              AcceptanceBuildForm(
                                  controllers: buildFields,
                                  requirements: requirements,
                                  onIdentify: () => identify(),
                                  busy: saving || detecting,
                                  detecting: detecting,
                                  selectedDirectory: selectedDirectory,
                                  onSelectTarget: selectTarget,
                                  onToggleTarget: toggleTarget,
                                  targets: buildTargets,
                                  reasoning: buildReasoning,
                                  detection: detection),
                              const SizedBox(height: 16),
                            ],
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  DropdownButtonFormField<String>(
                                    key: const Key(
                                        'acceptance-environment-mode'),
                                    initialValue: mode,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                        labelText:
                                            l.acceptanceEnvironmentTitle),
                                    items: [
                                      DropdownMenuItem(
                                          value: 'auto',
                                          child: Text(
                                              l.acceptanceEnvironmentAuto)),
                                      DropdownMenuItem(
                                          value: 'base',
                                          child: Text(
                                              l.acceptanceEnvironmentBase)),
                                      DropdownMenuItem(
                                          value: 'dockerfile',
                                          child: Text(l
                                              .acceptanceEnvironmentDockerfile)),
                                      DropdownMenuItem(
                                          value: 'image',
                                          child: Text(
                                              l.acceptanceEnvironmentImage))
                                    ],
                                    onChanged: saving
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              setState(() => mode = value);
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  Text(hints[mode] ?? ''),
                                  if (mode == 'dockerfile') ...[
                                    const SizedBox(height: 16),
                                    TextField(
                                        key: const Key(
                                            'acceptance-environment-dockerfile'),
                                        controller: dockerfile,
                                        enabled: !saving,
                                        minLines: 8,
                                        maxLines: 18,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13),
                                        decoration: const InputDecoration(
                                            labelText: 'Dockerfile',
                                            alignLabelWithHint: true,
                                            border: OutlineInputBorder())),
                                  ],
                                  if (mode == 'image') ...[
                                    const SizedBox(height: 16),
                                    if (settings!.available.isNotEmpty) ...[
                                      DropdownButtonFormField<String>(
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                            labelText: l
                                                .acceptanceEnvironmentAvailable),
                                        items: settings!.available
                                            .map((item) => DropdownMenuItem(
                                                value: item.imageId,
                                                child: Text(item.name,
                                                    overflow:
                                                        TextOverflow.ellipsis)))
                                            .toList(),
                                        onChanged: saving
                                            ? null
                                            : (value) {
                                                if (value != null) {
                                                  image.text = value;
                                                }
                                              },
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    TextField(
                                        key: const Key(
                                            'acceptance-environment-image'),
                                        controller: image,
                                        enabled: !saving,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: InputDecoration(
                                            labelText: l
                                                .acceptanceEnvironmentImageLabel)),
                                  ],
                                  const SizedBox(height: 12),
                                  SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      value: rebuild,
                                      onChanged: saving
                                          ? null
                                          : (value) =>
                                              setState(() => rebuild = value),
                                      title:
                                          Text(l.acceptanceEnvironmentRebuild),
                                      subtitle: Text(
                                          l.acceptanceEnvironmentRebuildHint)),
                                ])),
                            const SizedBox(height: 12),
                            if (settings!.current != null) ...[
                              const SizedBox(height: 20),
                              AcceptanceEnvironmentCard(
                                  environment: settings!.current!),
                            ],
                          ],
                        ],
                      )),
                )),
    );
  }
}

class AcceptanceEnvironmentCard extends StatelessWidget {
  const AcceptanceEnvironmentCard(
      {super.key, required this.environment, this.reused = false});
  final AcceptanceEnvironment environment;
  final bool reused;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final label = switch (environment.phase) {
      'pending' => l.acceptanceEnvironmentPending,
      'identifying' => l.acceptanceEnvironmentIdentifying,
      'building' => l.acceptanceEnvironmentBuilding,
      'verifying' => l.acceptanceVerifying,
      'ready' => reused ? l.acceptanceEnvironmentReused : l.acceptanceReady,
      'failed' => l.acceptanceFailed,
      _ => environment.phase,
    };
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (environment.busy)
          SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: acceptanceAccent(context)))
        else
          Icon(environment.phase == 'failed'
              ? Icons.error_outline
              : Icons.layers_outlined),
        const SizedBox(width: 12),
        Expanded(
            child: Text(environment.name,
                style: Theme.of(context).textTheme.titleMedium))
      ]),
      const SizedBox(height: 8),
      Text(label),
      if (environment.busy && environment.progress.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(environment.progress,
            style: Theme.of(context).textTheme.bodySmall),
      ],
      if (environment.busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator()
      ],
      if (environment.description.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(environment.description,
            maxLines: 3, overflow: TextOverflow.ellipsis),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(l.acceptanceDetails),
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(environment.description))
          ],
        ),
      ],
      if (environment.error != null) ...[
        const SizedBox(height: 8),
        SelectableText(environment.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))
      ],
      if (environment.dockerfile.isNotEmpty)
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l.acceptanceEnvironmentRecipe),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(environment.dockerfile,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)))
            ]),
      if (environment.log.isNotEmpty)
        ExpansionTile(
            key: const Key('acceptance-environment-logs'),
            tilePadding: EdgeInsets.zero,
            title: Text(l.acceptanceEnvironmentLogs),
            children: [
              SizedBox(
                  height: 240,
                  child: SingleChildScrollView(
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(environment.log,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)))))
            ]),
    ]));
  }
}
