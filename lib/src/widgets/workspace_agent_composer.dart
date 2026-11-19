import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../bridge_client.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import 'app_snack_bar.dart';
import 'message_composer.dart';
import 'model_selection_panel.dart';
import 'composer_settings_dropdown.dart';
import 'approval_mode_selector.dart';
import 'workspace_dispatch_panel.dart';
import 'workspace_composer_autocomplete.dart';
import 'workspace_composer_reference.dart';
import 'workspace_conversation_actions.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// A draft shared by the home composer and its expanded conversation.
class WorkspaceAgentComposerController extends ChangeNotifier {
  WorkspaceAgentComposerController(this.client) {
    _connectionRevision = client.connectionRevision;
    _conversationId = client.workspaceConversationId;
    client.sessionCacheRevision.addListener(_connectionChanged);
    client.workspaceConversationRevision.addListener(_connectionChanged);
    text.addListener(notifyListeners);
    ready = _loadModels();
  }

  final BridgeClient client;
  final text = TextEditingController();
  final List<String> _paths = [];
  final Map<String, DomainAttachment> _uploaded = {};
  final List<WorkspaceComposerReference> _references = [];
  String? referenceProjectId;
  final _drafts = <String,
      ({
    String text,
    List<String> paths,
    Map<String, DomainAttachment> uploaded,
    String? requestId,
    String? requestPayload,
    List<WorkspaceComposerReference> references,
    String? referenceProjectId
  })>{};
  String? _requestId, _requestPayload;

  String requestIdFor(String payload) {
    if (_requestPayload != payload) {
      _requestPayload = payload;
      _requestId = const Uuid().v4();
    }
    return _requestId!;
  }

  List<String> get paths => List.unmodifiable(_paths);
  List<WorkspaceComposerReference> get references => _references
      .where((reference) =>
          reference.isUsedIn(text.text) &&
          (reference.kind != 'skill' || taskAgent == 'codex'))
      .toList(growable: false);

  void selectReferenceProject(ProjectSummary project) {
    referenceProjectId = project.id;
    notifyListeners();
  }

  void addReference(WorkspaceComposerReference reference) {
    _references.removeWhere((item) =>
        item.kind == reference.kind &&
        item.projectId == reference.projectId &&
        item.value == reference.value);
    _references.add(reference);
    notifyListeners();
  }

  void removeReference(WorkspaceComposerReference reference) {
    _references.remove(reference);
    text.text = text.text.replaceAll(reference.token, '');
    text.selection = TextSelection.collapsed(offset: text.text.length);
    notifyListeners();
  }

  List<ModelProviderConfig> providers = [];
  Map<String, dynamic>? selection;
  String taskAgent = 'pi';
  ApprovalMode approvalMode = ApprovalMode.smart;
  bool savingApprovalMode = false;
  Object? modelError;
  bool loadingModels = true;
  bool savingModel = false;
  late Future<void> ready;
  late int _connectionRevision;
  late String _conversationId;
  int _configurationRevision = 0;
  bool _disposed = false;
  bool _initialized = false;
  bool get isInitializing => loadingModels && !_initialized;
  bool get hasContent => text.text.trim().isNotEmpty || _paths.isNotEmpty;
  String? get model => selection?['model'] as String?;

  void _connectionChanged() {
    if (_connectionRevision == client.connectionRevision &&
        _conversationId == client.workspaceConversationId) {
      return;
    }
    if (_connectionRevision == client.connectionRevision) {
      _drafts[_conversationId] = (
        text: text.text,
        paths: List.of(_paths),
        uploaded: Map.of(_uploaded),
        requestId: _requestId,
        requestPayload: _requestPayload,
        references: List.of(_references),
        referenceProjectId: referenceProjectId
      );
    } else {
      _drafts.clear();
    }
    _connectionRevision = client.connectionRevision;
    _conversationId = client.workspaceConversationId;
    _configurationRevision++;
    _initialized = false;
    clear();
    referenceProjectId = null;
    final draft = _drafts[_conversationId];
    if (draft != null) {
      _paths.addAll(draft.paths);
      _uploaded.addAll(draft.uploaded);
      text.text = draft.text;
      _requestId = draft.requestId;
      _requestPayload = draft.requestPayload;
      _references.addAll(draft.references);
      referenceProjectId = draft.referenceProjectId;
    }
    providers = [];
    selection = null;
    taskAgent = 'pi';
    approvalMode = ApprovalMode.smart;
    savingApprovalMode = false;
    savingModel = false;
    ready = _loadModels();
  }

  Future<void> _loadModels() async {
    final revision = _configurationRevision;
    loadingModels = true;
    modelError = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        client.getModelProviders(),
        client.workspaceAgentRequest(action: '/model'),
        client.workspaceAgentRequest(action: '/dispatch/settings'),
      ]);
      if (_disposed || revision != _configurationRevision) return;
      providers = (values[0] as List<ModelProviderConfig>)
          .where((p) => p.enabled)
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      selection = (values[1] as Map<String, dynamic>)['selection']
          as Map<String, dynamic>?;
      final dispatchSettings = values[2] as Map<String, dynamic>;
      taskAgent = dispatchSettings['agent'] as String? ?? 'pi';
      approvalMode = ApprovalMode.fromJson(dispatchSettings['approval_mode']);
    } catch (error) {
      if (_disposed || revision != _configurationRevision) return;
      modelError = error;
    } finally {
      if (!_disposed && revision == _configurationRevision) {
        loadingModels = false;
        _initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> refreshModels() => ready = _loadModels();

  void setTaskAgent(String value) {
    taskAgent = value;
    notifyListeners();
  }

  Future<void> saveApprovalMode(ApprovalMode value) async {
    if (savingApprovalMode) return;
    final revision = _configurationRevision;
    savingApprovalMode = true;
    notifyListeners();
    try {
      final result = await client.workspaceAgentRequest(
          action: '/approval-mode',
          method: 'PUT',
          body: {'approval_mode': value.name});
      if (_disposed || revision != _configurationRevision) return;
      if (result['approval_mode'] != value.name) {
        throw StateError('Bridge did not save the selected approval mode');
      }
      approvalMode = value;
    } catch (_) {
      if (_disposed || revision != _configurationRevision) return;
      rethrow;
    } finally {
      if (!_disposed && revision == _configurationRevision) {
        savingApprovalMode = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveModel(Map<String, dynamic>? value) async {
    final revision = _configurationRevision;
    savingModel = true;
    notifyListeners();
    try {
      await client.workspaceAgentRequest(
          action: '/model', method: 'PUT', body: {'selection': value});
      if (_disposed || revision != _configurationRevision) return;
      selection = value;
      modelError = null;
    } finally {
      if (!_disposed && revision == _configurationRevision) {
        savingModel = false;
        notifyListeners();
      }
    }
  }

  void addFiles(Iterable<String> paths) {
    for (final path in paths) {
      if (!_paths.contains(path)) _paths.add(path);
    }
    notifyListeners();
  }

  void removeFile(String path) {
    _paths.remove(path);
    _uploaded.remove(path);
    notifyListeners();
  }

  Future<List<DomainAttachment>> uploadAttachments() async {
    final revision = _configurationRevision;
    if (_paths.length > 8) throw StateError('Attach at most 8 files.');
    var total = 0;
    for (final path in _paths) {
      total += await File(path).length();
    }
    if (total > 10 * 1024 * 1024) {
      throw StateError('Attachments must total at most 10 MB.');
    }
    final attachments = <DomainAttachment>[];
    for (final path in List<String>.of(_paths)) {
      var attachment = _uploaded[path];
      if (attachment == null) {
        final uploaded =
            await client.uploadFile(path).timeout(const Duration(seconds: 75));
        if (_disposed || revision != _configurationRevision) {
          throw StateError('Connection changed while uploading attachments');
        }
        attachment = DomainAttachment(
            id: uploaded.id,
            kind: uploaded.contentType.startsWith('image/') ||
                    RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false)
                        .hasMatch(uploaded.fileName)
                ? 'image'
                : 'file',
            fileName: uploaded.fileName,
            contentType: uploaded.contentType,
            sizeBytes: uploaded.sizeBytes,
            url: uploaded.url);
        _uploaded[path] = attachment;
      }
      attachments.add(attachment);
    }
    return attachments;
  }

  void clear() {
    _requestId = null;
    _requestPayload = null;
    _paths.clear();
    _uploaded.clear();
    _references.clear();
    text.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    client.sessionCacheRevision.removeListener(_connectionChanged);
    client.workspaceConversationRevision.removeListener(_connectionChanged);
    text.removeListener(notifyListeners);
    text.dispose();
    super.dispose();
  }
}

class WorkspaceAgentComposer extends StatefulWidget {
  const WorkspaceAgentComposer(
      {super.key,
      required this.controller,
      required this.onSend,
      this.enabled = true,
      this.home = false,
      this.prominent = false,
      this.maxLines,
      this.projects = const [],
      this.projectId,
      this.onConversationOpened,
      this.pickAttachments});
  final WorkspaceAgentComposerController controller;
  final VoidCallback onSend;
  final bool enabled, home, prominent;
  final int? maxLines;
  final List<ProjectSummary> projects;
  final String? projectId;
  final VoidCallback? onConversationOpened;
  final Future<List<String>> Function()? pickAttachments;

  @override
  State<WorkspaceAgentComposer> createState() => _WorkspaceAgentComposerState();
}

enum _AgentSettingsSection { agent, provider, model }

class _WorkspaceAgentComposerState extends State<WorkspaceAgentComposer> {
  bool _picking = false;
  final _homeFocus = FocusNode();
  final _autocomplete = GlobalKey<WorkspaceComposerAutocompleteState>();
  final _settingsMenuController = OverlayPortalController();
  final _customModel = TextEditingController();
  _AgentSettingsSection? _settingsSection;
  String? _pendingProviderId;

  @override
  void initState() {
    super.initState();
    _homeFocus.addListener(_focusChanged);
    _homeFocus.onKeyEvent = (node, event) =>
        _autocomplete.currentState?.handleKeyEvent(node, event) ??
        KeyEventResult.ignored;
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _homeFocus.dispose();
    _customModel.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    final revision = widget.controller.client.connectionRevision;
    try {
      final paths = widget.pickAttachments != null
          ? await widget.pickAttachments!()
          : (await openFiles()).map((file) => file.path).toList();
      if (!mounted || revision != widget.controller.client.connectionRevision) {
        return;
      }
      widget.controller.addFiles(paths);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(AppSnackBar(isError: true, content: Text('$error')));
  }

  Future<void> _submit() async {
    final draft = widget.controller;
    if (!widget.enabled ||
        !draft.hasContent ||
        draft.savingModel ||
        draft.savingApprovalMode ||
        _picking ||
        !draft.text.value.composing.isCollapsed) {
      return;
    }
    if (_autocomplete.currentState?.acceptSuggestion() == true) return;
    final command = draft.text.text.trim();
    if (!workspaceSlashCommands.contains(command)) {
      widget.onSend();
      return;
    }
    draft.text.clear();
    switch (command) {
      case '/new':
        draft.client.startWorkspaceConversation();
      case '/history':
      case '/memory':
        final selected = await showWorkspaceConversationLibrary(context,
            client: draft.client,
            memories: command == '/memory',
            projectId: widget.projectId,
            projects: widget.projects);
        if (selected != null && mounted) {
          draft.client.openWorkspaceConversation(selected);
          widget.onConversationOpened?.call();
        }
      case '/model':
        if (await _prepareSettingsMenu() && mounted) {
          setState(() => _settingsSection = _AgentSettingsSection.provider);
          _settingsMenuController.show();
        }
      case '/help':
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(_text(context, '助手命令', 'Assistant commands')),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          for (final item in workspaceSlashCommands)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                    '$item  ${workspaceCommandDescription(context, item)}')),
                          Text(_text(
                              context,
                              r'@ 引用项目文件；执行 Agent 为 Codex 时，$ 可选择技能。',
                              r'@ references project files; $ selects skills when the execution agent is Codex.')),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(_text(context, '关闭', 'Close')))
                    ]));
    }
  }

  Future<bool> _prepareSettingsMenu() async {
    final controller = widget.controller;
    final revision = controller.client.connectionRevision;
    if (controller.modelError != null) {
      await controller.refreshModels();
      if (!mounted || revision != controller.client.connectionRevision) {
        return false;
      }
      if (controller.modelError != null) {
        _showError(controller.modelError!);
        return false;
      }
    }
    if (!mounted || controller.loadingModels) return false;
    setState(() {
      _pendingProviderId = controller.selection?['provider_id'] as String?;
      _customModel.text = controller.model ?? '';
    });
    return true;
  }

  Future<void> _saveMenuSelection(Map<String, dynamic>? value) async {
    if (widget.controller.savingModel) return;
    _closeSettingsMenu();
    try {
      await widget.controller.saveModel(value);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _closeSettingsMenu() {
    _settingsMenuController.hide();
    setState(() => _settingsSection = null);
  }

  Widget _buildSettingsMenu(WorkspaceAgentComposerController draft) {
    final savedProviderId = draft.selection?['provider_id'] as String?;
    final savedProvider =
        draft.providers.where((p) => p.id == savedProviderId).firstOrNull;
    final provider =
        draft.providers.where((p) => p.id == _pendingProviderId).firstOrNull;
    final label = draft.loadingModels || draft.savingModel
        ? _text(context, '加载模型…', 'Loading model…')
        : draft.model == null
            ? _text(context, '自动选择模型', 'Automatic model')
            : [savedProvider?.name ?? savedProviderId ?? '', draft.model!]
                .where((part) => part.isNotEmpty)
                .join(' • ');
    return ComposerSettingsDropdown<_AgentSettingsSection>(
        key: Key(widget.home ? 'home-assistant-model' : 'agent-chat-model'),
        controller: _settingsMenuController,
        label: label,
        maxButtonWidth: 260,
        enabled: widget.enabled &&
            !draft.loadingModels &&
            !draft.savingModel &&
            !draft.savingApprovalMode,
        beforeOpen: _prepareSettingsMenu,
        selectedSection: _settingsSection,
        onSectionChanged: (value) => setState(() => _settingsSection = value),
        sections: [
          ComposerSettingsSection(
              value: _AgentSettingsSection.agent,
              key: const Key('agent-dispatch-settings-button'),
              label: _text(context, '执行 Agent', 'Task agent'),
              contentBuilder: (_) => WorkspaceDispatchAgentOptions(
                  client: draft.client,
                  onAgentChanged: draft.setTaskAgent,
                  onSaved: _closeSettingsMenu)),
          ComposerSettingsSection(
              value: _AgentSettingsSection.provider,
              key: const Key('agent-provider-settings-button'),
              label: _text(context, '模型服务', 'Model provider'),
              contentBuilder: (_) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ComposerSettingsOption(
                            key: const Key('agent-provider-option-auto'),
                            label: _text(context, '自动选择', 'Automatic'),
                            selected: _pendingProviderId == null,
                            onTap: () => unawaited(_saveMenuSelection(null))),
                        for (final candidate in draft.providers)
                          ComposerSettingsOption(
                              key: ValueKey([
                                'agent-provider-option',
                                candidate.id
                              ].join('-')),
                              label: candidate.name,
                              selected: candidate.id == _pendingProviderId,
                              onTap: () => setState(() {
                                    _pendingProviderId = candidate.id;
                                    _customModel.text =
                                        candidate.id == savedProviderId
                                            ? draft.model ?? ''
                                            : candidate.model ?? '';
                                    _settingsSection =
                                        _AgentSettingsSection.model;
                                  })),
                      ])),
          ComposerSettingsSection(
              value: _AgentSettingsSection.model,
              key: const Key('agent-model-settings-button'),
              label: _text(context, '模型', 'Model'),
              contentBuilder: (_) => provider == null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_text(context, '先选择模型服务，再选择模型。',
                          'Choose a model provider first.')),
                      TextButton(
                          onPressed: () => setState(() => _settingsSection =
                              _AgentSettingsSection.provider),
                          child: Text(
                              _text(context, '选择模型服务', 'Choose provider'))),
                    ])
                  : ModelSelectionPanel(
                      client: draft.client,
                      provider: provider,
                      selectedModel:
                          _customModel.text.isEmpty ? null : _customModel.text,
                      models: [
                        if (provider.id == savedProviderId &&
                            draft.model != null)
                          draft.model!
                      ],
                      customController: _customModel,
                      customHint: _text(context, '输入模型名称', 'Custom model'),
                      defaultLabel: provider.model?.trim().isNotEmpty == true
                          ? _text(context, '服务默认模型', 'Provider default')
                          : null,
                      loadErrorText: _text(context, '未能获取模型列表，可手动输入名称。',
                          'Could not load models. Enter a model name manually.'),
                      keyPrefix: 'agent-model',
                      onSelected: (model) => unawaited(_saveMenuSelection({
                            'provider_id': provider.id,
                            'model': model ?? provider.model!,
                          })))),
        ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final draft = widget.controller;
        final theme = Theme.of(context);
        final accent = AppColors.accentBlueFor(theme.brightness);

        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draft.references.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final reference in draft.references)
                        InputChip(
                            label: Text(
                                '${reference.projectName} · ${reference.token}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            onDeleted: widget.enabled
                                ? () => draft.removeReference(reference)
                                : null),
                    ])),
              if (draft.paths.isNotEmpty)
                SizedBox(
                    height: widget.home ? 88 : 76,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: draft.paths.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final path = draft.paths[index];
                          final name =
                              path.replaceAll('\\', '/').split('/').last;
                          final image = RegExp(r'\.(png|jpe?g|webp|gif)$',
                                  caseSensitive: false)
                              .hasMatch(name);
                          return Container(
                              width: 142,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: AppColors.panelFor(theme.brightness),
                                  border: Border.all(
                                      color:
                                          AppColors.outlineFor(theme.brightness)
                                              .withValues(alpha: .6)),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                if (image)
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(File(path),
                                          width: 36,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.image_outlined))),
                                if (!image)
                                  const Icon(Icons.insert_drive_file_outlined,
                                      size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall)),
                                IconButton(
                                    tooltip: _text(
                                        context, '移除附件', 'Remove attachment'),
                                    constraints: const BoxConstraints.tightFor(
                                        width: 28, height: 28),
                                    padding: EdgeInsets.zero,
                                    onPressed: widget.enabled
                                        ? () => draft.removeFile(path)
                                        : null,
                                    icon: const Icon(Icons.close, size: 16)),
                              ]));
                        })),
              MessageComposer(
                inputKey: Key(
                    widget.home ? 'home-assistant-input' : 'agent-chat-input'),
                controller: draft.text,
                focusNode: _homeFocus,
                inputWrapper: (input) => WorkspaceComposerAutocomplete(
                    key: _autocomplete,
                    client: draft.client,
                    controller: draft.text,
                    focusNode: _homeFocus,
                    projects: widget.projects,
                    allowProjectChange: widget.projectId == null,
                    projectId: widget.projectId ?? draft.referenceProjectId,
                    agent: draft.taskAgent,
                    enabled: widget.enabled,
                    onReference: draft.addReference,
                    onProjectSelected: draft.selectReferenceProject,
                    onSubmit: () => unawaited(_submit()),
                    child: input),
                prominent: widget.prominent,
                enabled: widget.enabled,
                maxLines: widget.maxLines ?? 4,
                maxLength: 8000,
                surfaceColor: widget.prominent
                    ? Color.alphaBlend(
                        AppColors.panelFor(theme.brightness)
                            .withValues(alpha: .65),
                        AppColors.screenFor(theme.brightness))
                    : widget.home
                        ? AppColors.screenFor(theme.brightness)
                        : null,
                borderColor: widget.prominent
                    ? _homeFocus.hasFocus
                        ? accent.withValues(alpha: .65)
                        : AppColors.outlineFor(theme.brightness)
                            .withValues(alpha: .8)
                    : null,
                textInputAction: TextInputAction.send,
                hintText: widget.home
                    ? _text(context, '有什么想推进的？',
                        'What would you like to move forward?')
                    : _text(context, '和助手聊聊…', 'Message your assistant…'),
                onSubmitted: (_) => unawaited(_submit()),
                settings: [
                  _buildSettingsMenu(draft),
                  ApprovalModeSelector(
                    key: const Key('agent-approval-mode-button'),
                    value: draft.approvalMode,
                    keyPrefix: 'agent-approval-mode',
                    enabled: widget.enabled &&
                        !draft.loadingModels &&
                        !draft.savingModel,
                    saving: draft.savingApprovalMode,
                    onChanged: (mode) async {
                      try {
                        await draft.saveApprovalMode(mode);
                      } catch (_) {
                        if (mounted) {
                          _showError(approvalModeLocalizations(this.context)
                              .approvalModeSaveFailed);
                        }
                      }
                    },
                  ),
                ],
                actions: [
                  IconButton(
                      key: Key(widget.home
                          ? 'home-assistant-attach'
                          : 'agent-chat-attach'),
                      tooltip: _text(context, '添加附件', 'Add attachment'),
                      style: MessageComposer.actionStyle(context),
                      onPressed: widget.enabled && !_picking ? _pick : null,
                      icon: _picking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.attach_file_rounded, size: 20)),
                  const SizedBox(width: 4),
                  IconButton.filled(
                      key: Key(widget.home
                          ? 'home-assistant-send'
                          : 'agent-chat-send'),
                      tooltip: _text(context, '发送', 'Send'),
                      style: widget.prominent
                          ? MessageComposer.actionStyle(context, primary: true).copyWith(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                  (states) =>
                                      states.contains(WidgetState.disabled)
                                          ? accent.withValues(alpha: .10)
                                          : accent),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                  (states) => states
                                          .contains(WidgetState.disabled)
                                      ? AppColors.mutedFor(theme.brightness)
                                      : AppColors.accentBlueOnFor(theme.brightness)),
                              fixedSize: const WidgetStatePropertyAll(Size.square(36)),
                              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))
                          : MessageComposer.actionStyle(context, primary: true),
                      onPressed: widget.enabled && draft.hasContent && !draft.savingModel && !draft.savingApprovalMode && !_picking ? () => unawaited(_submit()) : null,
                      icon: Icon(widget.prominent ? Icons.arrow_upward_rounded : Icons.send_rounded, size: 20)),
                ],
              ),
            ]);
      });
}
