import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../project_runtime_models.dart';
import '../widgets/app_card.dart';
import '../widgets/project_runtime_target_dialog.dart';
import 'acceptance_environment_screen.dart';
import 'acceptance_screen.dart';

class ProjectRuntimeScreen extends StatefulWidget {
  const ProjectRuntimeScreen(
      {super.key, required this.client, required this.projectId});
  final BridgeClient client;
  final String projectId;

  @override
  State<ProjectRuntimeScreen> createState() => _ProjectRuntimeScreenState();
}

class _ProjectRuntimeScreenState extends State<ProjectRuntimeScreen>
    with WidgetsBindingObserver {
  ProjectRuntimeOverview? overview;
  Object? error;
  Object? configurationError;
  ({int total, int ready, String reasoning})? configurationResult;
  bool configuring = false;
  bool refreshing = false, appActive = true;
  final busy = <String>{};
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (appActive && busy.isEmpty) unawaited(load());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (appActive) unawaited(load());
  }

  Future<void> load() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final value = await widget.client.getProjectRuntime(widget.projectId);
      if (mounted) {
        setState(() {
          overview = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      refreshing = false;
    }
  }

  Future<void> act(String directory, Future<void> Function() action) async {
    setState(() {
      busy.add(directory);
      error = null;
    });
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy.remove(directory));
    }
  }

  Future<void> configure() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AcceptanceEnvironmentScreen(
            client: widget.client,
            projectId: widget.projectId,
            generalPurpose: true)));
    if (mounted) await load();
  }

  Future<void> editTarget({String? directory, bool renameOnly = false}) async {
    final target = overview?.targets
        .where((target) => target.directory == directory)
        .firstOrNull;
    if (directory != null && target == null) return;
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProjectRuntimeTargetDialog(
            client: widget.client,
            projectId: widget.projectId,
            target: target,
            name: directory == null
                ? ''
                : overview?.names[directory] ?? directory,
            renameOnly: renameOnly));
    if (mounted && saved == true) {
      setState(() {
        configurationResult = null;
        configurationError = null;
      });
      await load();
    }
  }

  Future<void> deleteTarget(String directory) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(l.projectRuntimeDeleteTargetConfirm(
                  overview?.names[directory] ?? directory)),
              content: Text(l.projectRuntimeDeleteTargetHint),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.cancel)),
                FilledButton(
                    key: const Key('runtime-target-confirm-delete'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l.projectRuntimeDeleteTarget)),
              ],
            ));
    if (confirmed == true && mounted) {
      setState(() {
        configurationResult = null;
        configurationError = null;
      });
      await act(
          directory,
          () => widget.client
              .deleteProjectRuntimeTarget(widget.projectId, directory));
    }
  }

  Future<void> autoConfigure() async {
    if (configuring || busy.isNotEmpty) return;
    setState(() {
      configuring = true;
      configurationError = null;
      configurationResult = null;
    });
    try {
      final settings = await widget.client
          .getAcceptanceEnvironment(widget.projectId, generalPurpose: true);
      if (!mounted) return;
      final detection = await widget.client.detectAcceptanceBuild(
          widget.projectId,
          agent: true,
          generalPurpose: true,
          allTargets: true,
          current:
              settings.config.build ?? const AcceptanceBuildConfiguration(),
          currentTargets: settings.config.buildTargets);
      if (!mounted) return;
      if (detection.targets.isEmpty) {
        throw Exception(detection.reasoning.isEmpty
            ? context.l10n.projectRuntimeEmpty
            : detection.reasoning);
      }
      await widget.client.saveAcceptanceEnvironment(
          widget.projectId,
          AcceptanceEnvironmentConfig(
              mode: settings.config.mode,
              dockerfile: settings.config.dockerfile,
              image: settings.config.image,
              build: detection.targets.first.configuration,
              buildTargets: detection.targets,
              buildReasoning: detection.reasoning),
          generalPurpose: true);
      if (!mounted) return;
      setState(() => configurationResult = (
            total: detection.targets.length,
            reasoning: detection.reasoning,
            ready: detection.targets
                .where((target) =>
                    (target.configuration.values['start_command'] ?? '')
                        .trim()
                        .isNotEmpty)
                .length
          ));
      await load();
    } catch (e) {
      if (mounted) setState(() => configurationError = e);
    } finally {
      if (mounted) setState(() => configuring = false);
    }
  }

  Future<void> showLogs(String directory) async {
    await act(directory, () async {
      final log = await widget.client
          .getProjectRuntimeLogs(widget.projectId, directory);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(context.l10n.projectRuntimeLogs),
                content: SizedBox(
                    width: 720,
                    child: SingleChildScrollView(
                        child: SelectableText(log.isEmpty
                            ? context.l10n.projectRuntimeNoLogs
                            : log))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.close))
                ],
              ));
    });
  }

  Future<void> openDesktop(String directory, String id) =>
      act(directory, () async {
        final run = await widget.client.getAcceptanceRun(id);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                AcceptanceDetailScreen(run: run, client: widget.client)));
      });

  String phaseLabel(ProjectRuntime? runtime) {
    final l = context.l10n;
    return switch (runtime?.phase) {
      'starting' => l.projectRuntimeStarting,
      'running' => l.projectRuntimeRunning,
      'stopping' => l.projectRuntimeStopping,
      'failed' => l.projectRuntimeFailed,
      'unknown' => l.projectRuntimeUnknown,
      _ => l.projectRuntimeStopped,
    };
  }

  Widget targetCard(String directory) {
    final l = context.l10n;
    final target = overview!.targets
        .where((target) => target.directory == directory)
        .firstOrNull;
    final runtime = overview!.runtimes
        .where((runtime) => runtime.directory == directory)
        .firstOrNull;
    final location = overview!.locations[directory] ?? 'host';
    final name = overview!.names[directory] ?? directory;
    final active = runtime?.active == true;
    final occupied = runtime?.occupied == true;
    final updating = busy.contains(directory);
    final missingCommand =
        (target?.configuration.values['start_command'] ?? '').trim().isEmpty;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.terminal),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    if (name != directory)
                      Text(directory,
                          style: Theme.of(context).textTheme.bodySmall),
                  ])),
              Text(phaseLabel(runtime),
                  key: ValueKey('runtime-phase-$directory')),
              PopupMenuButton<String>(
                key: ValueKey('runtime-target-menu-$directory'),
                tooltip: l.projectRuntimeTargetActions,
                enabled: !updating && !configuring,
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      unawaited(editTarget(directory: directory));
                    case 'rename':
                      unawaited(
                          editTarget(directory: directory, renameOnly: true));
                    case 'delete':
                      unawaited(deleteTarget(directory));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit',
                      enabled: target != null,
                      child: Text(l.projectRuntimeEditTarget)),
                  PopupMenuItem(
                      value: 'rename',
                      enabled: target != null,
                      child: Text(l.projectRuntimeRenameTarget)),
                  PopupMenuItem(
                      value: 'delete',
                      enabled: !active && !occupied,
                      child: Text(active || occupied
                          ? l.projectRuntimeDeleteAfterStop
                          : l.projectRuntimeDeleteTarget)),
                ],
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('runtime-location-$directory-$location'),
              initialValue: location,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: l.projectRuntimeLocation,
                  border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(
                    value: 'host', child: Text(l.projectRuntimeHost)),
                DropdownMenuItem(
                    value: 'docker', child: Text(l.projectRuntimeDocker)),
              ],
              onChanged: updating || configuring || target == null
                  ? null
                  : (value) {
                      if (value != null) {
                        unawaited(act(
                            directory,
                            () => widget.client.saveProjectRuntimeLocation(
                                widget.projectId, directory, value)));
                      }
                    },
            ),
            if (active) ...[
              const SizedBox(height: 8),
              Text(l.projectRuntimeCurrentLocation(runtime!.location == 'host'
                  ? l.projectRuntimeHost
                  : l.projectRuntimeDocker)),
            ],
            const SizedBox(height: 10),
            if (!active && missingCommand) ...[
              Text(l.projectRuntimeStartRequired,
                  key: ValueKey('runtime-start-required-$directory'),
                  style: Theme.of(context).textTheme.bodySmall),
              if (target?.reason.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(target!.reason,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ] else
              SelectableText(active
                  ? runtime!.command
                  : target?.configuration.values['start_command'] ??
                      runtime?.command ??
                      ''),
            if (occupied) ...[
              const SizedBox(height: 8),
              Text(l.projectRuntimeOccupied(runtime!.leaseSessionId!)),
            ] else if (runtime?.phase == 'running') ...[
              const SizedBox(height: 8),
              Text(l.projectRuntimeAvailable),
            ],
            if (runtime?.revision != null) ...[
              const SizedBox(height: 8),
              Text(l.projectRuntimeSnapshot(runtime!.revision!)),
            ],
            if (runtime?.error != null) ...[
              const SizedBox(height: 8),
              SelectableText(runtime!.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  key: ValueKey('runtime-start-$directory'),
                  onPressed: updating ||
                          configuring ||
                          active ||
                          target == null ||
                          missingCommand
                      ? null
                      : () => act(
                          directory,
                          () => widget.client.startProjectRuntime(
                              widget.projectId, directory)),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.projectRuntimeStart)),
              OutlinedButton.icon(
                  key: ValueKey('runtime-stop-$directory'),
                  onPressed: updating || !active || occupied
                      ? null
                      : () => act(
                          directory,
                          () => widget.client
                              .stopProjectRuntime(widget.projectId, directory)),
                  icon: const Icon(Icons.stop),
                  label: Text(l.projectRuntimeStop)),
              if (runtime != null)
                TextButton.icon(
                    onPressed: updating ? null : () => showLogs(directory),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(l.projectRuntimeLogs)),
              if (runtime?.acceptanceRunId != null && active)
                TextButton.icon(
                    onPressed: updating
                        ? null
                        : () =>
                            openDesktop(directory, runtime!.acceptanceRunId!),
                    icon: const Icon(Icons.desktop_windows_outlined),
                    label: Text(l.projectRuntimeDesktop)),
            ]),
            if (updating) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator()
            ],
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final directories = {
      ...?overview?.targets.map((target) => target.directory),
      ...?overview?.runtimes.map((runtime) => runtime.directory)
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.projectRuntimeTitle), actions: [
        IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            tooltip: l.acceptanceRefreshStatus),
      ]),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(l.projectRuntimeHint),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    key: const Key('runtime-add-target'),
                    onPressed: configuring ? null : () => editTarget(),
                    icon: const Icon(Icons.add),
                    label: Text(l.projectRuntimeAddTarget)),
                FilledButton.icon(
                    key: const Key('runtime-auto-configure'),
                    onPressed:
                        configuring || busy.isNotEmpty ? null : autoConfigure,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(l.projectRuntimeAutoConfigure)),
                OutlinedButton.icon(
                    key: const Key('runtime-configure'),
                    onPressed: configuring ? null : configure,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l.projectRuntimeConfigure)),
              ]),
              if (configuring) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l.projectRuntimeAutoConfiguring),
              ],
              if (configurationResult != null) ...[
                const SizedBox(height: 12),
                Text(l.projectRuntimeAutoConfigured(
                    configurationResult!.total, configurationResult!.ready)),
                if (configurationResult!.ready < configurationResult!.total &&
                    configurationResult!.reasoning.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(configurationResult!.reasoning,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
              const SizedBox(height: 16),
              for (final failure in [configurationError, error])
                if (failure != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(failure.toString(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              if (overview == null && error == null)
                const Center(child: CircularProgressIndicator()),
              if (overview != null && directories.isEmpty)
                Text(l.projectRuntimeEmpty),
              for (final directory in directories) targetCard(directory),
            ]),
          )),
    );
  }
}
