import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_card.dart';

class PiPluginsScreen extends StatefulWidget {
  const PiPluginsScreen({super.key, this.client});
  static const routeName = '/settings/pi-plugins';
  final BridgeClient? client;

  @override
  State<PiPluginsScreen> createState() => _PiPluginsScreenState();
}

class _PiPluginsScreenState extends State<PiPluginsScreen> {
  List<PiPlugin> _plugins = const [];
  List<ProjectSummary> _projects = const [];
  Object? _error;
  bool _loading = true;
  final Set<String> _busy = {};
  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values =
          await Future.wait([_client.getPiPlugins(), _client.listProjects()]);
      if (!mounted) return;
      setState(() {
        _plugins = values[0] as List<PiPlugin>;
        _projects = values[1] as List<ProjectSummary>;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _replace(PiPlugin plugin) => setState(() {
        _plugins = [
          for (final item in _plugins)
            if (item.id == plugin.id) plugin else item
        ];
      });

  Future<void> _run(String id, Future<void> Function() operation) async {
    setState(() => _busy.add(id));
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10n.piPluginOperationFailed('$error'))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _install() async {
    final result = await showDialog<_InstallPiPlugin>(
        context: context, builder: (_) => _InstallDialog(projects: _projects));
    if (result == null) return;
    setState(() => _busy.add('__install__'));
    try {
      final plugin = await _client.installPiPlugin(
          source: result.source,
          id: result.id,
          sha256: result.sha256,
          contentBase64: result.contentBase64,
          fileName: result.fileName,
          projectIds: result.projectIds,
          config: result.config);
      if (mounted) setState(() => _plugins = [..._plugins, plugin]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10n.piPluginOperationFailed('$error'))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove('__install__'));
    }
  }

  Future<void> _edit(PiPlugin plugin) async {
    final result = await showDialog<_PluginEdit>(
        context: context,
        builder: (_) => _EditDialog(plugin: plugin, projects: _projects));
    if (result == null) return;
    await _run(
        plugin.id,
        () async => _replace(await _client.updatePiPlugin(plugin.id,
            projectIds: result.projectIds, config: result.config)));
  }

  Future<void> _remove(PiPlugin plugin) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(context.l10n.piPluginRemoveConfirm(plugin.name)),
                content: Text(context.l10n.piPluginPermissionWarning),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(context.l10n.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(context.l10n.uninstall))
                ]));
    if (confirmed != true) return;
    await _run(plugin.id, () async {
      await _client.removePiPlugin(plugin.id);
      if (mounted) {
        setState(
            () => _plugins = _plugins.where((p) => p.id != plugin.id).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.piPluginsTitle), actions: [
        IconButton(
            onPressed: _loading ? null : _load,
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh_rounded))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy.contains('__install__') ? null : _install,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.piPluginAdd)),
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: AppSpacing.screenPadding, children: [
                Text(l10n.piPluginsSubtitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.compact),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.security_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.piPluginPermissionWarning))
                ]),
                const SizedBox(height: AppSpacing.fieldGap),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  Center(
                      child: Column(children: [
                    Text(l10n.piPluginLoadFailed('$_error')),
                    TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l10n.retry))
                  ]))
                else if (_plugins.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Center(child: Text(l10n.piPluginEmpty)))
                else
                  ..._plugins.map((plugin) => Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.compact),
                      child: _pluginCard(plugin))),
                const SizedBox(height: 88),
              ]))),
    );
  }

  Widget _pluginCard(PiPlugin plugin) {
    final l10n = context.l10n;
    final busy = _busy.contains(plugin.id);
    final scope = plugin.projectIds.isEmpty
        ? l10n.piPluginGlobal
        : plugin.projectIds
            .map((id) =>
                _projects
                    .where((p) => p.id == id)
                    .map((p) => p.name)
                    .firstOrNull ??
                id)
            .join(', ');
    return AppCard(
        padding: AppSpacing.cardPadding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(plugin.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text([
                    plugin.id,
                    if (plugin.version?.isNotEmpty == true)
                      'v${plugin.version}',
                    plugin.source.kind.name
                  ].join(' · '))
                ])),
            Switch(
                value: plugin.enabled,
                onChanged: busy
                    ? null
                    : (value) => _run(
                        plugin.id,
                        () async => _replace(await _client
                            .updatePiPlugin(plugin.id, enabled: value))))
          ]),
          const SizedBox(height: 8),
          Text('${l10n.piPluginScope}: $scope'),
          if (plugin.permissions.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                    spacing: 6,
                    children: plugin.permissions
                        .map((p) => Chip(
                            label: Text(p),
                            visualDensity: VisualDensity.compact))
                        .toList())),
          if (plugin.validationError != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${l10n.piPluginValidationFailed}: ${plugin.validationError}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(
                        plugin.id,
                        () async => _replace(
                            await _client.validatePiPlugin(plugin.id))),
                icon: const Icon(Icons.verified_outlined),
                label: Text(l10n.piPluginValidate)),
            IconButton(
                onPressed: busy ? null : () => _edit(plugin),
                tooltip: l10n.piPluginConfig,
                icon: const Icon(Icons.tune_rounded)),
            const Spacer(),
            IconButton(
                onPressed: busy ? null : () => _remove(plugin),
                tooltip: l10n.uninstall,
                icon: const Icon(Icons.delete_outline_rounded))
          ]),
          Text(l10n.piPluginNextTurnHint,
              style: Theme.of(context).textTheme.bodySmall),
        ]));
  }
}

class _InstallPiPlugin {
  const _InstallPiPlugin(this.source, this.id, this.sha256, this.contentBase64,
      this.fileName, this.projectIds, this.config);
  final PiPluginSource source;
  final String? id, sha256, contentBase64, fileName;
  final List<String> projectIds;
  final Map<String, dynamic> config;
}

class _PluginEdit {
  const _PluginEdit(this.projectIds, this.config);
  final List<String> projectIds;
  final Map<String, dynamic> config;
}

PiPluginSourceKind inferPiPluginSourceKind(String value, bool hasUpload) {
  if (hasUpload) return PiPluginSourceKind.upload;
  final source = value.trim().toLowerCase();
  if (source.startsWith('npm:')) return PiPluginSourceKind.npm;
  if (source.startsWith('git:') ||
      source.startsWith('git@') ||
      source.endsWith('.git') ||
      source.contains('github.com/') ||
      source.contains('gitlab.com/') ||
      source.contains('bitbucket.org/')) {
    return PiPluginSourceKind.git;
  }
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return PiPluginSourceKind.url;
  }
  return PiPluginSourceKind.local;
}

class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.projects});
  final List<ProjectSummary> projects;
  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  final source = TextEditingController(),
      config = TextEditingController(text: '{}');
  final selected = <String>{};
  XFile? file;
  String? error;
  @override
  void dispose() {
    source.dispose();
    config.dispose();
    super.dispose();
  }

  Future<void> chooseFile() async {
    final value = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: 'Pi extension', extensions: ['js', 'mjs', 'cjs', 'json'])
    ]);
    if (value != null) {
      setState(() => file = value);
    }
  }

  Future<void> submit() async {
    try {
      final parsed = jsonDecode(config.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Configuration must be a JSON object');
      }
      final sourceValue = source.text.trim();
      String? encoded;
      if (file != null) {
        encoded = base64Encode(await file!.readAsBytes());
      }
      if (sourceValue.isEmpty && file == null) {
        throw const FormatException(
            'Enter an npm, URL, Git, or local path source');
      }
      if (!mounted) return;
      Navigator.pop(
          context,
          _InstallPiPlugin(
              PiPluginSource(
                  kind: inferPiPluginSourceKind(sourceValue, file != null),
                  value:
                      file != null ? (file?.name ?? 'upload.js') : sourceValue),
              null,
              null,
              encoded,
              file?.name,
              selected.toList(),
              parsed));
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(context.l10n.piPluginAdd),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: source,
                    decoration: InputDecoration(
                        labelText: context.l10n.piPluginSource)),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text(file?.name ?? context.l10n.piPluginSourceUpload),
                    trailing: IconButton(
                        onPressed: chooseFile,
                        tooltip: context.l10n.piPluginSourceUpload,
                        icon: const Icon(Icons.upload_file_rounded))),
                _ScopeFields(
                    projects: widget.projects,
                    selected: selected,
                    onChanged: () => setState(() {})),
                TextField(
                    controller: config,
                    minLines: 3,
                    maxLines: 7,
                    decoration: InputDecoration(
                        labelText: context.l10n.piPluginConfig,
                        errorText: error))
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel)),
            FilledButton(onPressed: submit, child: Text(context.l10n.install))
          ]);
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.plugin, required this.projects});
  final PiPlugin plugin;
  final List<ProjectSummary> projects;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final selected = widget.plugin.projectIds.toSet();
  late final config = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(widget.plugin.config));
  String? error;
  @override
  void dispose() {
    config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.plugin.name),
          content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _ScopeFields(
                    projects: widget.projects,
                    selected: selected,
                    onChanged: () => setState(() {})),
                TextField(
                    controller: config,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                        labelText: context.l10n.piPluginConfig,
                        errorText: error))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () {
                  try {
                    final value = jsonDecode(config.text);
                    if (value is! Map<String, dynamic>) {
                      throw const FormatException(
                          'Configuration must be a JSON object');
                    }
                    Navigator.pop(
                        context, _PluginEdit(selected.toList(), value));
                  } catch (e) {
                    setState(() => error = '$e');
                  }
                },
                child: Text(context.l10n.save))
          ]);
}

class _ScopeFields extends StatelessWidget {
  const _ScopeFields(
      {required this.projects,
      required this.selected,
      required this.onChanged});
  final List<ProjectSummary> projects;
  final Set<String> selected;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.l10n.piPluginScope),
      subtitle: Text(selected.isEmpty
          ? context.l10n.piPluginGlobal
          : context.l10n.piPluginSelectedProjects),
      children: projects
          .map((p) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected.contains(p.id),
              title: Text(p.name),
              onChanged: (v) {
                if (v == true) {
                  selected.add(p.id);
                } else {
                  selected.remove(p.id);
                }
                onChanged();
              }))
          .toList());
}
