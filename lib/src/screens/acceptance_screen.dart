import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_card.dart';

String acceptancePhaseLabel(BuildContext context, String phase) {
  final l = context.l10n;
  return switch (phase) {
    'not_installed' => l.acceptanceNotInstalled,
    'checking' => l.acceptanceChecking,
    'preparing' => l.acceptancePreparing,
    'verifying' => l.acceptanceVerifying,
    'ready' => l.acceptanceReady,
    'starting' => l.acceptanceStarting,
    'running' => l.acceptanceRunning,
    'stopping' => l.acceptanceStopping,
    'completed' => l.acceptanceCompleted,
    'failed' => l.acceptanceFailed,
    _ => phase,
  };
}

class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen({super.key, this.client});
  static const routeName = '/acceptance';
  final BridgeClient? client;
  @override
  State<AcceptanceScreen> createState() => _AcceptanceScreenState();
}

class _AcceptanceScreenState extends State<AcceptanceScreen> {
  BridgeClient get client => widget.client ?? bridgeClient;
  AcceptanceInstallation? installation;
  List<AcceptanceRun> runs = [];
  List<ProjectSummary> projects = [];
  Object? error;
  bool loading = true, refreshing = false, busy = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (installation?.busy == true || runs.any((r) => !r.terminal)) {
        unawaited(refresh());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final values = await Future.wait([
        client.getAcceptanceInstallation(),
        client.listAcceptanceRuns(),
        client.listProjects(),
      ]);
      if (!mounted) return;
      setState(() {
        installation = values[0] as AcceptanceInstallation;
        runs = values[1] as List<AcceptanceRun>;
        projects = values[2] as List<ProjectSummary>;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      refreshing = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> operation(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start() async {
    final input = await showDialog<_RunInput>(
        context: context, builder: (_) => _StartDialog(projects: projects));
    if (input == null) return;
    await operation(() async {
      final run = await client.createAcceptanceRun(
          id: input.id,
          projectId: input.projectId,
          command: input.command,
          size: input.size);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AcceptanceDetailScreen(run: run, client: client)));
      await refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.acceptanceTitle), actions: [
        IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: l.retry,
            icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: installation?.ready == true
          ? FloatingActionButton.extended(
              onPressed: busy || projects.isEmpty ? null : start,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.acceptanceStart))
          : null,
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: AppSpacing.screenPadding,
                children: [
                  AppCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.acceptancePlugin,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(l.acceptancePluginDescription),
                            if (installation != null) ...[
                              const SizedBox(height: 12),
                              Text(acceptancePhaseLabel(
                                  context, installation!.phase)),
                              if (installation!.busy)
                                const LinearProgressIndicator(),
                              if (installation!.error != null)
                                SelectableText(installation!.error!),
                            ],
                            if (installation?.ready != true)
                              FilledButton.icon(
                                  onPressed: busy || installation?.busy == true
                                      ? null
                                      : () => operation(() async {
                                            final value = await client
                                                .installAcceptancePlugin();
                                            if (mounted) {
                                              setState(
                                                  () => installation = value);
                                            }
                                          }),
                                  icon: const Icon(Icons.download),
                                  label: Text(l.acceptanceInstall)),
                          ])),
                  const SizedBox(height: 16),
                  if (loading) const Center(child: CircularProgressIndicator()),
                  if (error != null)
                    SelectableText('$error',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (!loading && runs.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.acceptanceEmpty)),
                  ...runs.map((run) => ListTile(
                        title: Text(projects
                                .where((p) => p.id == run.projectId)
                                .firstOrNull
                                ?.name ??
                            run.projectId),
                        subtitle: Text([
                          acceptancePhaseLabel(context, run.phase),
                          run.revision
                              .substring(0, run.revision.length.clamp(0, 8)),
                          run.createdAt.toLocal().toString().split('.').first
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(
                                builder: (_) => AcceptanceDetailScreen(
                                    run: run, client: client)))
                            .then((_) {
                          if (mounted) unawaited(refresh());
                        }),
                      )),
                  const SizedBox(height: 88),
                ],
              ))),
    );
  }
}

class _RunInput {
  _RunInput(this.projectId, this.command, this.size);
  final String id = const Uuid().v4();
  final String projectId, command, size;
}

class _StartDialog extends StatefulWidget {
  const _StartDialog({required this.projects});
  final List<ProjectSummary> projects;
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  final command = TextEditingController(
      text: 'chromium --no-sandbox --new-window about:blank');
  late String projectId = widget.projects.first.id;
  String size = 'pc';
  @override
  void dispose() {
    command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.acceptanceStart),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: InputDecoration(
                      labelText: context.l10n.acceptanceProject),
                  items: widget.projects
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => projectId = v);
                  }),
              TextField(
                  controller: command,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                      labelText: context.l10n.acceptanceCommand),
                  onChanged: (_) => setState(() {})),
              DropdownButtonFormField<String>(
                  initialValue: size,
                  decoration:
                      InputDecoration(labelText: context.l10n.acceptanceSize),
                  items: const ['mobile', 'tablet', 'laptop', 'pc']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => size = v);
                  }),
              const SizedBox(height: 12),
              Text(context.l10n.acceptanceCommitHint),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: command.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context, _RunInput(projectId, command.text.trim(), size)),
              child: Text(context.l10n.acceptanceStart))
        ],
      );
}

class AcceptanceDetailScreen extends StatefulWidget {
  const AcceptanceDetailScreen(
      {super.key, required this.run, required this.client});
  final AcceptanceRun run;
  final BridgeClient client;
  @override
  State<AcceptanceDetailScreen> createState() => _AcceptanceDetailScreenState();
}

class _AcceptanceDetailScreenState extends State<AcceptanceDetailScreen> {
  late AcceptanceRun run = widget.run;
  Uint8List? preview;
  Timer? timer;
  Object? error;
  bool busy = false, refreshing = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!run.terminal && !busy && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) { unawaited(refresh()); }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final value = await widget.client.getAcceptanceRun(run.id);
      final image = value.running ? await widget.client.acceptancePreview(run.id) : null;
      if (mounted) {
        setState(() {
          run = value;
          if (image != null) preview = image;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      refreshing = false;
    }
  }

  Future<void> operation(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> desktop() async {
    await widget.client.setAcceptanceControl(run.id, acquire: true);
    try {
      final uri = await widget.client.acceptanceDesktopUrl(run.id);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(mounted
            ? context.l10n.acceptanceOpenFailed
            : 'Cannot open desktop');
      }
    } catch (_) {
      await widget.client.setAcceptanceControl(run.id, acquire: false);
      rethrow;
    }
  }

  Future<void> finish(bool passed) async {
    final notes = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(passed
                    ? context.l10n.acceptancePass
                    : context.l10n.acceptanceFail),
                content: TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 16000,
                    decoration: InputDecoration(
                        labelText: context.l10n.acceptanceNotes)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, notes.text),
                      child: Text(passed
                          ? context.l10n.acceptancePass
                          : context.l10n.acceptanceFail))
                ]));
    // Dispose after the closing dialog route has finished using its controller.
    Future<void>.delayed(const Duration(seconds: 1), notes.dispose);
    if (value != null) {
      await operation(() async {
        await widget.client
            .stopAcceptanceRun(run.id, passed: passed, notes: value);
      });
    }
  }

  Future<void> openArtifact(AcceptanceArtifact artifact) async {
    final bytes = await widget.client.acceptanceArtifact(run.id, artifact.name);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: artifact.contentType.startsWith('image/')
                  ? InteractiveViewer(child: Image.memory(bytes))
                  : SingleChildScrollView(
                      child: SelectableText(utf8.decode(bytes))),
            )));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
        appBar: AppBar(title: Text(l.acceptanceTitle), actions: [
          IconButton(
              onPressed: refreshing ? null : refresh,
              tooltip: l.retry,
              icon: const Icon(Icons.refresh)),
        ]),
        body: SafeArea(
            child: ListView(padding: AppSpacing.screenPadding, children: [
          Text(acceptancePhaseLabel(context, run.phase),
              style: Theme.of(context).textTheme.titleLarge),
          SelectableText(run.revision),
          Text(run.command),
          if (preview != null) SizedBox(height: 360, child: InteractiveViewer(
            child: Image.memory(preview!, gaplessPlayback: true, fit: BoxFit.contain))),
          if (busy) const LinearProgressIndicator(),
          if (error != null || run.error != null)
            SelectableText(error?.toString() ?? run.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          if (run.running)
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: busy ? null : () => operation(desktop),
                  icon: const Icon(Icons.desktop_windows),
                  label: Text(l.acceptanceTakeControl)),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => operation(() async {
                            await widget.client
                                .setAcceptanceControl(run.id, acquire: false);
                          }),
                  child: Text(l.acceptanceReleaseControl)),
              OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => operation(() async {
                            await widget.client
                                .captureAcceptanceScreenshot(run.id);
                          }),
                  icon: const Icon(Icons.screenshot),
                  label: Text(l.acceptanceCapture)),
              FilledButton(
                  onPressed: busy ? null : () => finish(true),
                  child: Text(l.acceptancePass)),
              OutlinedButton(
                  onPressed: busy ? null : () => finish(false),
                  child: Text(l.acceptanceFail)),
            ]),
          if (run.phase != 'completed')
            TextButton(
                onPressed: busy
                    ? null
                    : () => operation(() async {
                          await widget.client.stopAcceptanceRun(run.id);
                        }),
                child: Text(l.acceptanceStop)),
          if (run.passed != null)
            Text(run.passed! ? l.acceptancePass : l.acceptanceFail),
          if (run.notes?.isNotEmpty == true) SelectableText(run.notes!),
          const SizedBox(height: 16),
          Text(l.acceptanceEvidence,
              style: Theme.of(context).textTheme.titleMedium),
          ...run.artifacts.map((artifact) => ListTile(
              title: Text(artifact.name),
              subtitle: Text(artifact.bytes.toString()),
              onTap: busy || artifact.contentType == 'video/mp4'
                  ? null
                  : () => operation(() => openArtifact(artifact)))),
        ])));
  }
}
