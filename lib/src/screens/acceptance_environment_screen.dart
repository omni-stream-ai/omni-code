import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../widgets/app_card.dart';

const _dockerfileTemplate =
    'FROM {{BASE_IMAGE}}\nUSER root\nRUN apt-get update && apt-get install -y --no-install-recommends git unzip xz-utils && rm -rf /var/lib/apt/lists/*\nUSER x11box\nWORKDIR /workspace\n';

class AcceptanceEnvironmentScreen extends StatefulWidget {
  const AcceptanceEnvironmentScreen(
      {super.key, required this.client, required this.projectId});
  final BridgeClient client;
  final String projectId;
  @override
  State<AcceptanceEnvironmentScreen> createState() =>
      _AcceptanceEnvironmentScreenState();
}

class _AcceptanceEnvironmentScreenState
    extends State<AcceptanceEnvironmentScreen> {
  AcceptanceEnvironmentSettings? settings;
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
    dockerfile.dispose();
    image.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final value =
          await widget.client.getAcceptanceEnvironment(widget.projectId);
      if (!mounted) return;
      setState(() {
        settings = value;
        mode = value.config.mode;
        dockerfile.text = value.config.dockerfile.isEmpty
            ? _dockerfileTemplate
            : value.config.dockerfile;
        image.text = value.config.image;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
              dockerfile: mode == 'dockerfile' ? dockerfile.text : '',
              image: mode == 'image' ? image.text.trim() : ''),
          rebuild: rebuild);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.acceptanceEnvironmentSaved)));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
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
                          Text(l.acceptanceEnvironmentHint),
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
                            FilledButton.icon(
                                key: const Key('acceptance-environment-save'),
                                onPressed: saving ? null : save,
                                icon: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.check),
                                label: Text(l.acceptanceEnvironmentSave)),
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
