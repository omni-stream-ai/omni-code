import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../acceptance_models.dart';
import 'acceptance_video_screen.dart';
import 'acceptance_environment_screen.dart';
import 'acceptance_plan_card.dart';
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
    'planning' => l.acceptancePlanGenerating,
    'running' => l.acceptanceRunning,
    'stopping' => l.acceptanceStopping,
    'completed' => l.acceptanceCompleted,
    'failed' => l.acceptanceFailed,
    _ => phase,
  };
}

class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen(
      {super.key,
      this.client,
      this.projectId,
      this.sessionId,
      this.automatic = true});
  static const routeName = '/acceptance';
  final BridgeClient? client;
  final String? projectId, sessionId;
  final bool automatic;
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
  bool creating = false;
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
        runs = (values[1] as List<AcceptanceRun>)
            .where((r) =>
                (widget.projectId == null || r.projectId == widget.projectId) &&
                (widget.sessionId == null || r.sessionId == widget.sessionId))
            .toList();
        projects = (values[2] as List<ProjectSummary>)
            .where((p) => widget.projectId == null || p.id == widget.projectId)
            .toList();
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
    if (busy || creating) return;
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

  Future<void> uninstall() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(context.l10n.uninstall),
                content: Text(context.l10n.acceptanceUninstallHint),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(context.l10n.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(context.l10n.uninstall))
                ]));
    if (confirmed != true || !mounted) return;
    await operation(() async {
      await client.uninstallAcceptancePlugin();
      await refresh();
    });
  }

  Future<void> start() async {
    if (busy || creating || projects.isEmpty) return;
    final input = await showDialog<_RunInput>(
        context: context,
        builder: (_) => _StartDialog(
              client: client,
              projects: projects,
              automatic: widget.automatic,
              sessionScoped: widget.sessionId != null,
            ));
    if (input == null || !mounted || busy || creating) return;
    setState(() {
      creating = true;
      error = null;
    });
    AcceptanceRun? run;
    try {
      run = await client.createAcceptanceRun(
          id: input.id,
          projectId: input.projectId,
          command: input.command,
          size: input.size,
          sessionId: widget.sessionId,
          requirements: input.requirements,
          automatic: widget.automatic);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => creating = false);
    }
    if (run == null || !mounted) return;
    final createdRun = run;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            AcceptanceDetailScreen(run: createdRun, client: client)));
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
        canPop: !creating,
        child: Stack(fit: StackFit.expand, children: [
          Scaffold(
            appBar: AppBar(title: Text(l.acceptanceTitle), actions: [
              if (widget.projectId != null)
                IconButton(
                  tooltip: l.acceptanceEnvironmentTitle,
                  icon: const Icon(Icons.layers_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => AcceptanceEnvironmentScreen(
                              client: client, projectId: widget.projectId!))),
                ),
              IconButton(
                  onPressed: refreshing ? null : refresh,
                  tooltip: l.retry,
                  icon: const Icon(Icons.refresh)),
            ]),
            floatingActionButton: installation?.ready == true
                ? FloatingActionButton.extended(
                    onPressed:
                        busy || creating || projects.isEmpty ? null : start,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(widget.automatic
                        ? l.acceptanceStart
                        : l.acceptanceRemoteDesktop))
                : null,
            body: SafeArea(
                child: RefreshIndicator(
                    onRefresh: refresh,
                    child: _AcceptanceBody(
                      children: [
                        AppCard(
                            padding: AppSpacing.cardPadding,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(Icons.desktop_windows_outlined,
                                        color: _acceptanceAccent(context)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(l.acceptancePlugin,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium)),
                                    if (installation?.ready == true)
                                      PopupMenuButton<String>(
                                        enabled: !busy,
                                        onSelected: (_) => uninstall(),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                              value: 'uninstall',
                                              child: Text(l.uninstall))
                                        ],
                                      ),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(l.acceptancePluginDescription),
                                  if (installation != null) ...[
                                    const SizedBox(height: 12),
                                    _StatusPill(
                                        label: acceptancePhaseLabel(
                                            context, installation!.phase),
                                        error: installation!.phase == 'failed'),
                                    if (installation!.busy)
                                      const LinearProgressIndicator(),
                                    if (installation!.error != null)
                                      SelectableText(installation!.error!),
                                  ],
                                  if (installation?.ready != true)
                                    FilledButton.icon(
                                        onPressed: busy ||
                                                installation?.busy == true
                                            ? null
                                            : () => operation(() async {
                                                  final value = await client
                                                      .installAcceptancePlugin();
                                                  if (mounted) {
                                                    setState(() =>
                                                        installation = value);
                                                  }
                                                }),
                                        icon: const Icon(Icons.download),
                                        label: Text(l.acceptanceInstall)),
                                ])),
                        if (loading)
                          const Center(child: CircularProgressIndicator()),
                        if (error != null)
                          SelectableText('$error',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        if (!loading && runs.isEmpty)
                          Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(l.acceptanceEmpty)),
                        if (runs.isNotEmpty)
                          Text(l.acceptanceHistory,
                              style: Theme.of(context).textTheme.titleMedium),
                        ...runs.map((run) => AppCard(
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute<void>(
                                      builder: (_) => AcceptanceDetailScreen(
                                          run: run, client: client)))
                                  .then((_) {
                                if (mounted) unawaited(refresh());
                              }),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                              projects
                                                      .where((p) =>
                                                          p.id == run.projectId)
                                                      .firstOrNull
                                                      ?.name ??
                                                  run.projectId,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right_rounded,
                                          size: 20),
                                    ]),
                                    const SizedBox(height: 10),
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _StatusPill(
                                              label: run.automation ==
                                                      'awaiting_plan_approval'
                                                  ? l.acceptancePlanWaiting
                                                  : run.running &&
                                                          run.automation ==
                                                              'failed'
                                                      ? l
                                                          .acceptanceAutomationFailed
                                                      : run.passed == null
                                                          ? acceptancePhaseLabel(
                                                              context,
                                                              run.phase)
                                                          : run.passed!
                                                              ? l.acceptancePass
                                                              : l
                                                                  .acceptanceFail,
                                              error: run.phase == 'failed' ||
                                                  run.passed == false),
                                          Text(_runDate(context, run.createdAt),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        ]),
                                    if (run.automationProgress.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(run.automationProgress,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 13)),
                                    ],
                                  ]),
                            )),
                      ],
                    ))),
          ),
          if (creating)
            Positioned.fill(
                child: ColoredBox(
              color: Colors.black26,
              child: ModalBarrier(
                dismissible: false,
                color: Colors.transparent,
                semanticsLabel: l.acceptanceCreating,
              ),
            )),
          if (creating)
            Center(
                child: Card(
              key: const Key('acceptance-creation-loading'),
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: 16),
                  Text(l.acceptanceCreating,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l.acceptanceCreatingHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            )),
        ]));
  }
}

class _RunInput {
  _RunInput(this.projectId, this.command, this.size, this.requirements);
  final String id = const Uuid().v4();
  final String projectId, command, size;
  final String? requirements;
}

class _StartDialog extends StatefulWidget {
  const _StartDialog(
      {required this.client,
      required this.projects,
      required this.automatic,
      required this.sessionScoped});
  final List<ProjectSummary> projects;
  final BridgeClient client;
  final bool automatic, sessionScoped;
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  final command = TextEditingController(text: '');
  final requirements = TextEditingController();
  late String projectId = widget.projects.first.id;
  String size = 'pc';
  @override
  void dispose() {
    command.dispose();
    requirements.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.automatic
            ? context.l10n.acceptanceStart
            : context.l10n.acceptanceRemoteDesktop),
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
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('acceptance-project-environment'),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => AcceptanceEnvironmentScreen(
                                client: widget.client, projectId: projectId))),
                    icon: const Icon(Icons.layers_outlined, size: 18),
                    label: Text(context.l10n.acceptanceEnvironmentTitle),
                  )),
              if (widget.automatic) ...[
                const SizedBox(height: 12),
                if (widget.sessionScoped)
                  Text(context.l10n.acceptanceSessionScopeHint),
                TextField(
                  key: const Key('acceptance-requirements-input'),
                  controller: requirements,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: context.l10n.acceptanceRequirementsInput,
                    hintText: context.l10n.acceptanceRequirementsHint,
                  ),
                ),
              ],
              TextField(
                  controller: command,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                      labelText: context.l10n.acceptanceCommand,
                      hintText: context.l10n.acceptanceCommandAuto),
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
              onPressed: () => Navigator.pop(
                  context,
                  _RunInput(
                    projectId,
                    command.text.trim(),
                    size,
                    requirements.text.trim().isEmpty
                        ? null
                        : requirements.text.trim(),
                  )),
              child: Text(widget.automatic
                  ? context.l10n.acceptanceStart
                  : context.l10n.acceptanceRemoteDesktop))
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

class _AcceptanceDetailScreenState extends State<AcceptanceDetailScreen>
    with WidgetsBindingObserver {
  late AcceptanceRun run = widget.run;
  Uint8List? preview;
  Timer? timer;
  Object? error;
  bool busy = false, refreshing = false;
  int updateGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!run.terminal &&
          !busy &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    final generation = updateGeneration;
    try {
      final value = await widget.client.getAcceptanceRun(run.id);
      if (!mounted || generation != updateGeneration) return;
      setState(() {
        run = value;
        error = null;
      });
      if (value.running) {
        final image = await widget.client.acceptancePreview(run.id);
        if (mounted) setState(() => preview = image);
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
    final id = run.id;
    Future<Uri> openDesktop() async {
      await widget.client.setAcceptanceControl(id, acquire: true);
      return widget.client.acceptanceDesktopUrl(id);
    }

    try {
      final uri = await openDesktop();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AcceptanceDesktopScreen(
                url: uri,
                title: context.l10n.acceptanceTakeControl,
                onReload: openDesktop,
                onClose: () =>
                    widget.client.setAcceptanceControl(id, acquire: false),
              )));
    } catch (_) {
      await widget.client.setAcceptanceControl(id, acquire: false);
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
    if (artifact.contentType == 'video/mp4') {
      if (kIsWeb) {
        final uri =
            await widget.client.acceptanceEvidenceUrl(run.id, artifact.name);
        if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
          throw StateError('Could not open recording');
        }
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AcceptanceVideoScreen(
                client: widget.client, runId: run.id, name: artifact.name)));
      }
      return;
    }
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final recording =
        run.artifacts.where((a) => a.contentType == 'video/mp4').firstOrNull;
    final evidence =
        run.artifacts.where((a) => a.contentType != 'video/mp4').toList();
    final canExport = run.running &&
        (!run.automatic ||
            const ['awaiting_confirmation', 'failed', 'completed']
                .contains(run.automation));
    final passed = run.checklist.where((c) => c.status == 'passed').length;
    final failed = run.checklist
        .where((c) => c.status == 'failed' || c.status == 'blocked')
        .length;
    final automationFailedWhileRunning =
        run.running && run.automation == 'failed';
    final heading = run.passed != null
        ? (run.passed! ? l.acceptancePass : l.acceptanceFail)
        : automationFailedWhileRunning
            ? l.acceptanceAutomationFailed
            : run.autoVerdict != null && !run.terminal
                ? l.acceptanceAwaitingReview
                : run.automation == 'awaiting_plan_approval'
                    ? l.acceptancePlanWaiting
                    : acceptancePhaseLabel(context, run.phase);
    return Scaffold(
      appBar: AppBar(title: Text(l.acceptanceTitle), actions: [
        IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: l.retry,
            icon: const Icon(Icons.refresh_rounded)),
        if (!run.terminal)
          PopupMenuButton<String>(
            onSelected: (_) => operation(() async {
              await widget.client.stopAcceptanceRun(run.id);
            }),
            enabled: !busy,
            itemBuilder: (_) =>
                [PopupMenuItem(value: 'stop', child: Text(l.acceptanceStop))],
          ),
      ]),
      body: SafeArea(
          child: RefreshIndicator(
        onRefresh: refresh,
        child: _AcceptanceBody(children: [
          AppCard(
            color: colors.surfaceContainerHighest,
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                    automationFailedWhileRunning
                        ? Icons.warning_amber_rounded
                        : run.passed == false || run.phase == 'failed'
                            ? Icons.error_outline_rounded
                            : run.passed == true
                                ? Icons.task_alt_rounded
                                : Icons.fact_check_outlined,
                    color: colors.onSurface,
                    size: 28),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(heading,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700))),
              ]),
              if (run.automationProgress.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(run.automationProgress,
                    style: TextStyle(color: colors.onSurface)),
              ],
              if (run.checklist.isNotEmpty) ...[
                const SizedBox(height: 18),
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (passed + failed) / run.checklist.length,
                      minHeight: 6,
                      color: _acceptanceAccent(context),
                      backgroundColor: colors.onSurface.withValues(alpha: .12),
                    )),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _StatusPill(
                      label:
                          '$passed / ${run.checklist.length} · ${l.acceptanceCheckPassed}'),
                  if (failed > 0)
                    _StatusPill(
                        label: '$failed · ${l.acceptanceCheckFailed}',
                        error: true),
                ]),
              ],
              if (run.autoVerdict != null) ...[
                const SizedBox(height: 14),
                Text(
                    run.autoVerdict!.passed
                        ? l.acceptanceSuggestedPass
                        : l.acceptanceSuggestedFail,
                    style: TextStyle(
                        color: colors.onSurface, fontWeight: FontWeight.w600)),
              ],
              if (run.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                SelectableText(run.notes!),
              ],
            ]),
          ),
          if (busy) const LinearProgressIndicator(),
          if (run.testPlan != null)
            AcceptancePlanCard(
                key: ValueKey(run.id),
                run: run,
                client: widget.client,
                onUpdated: (value) {
                  if (mounted) {
                    setState(() {
                      updateGeneration++;
                      run = value;
                    });
                  }
                }),
          if (run.environment != null && run.phase != 'planning')
            AcceptanceEnvironmentCard(
                environment: run.environment!, reused: run.environmentReused),
          if (run.requirementBrief != null)
            AppCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                key: const Key('acceptance-requirement-brief'),
                initiallyExpanded: run.testPlan == null,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.assignment_outlined),
                title: Text(l.acceptanceRequirementsTitle),
                subtitle: Text(l.acceptanceRequirementSources(
                    run.requirementBrief!.sourceMessageCount)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, requirement)
                      in run.requirementBrief!.requirements.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SelectableText(
                          '${index + 1}. ${requirement.description}'),
                    ),
                  if (run.requirementBrief!.notes.isNotEmpty)
                    SelectableText(run.requirementBrief!.notes,
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if ((run.running ||
                  (run.phase == 'planning' && run.testPlan == null)) &&
              run.automation != 'awaiting_confirmation' &&
              run.automation != 'failed')
            AppCard(
                color: colors.primaryContainer,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.onPrimaryContainer)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(
                                run.automationProgress.isEmpty
                                    ? l.acceptanceStarting
                                    : run.automationProgress,
                                style: TextStyle(
                                    color: colors.onPrimaryContainer,
                                    fontWeight: FontWeight.w600))),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              minHeight: 4,
                              color: colors.onPrimaryContainer,
                              backgroundColor: colors.onPrimaryContainer
                                  .withValues(alpha: .18))),
                    ])),
          if (automationFailedWhileRunning && run.automationError != null)
            AppCard(
                color: colors.tertiaryContainer,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.acceptanceAutomationFailedHint,
                          style: TextStyle(color: colors.onTertiaryContainer)),
                      const SizedBox(height: 8),
                      SelectableText(run.automationError!,
                          style: TextStyle(color: colors.onTertiaryContainer)),
                    ]))
          else if (error != null ||
              run.error != null ||
              run.automationError != null)
            AppCard(
                color: colors.errorContainer,
                child: SelectableText(
                    error?.toString() ?? run.error ?? run.automationError!,
                    style: TextStyle(color: colors.onErrorContainer))),
          if (run.phase == 'planning' &&
              run.testPlan == null &&
              run.automation == 'failed')
            FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => operation(() async {
                          await widget.client.retryAcceptanceTestPlan(run.id);
                        }),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l.acceptancePlanRetry)),
          if (run.running)
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(l.acceptanceDesktopPreview,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (preview != null)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: ColoredBox(
                                color: colors.surfaceContainerHighest,
                                child: Image.memory(preview!,
                                    gaplessPlayback: true,
                                    fit: BoxFit.contain))))
                  else
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(l.acceptancePreviewHint,
                            style: TextStyle(color: colors.onSurfaceVariant))),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                      onPressed: busy ? null : () => operation(desktop),
                      icon: const Icon(Icons.open_in_full_rounded),
                      label: Text(l.acceptanceTakeControl)),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                    TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => operation(() async {
                                  await widget.client
                                      .captureAcceptanceScreenshot(run.id);
                                }),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(l.acceptanceCapture)),
                    if (run.controller != null)
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => operation(() async {
                                    await widget.client.setAcceptanceControl(
                                        run.id,
                                        acquire: false);
                                  }),
                          child: Text(l.acceptanceReleaseControl)),
                  ]),
                ])),
          if (run.checklist.isNotEmpty)
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(l.acceptanceChecks, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...run.checklist.map((check) => _CheckRow(check: check)),
                ])),
          if (run.running)
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(l.acceptanceReview, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(l.acceptanceReviewHint,
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                        onPressed: busy ? null : () => finish(true),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l.acceptancePass)),
                    OutlinedButton.icon(
                        onPressed: busy ? null : () => finish(false),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(l.acceptanceFail)),
                  ]),
                ])),
          if (run.phase != 'planning' || run.artifacts.isNotEmpty)
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(l.acceptanceEvidence,
                            style: theme.textTheme.titleMedium)),
                    _StatusPill(label: run.artifacts.length.toString())
                  ]),
                  const SizedBox(height: 12),
                  if (recording != null) ...[
                    Row(children: [
                      Expanded(
                          child: FilledButton.tonalIcon(
                              onPressed: busy
                                  ? null
                                  : () =>
                                      operation(() => openArtifact(recording)),
                              icon:
                                  const Icon(Icons.play_circle_outline_rounded),
                              label: Text(l.acceptanceReplay))),
                      IconButton(
                          tooltip: l.acceptanceDownload,
                          icon: const Icon(Icons.download_outlined),
                          onPressed: busy
                              ? null
                              : () => operation(() async {
                                    final uri = await widget.client
                                        .acceptanceEvidenceUrl(
                                            run.id, recording.name,
                                            download: true);
                                    if (!await launchUrl(uri,
                                        mode: LaunchMode.externalApplication)) {
                                      throw StateError(
                                          'Could not download recording');
                                    }
                                  })),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        '${l.acceptanceRecording} · ${_artifactSize(recording.bytes)}',
                        style: theme.textTheme.bodySmall),
                  ] else if (run.running) ...[
                    Text(l.acceptanceRecordingPending,
                        style: TextStyle(color: colors.onSurfaceVariant)),
                    if (canExport)
                      TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => operation(() async {
                                    await widget.client
                                        .saveAcceptanceEvidence(run.id);
                                  }),
                          icon: const Icon(Icons.video_file_outlined),
                          label: Text(l.acceptanceExportEvidence)),
                  ],
                  if (run.artifacts.isEmpty && !run.running)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(l.acceptanceNoEvidence,
                            style: TextStyle(color: colors.onSurfaceVariant))),
                  ...evidence.asMap().entries.map((entry) {
                    final artifact = entry.value;
                    final isImage = artifact.contentType.startsWith('image/');
                    final isVideo = artifact.contentType.startsWith('video/');
                    final label = isImage
                        ? l.acceptanceScreenshot
                        : isVideo
                            ? l.acceptanceRecording
                            : l.acceptanceReport;
                    final size = artifact.bytes < 1024 * 1024
                        ? '${(artifact.bytes / 1024).toStringAsFixed(1)} KB'
                        : '${(artifact.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          isImage
                              ? Icons.image_outlined
                              : isVideo
                                  ? Icons.videocam_outlined
                                  : Icons.description_outlined,
                          color: _acceptanceAccent(context)),
                      title: Text(artifact.name == 'initial.png'
                          ? l.acceptanceInitialFrame
                          : run.checklist
                                  .where(
                                      (c) => c.evidence.contains(artifact.name))
                                  .firstOrNull
                                  ?.title ??
                              '$label ${entry.key + 1}'),
                      subtitle: Text(size),
                      trailing: IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: l.acceptanceDownload,
                          onPressed: busy
                              ? null
                              : () => operation(() async {
                                    final uri = await widget.client
                                        .acceptanceEvidenceUrl(
                                            run.id, artifact.name,
                                            download: true);
                                    if (!await launchUrl(uri,
                                        mode: LaunchMode.externalApplication,
                                        webOnlyWindowName:
                                            kIsWeb ? '_self' : null)) {
                                      throw StateError(
                                          'Could not open evidence');
                                    }
                                  })),
                      onTap: busy
                          ? null
                          : () => operation(() => openArtifact(artifact)),
                    );
                  }),
                ])),
          AppCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.code_rounded),
                title: Text(l.acceptanceDetails),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_runDate(context, run.createdAt),
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  SelectableText(run.revision,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  SelectableText(run.command,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace')),
                ],
              )),
        ]),
      )),
    );
  }
}

class _AcceptanceBody extends StatelessWidget {
  const _AcceptanceBody({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final inset = ((constraints.maxWidth - AppSpacing.contentMaxWidth) / 2)
            .clamp(16.0, double.infinity);
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 100),
          itemCount: children.length,
          separatorBuilder: (_, index) => const SizedBox(height: 16),
          itemBuilder: (_, index) => children[index],
        );
      });
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.error = false});
  final String label;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.surface,
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: error ? colors.onErrorContainer : colors.onSurface)),
    );
  }
}

Color _acceptanceAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF80CBC4)
        : const Color(0xFF176B60);

String _runDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatShortDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _artifactSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});
  final AcceptanceCheck check;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (check.status) {
      'passed' => (
          Icons.check_circle_outline_rounded,
          l.acceptanceCheckPassed,
          _acceptanceAccent(context)
        ),
      'failed' => (
          Icons.cancel_outlined,
          l.acceptanceCheckFailed,
          colors.error
        ),
      'blocked' => (
          Icons.pause_circle_outline,
          l.acceptanceCheckBlocked,
          colors.error
        ),
      'running' => (
          Icons.timelapse_rounded,
          l.acceptanceCheckRunning,
          _acceptanceAccent(context)
        ),
      _ => (
          Icons.radio_button_unchecked,
          l.acceptanceCheckPending,
          colors.onSurfaceVariant
        ),
    };
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(icon, color: color),
      title: Text(check.title,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(label, style: TextStyle(color: color, fontSize: 12)),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (check.description.isNotEmpty) Text(check.description),
        if (check.assertion.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(check.assertion)),
        if (check.notes.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(check.notes)),
      ],
    );
  }
}

class AcceptanceDesktopScreen extends StatefulWidget {
  const AcceptanceDesktopScreen({
    super.key,
    required this.url,
    required this.title,
    required this.onReload,
    required this.onClose,
  });
  final Uri url;
  final String title;
  final Future<Uri> Function() onReload;
  final Future<void> Function() onClose;

  @override
  State<AcceptanceDesktopScreen> createState() =>
      _AcceptanceDesktopScreenState();
}

class _AcceptanceDesktopScreenState extends State<AcceptanceDesktopScreen> {
  static const _platform = MethodChannel('omni_code/app_update');
  late final WebViewController controller;
  bool loading = true;
  String? loadError;
  Uri? mainFrameUrl;
  bool closing = false;
  bool changingOrientation = false;
  bool orientationOverridden = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          mainFrameUrl = Uri.tryParse(url);
          if (mounted && loadError == null) setState(() => loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
        onHttpError: (error) {
          final uri = error.request?.uri ?? error.response?.uri;
          if (uri == null ||
              (uri.scheme == mainFrameUrl?.scheme &&
                  uri.authority == mainFrameUrl?.authority &&
                  uri.path == mainFrameUrl?.path)) {
            showLoadError('HTTP ${error.response?.statusCode ?? "error"}');
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && loadError == null) {
            showLoadError(error.description);
          }
        },
      ));
    loadDesktop(widget.url);
  }

  Future<void> toggleOrientation() async {
    if (changingOrientation || closing) return;
    final landscape = MediaQuery.orientationOf(context) == Orientation.portrait;
    setState(() => changingOrientation = true);
    orientationOverridden = true;
    try {
      await SystemChrome.setPreferredOrientations(landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.acceptanceOrientationFailed)));
      }
    } finally {
      if (mounted) setState(() => changingOrientation = false);
    }
  }

  Future<void> restoreOrientation() async {
    if (!orientationOverridden) return;
    orientationOverridden = false;
    await SystemChrome.setPreferredOrientations([]);
  }

  @override
  void dispose() {
    unawaited(restoreOrientation());
    super.dispose();
  }

  void showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      loading = false;
      loadError =
          message.replaceAll(RegExp(r'ticket=[^\s&]+'), 'ticket=REDACTED');
    });
  }

  Future<void> loadDesktop([Uri? url]) async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      // Each retry exchanges a fresh single-use ticket for a scoped cookie.
      final target = url ?? await widget.onReload();
      if (!mounted) return;
      mainFrameUrl = target;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _configureLocalBridgeProxy(target);
      }
      // The gateway issues a fresh single-use ticket and session cookie for
      // every open/retry. Remove a previous desktop cookie before following
      // the ticket so WebView cannot send an old control generation first.
      await WebViewCookieManager().clearCookies();
      await controller.loadRequest(target);
    } catch (error) {
      showLoadError(error.toString());
    }
  }

  Future<void> _configureLocalBridgeProxy(Uri target) async {
    if (!const {'10.0.2.2', 'localhost', '127.0.0.1'}.contains(target.host)) {
      return;
    }
    await _platform.invokeMethod<bool>(
        'configureWebViewProxy', <String, Object>{'host': target.host});
  }

  Future<void> close() async {
    if (closing) return;
    closing = true;
    try {
      await widget.onClose();
    } finally {
      await restoreOrientation();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _platform.invokeMethod<bool>('clearWebViewProxy');
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final canRotate = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (canRotate)
              IconButton(
                  onPressed:
                      changingOrientation || closing ? null : toggleOrientation,
                  tooltip: landscape
                      ? l.acceptanceSwitchPortrait
                      : l.acceptanceSwitchLandscape,
                  icon: Icon(landscape
                      ? Icons.stay_current_portrait
                      : Icons.stay_current_landscape)),
            IconButton(
                onPressed: close,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close)),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(children: [
            Offstage(
                offstage: loadError != null,
                child: WebViewWidget(controller: controller)),
            if (loading) const LinearProgressIndicator(),
            if (loadError != null)
              Center(
                  child: Padding(
                padding: AppSpacing.screenPadding,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 16),
                  Text(l.acceptanceOpenFailed,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: loading ? null : () => loadDesktop(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l.retry)),
                ]),
              )),
          ]),
        ),
      ),
    );
  }
}
