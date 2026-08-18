import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

typedef CreateSessionDialogResult = (String?, String, String?, String?);

const _defaultProviderValue = '__default_provider__';
const _autoProviderValue = '__auto_provider__';

class CreateSessionDialog extends StatefulWidget {
  const CreateSessionDialog({
    super.key,
    this.client,
    this.initialProviderId,
  });

  final BridgeClient? client;
  final String? initialProviderId;

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final _titleController = TextEditingController();
  String _agent = appSettingsController.settings.lastSelectedAgent;
  late String? _providerId = widget.initialProviderId;
  String? _model;
  List<ModelProviderConfig> _allProviders = const [];
  List<String> _providerModels = const [];
  List<AgentSummary> _agentOptions = const [];
  bool _loadingProviders = true;
  bool _loadingModels = false;
  bool _loadingAgents = true;
  bool _installingAgent = false;
  String? _agentError;

  BridgeClient get _client => widget.client ?? bridgeClient;

  void _persistCachedAgents(List<AgentSummary> agents) {
    unawaited(
      appSettingsController.save(
        appSettingsController.settings.copyWith(cachedAgents: agents),
      ),
    );
  }

  List<ModelProviderConfig> get _providers {
    final compatible = _selectedAgentSummary?.compatibleFormats ??
        _client.agentDescriptorFor(_agent).compatibleFormats;
    if (compatible.isEmpty) {
      return _allProviders;
    }
    return _allProviders.where((p) => compatible.contains(p.format)).toList();
  }

  String get _selectedProviderValue {
    if (isAutoProviderId(_providerId)) {
      return _autoProviderValue;
    }
    if (_providerId == null || _providerId!.isEmpty) {
      return _defaultProviderValue;
    }
    return _providerId!;
  }

  void _normalizeProviderSelection() {
    if (isAutoProviderId(_providerId)) {
      if (_providers.isEmpty) {
        _providerId = null;
      }
      return;
    }
    if (_providerId == null || _providerId!.isEmpty) {
      return;
    }
    final stillValid = _providers.any((p) => p.id == _providerId);
    if (!stillValid) {
      _providerId = null;
    }
  }

  AgentSummary? get _selectedAgentSummary {
    for (final agent in _agentOptions) {
      if (agent.id == _agent) {
        return agent;
      }
    }
    return null;
  }

  bool get _selectedAgentInstalled => _selectedAgentSummary?.installed ?? true;
  bool get _shouldShowAgentStatusCard =>
      !_selectedAgentInstalled ||
      _agentError?.trim().isNotEmpty == true ||
      _installingAgent;

  String _agentOptionLabel(BuildContext context, AgentSummary summary) {
    if (summary.installed) {
      return summary.label;
    }
    return '${summary.label} (${context.l10n.agentNotInstalledStatus})';
  }

  void _normalizeSelectedAgent() {
    if (_agentOptions.isEmpty) {
      return;
    }
    final selectableAgents = _agentOptions.where((agent) => agent.selectable);
    final candidates =
        selectableAgents.isNotEmpty ? selectableAgents : _agentOptions;
    final exists = candidates.any((agent) => agent.id == _agent);
    if (!exists) {
      _agent = candidates
          .firstWhere(
            (agent) => agent.defaultSelected,
            orElse: () => candidates.first,
          )
          .id;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProviders();
    final cachedAgents = _client.peekAgents();
    final initialAgents = (cachedAgents != null && cachedAgents.isNotEmpty)
        ? cachedAgents
        : appSettingsController.settings.cachedAgents;
    if (initialAgents.isNotEmpty) {
      _agentOptions = initialAgents;
      _normalizeSelectedAgent();
      _normalizeProviderSelection();
      _loadingAgents = false;
    }
    _loadAgents(forceRefresh: true);
  }

  Future<void> _loadProviders() async {
    try {
      final providers = await _client.getModelProviders();
      if (!mounted) {
        return;
      }
      setState(() {
        _allProviders = providers;
        _normalizeProviderSelection();
        _loadingProviders = false;
      });
      unawaited(_loadModelsForSelectedProvider());
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProviders = false;
      });
    }
  }

  Future<void> _loadModelsForSelectedProvider() async {
    final providerId = _providerId;
    final provider =
        _providers.where((candidate) => candidate.id == providerId).firstOrNull;
    if (provider == null || isAutoProviderId(providerId)) {
      if (mounted) {
        setState(() {
          _providerModels = const [];
          _model = null;
          _loadingModels = false;
        });
      }
      return;
    }
    setState(() {
      _loadingModels = true;
    });
    try {
      final fetchedModels = await _client.getProviderModels(provider);
      if (!mounted || _providerId != providerId) {
        return;
      }
      setState(() {
        _providerModels = {
          ...fetchedModels,
          if (provider.model != null) provider.model!,
        }.toList()
          ..sort();
        if (!_providerModels.contains(_model)) {
          _model = null;
        }
        _loadingModels = false;
      });
    } catch (_) {
      if (!mounted || _providerId != providerId) {
        return;
      }
      setState(() {
        _providerModels = provider.model == null ? const [] : [provider.model!];
        if (!_providerModels.contains(_model)) {
          _model = null;
        }
        _loadingModels = false;
      });
    }
  }

  Future<void> _loadAgents({bool forceRefresh = false}) async {
    try {
      final agents = await _client.listAgents(forceRefresh: forceRefresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _agentOptions = agents;
        _normalizeSelectedAgent();
        _normalizeProviderSelection();
        _loadingAgents = false;
      });
      _persistCachedAgents(agents);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingAgents = false;
      });
    }
  }

  Future<void> _installSelectedAgent() async {
    final selectedAgentId = _selectedAgentSummary?.id ?? _agent;
    setState(() {
      _installingAgent = true;
      _agentError = null;
    });
    try {
      final result = await _client.installAgent(selectedAgentId);
      if (!mounted) {
        return;
      }
      setState(() {
        _installingAgent = false;
        final updatedAgents = [
          for (final agent in _agentOptions)
            if (agent.id == selectedAgentId)
              AgentSummary(
                descriptor: agent.descriptor,
                installed: result.success,
                installHint: agent.installHint,
                installedPath:
                    result.success ? result.installedPath : agent.installedPath,
              )
            else
              agent,
        ];
        _agentOptions = updatedAgents;
        _agentError = result.success ? null : result.message;
        _normalizeProviderSelection();
        if (result.success) {
          _persistCachedAgents(updatedAgents);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installingAgent = false;
        _agentError = '$error';
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.newSession),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: context.l10n.sessionTitleOptional,
            ),
          ),
          const SizedBox(height: AppSpacing.stack),
          DropdownButtonFormField<String>(
            initialValue: _agentOptions.any((agent) => agent.id == _agent)
                ? _agent
                : null,
            items: _agentOptions
                .where((agent) => agent.selectable)
                .map(
                  (agent) => DropdownMenuItem(
                    value: agent.id,
                    child: Text(_agentOptionLabel(context, agent)),
                  ),
                )
                .toList(),
            onChanged: _loadingAgents
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _agent = value;
                      _agentError = null;
                      _normalizeProviderSelection();
                      _model = null;
                    });
                    unawaited(_loadModelsForSelectedProvider());
                  },
            decoration: InputDecoration(labelText: context.l10n.agentLabel),
          ),
          if (_loadingAgents) ...[
            const SizedBox(height: AppSpacing.compact),
            const LinearProgressIndicator(minHeight: 2),
          ] else if (_selectedAgentSummary case final summary?) ...[
            if (_shouldShowAgentStatusCard) ...[
              const SizedBox(height: AppSpacing.compact),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.block),
                decoration: BoxDecoration(
                  color: _selectedAgentInstalled
                      ? Colors.green.withValues(alpha: 0.08)
                      : Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedAgentInstalled
                        ? Colors.green.withValues(alpha: 0.24)
                        : Colors.orange.withValues(alpha: 0.24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_selectedAgentInstalled)
                      Text(
                        context.l10n.agentNotInstalledStatus,
                        key: const Key('agent-install-status-label'),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    if (!_selectedAgentInstalled &&
                        summary.installHint.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        summary.installHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_agentError?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        _agentError!,
                        key: const Key('agent-install-error'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          if (!_loadingProviders) ...[
            const SizedBox(height: AppSpacing.stack),
            DropdownButtonFormField<String>(
              key: const Key('new-session-provider-selector'),
              initialValue: _selectedProviderValue,
              items: [
                if (_providers.isNotEmpty)
                  DropdownMenuItem(
                    value: _autoProviderValue,
                    child: Text(context.l10n.providerAuto),
                  ),
                ..._providers.map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  ),
                ),
                DropdownMenuItem(
                  value: _defaultProviderValue,
                  child: Text(context.l10n.providerDefault),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _providerId = switch (value) {
                    _autoProviderValue => autoProviderId,
                    _defaultProviderValue || null => null,
                    _ => value,
                  };
                  _model = null;
                });
                unawaited(_loadModelsForSelectedProvider());
              },
              decoration: InputDecoration(
                labelText: context.l10n.providerSessionLabel,
              ),
            ),
            const SizedBox(height: AppSpacing.stack),
            DropdownButtonFormField<String?>(
              key: const Key('new-session-model-selector'),
              initialValue: _model,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.l10n.modelDefault),
                ),
                ..._providerModels.map(
                  (model) => DropdownMenuItem<String?>(
                    value: model,
                    child: Text(model),
                  ),
                ),
              ],
              onChanged: _loadingModels
                  ? null
                  : (value) {
                      setState(() {
                        _model = value;
                      });
                    },
              decoration: InputDecoration(
                labelText: context.l10n.modelSessionLabel,
              ),
            ),
            if (_loadingModels) ...[
              const SizedBox(height: AppSpacing.micro),
              const LinearProgressIndicator(
                key: Key('new-session-model-loading'),
                minHeight: 2,
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('create-or-install-agent-button'),
          onPressed: _loadingAgents || _installingAgent
              ? null
              : !_selectedAgentInstalled
                  ? _installSelectedAgent
                  : () {
                      final title = _titleController.text.trim();
                      Navigator.of(context).pop((
                        title.isEmpty ? null : title,
                        _agent,
                        _providerId,
                        _model,
                      ));
                    },
          child: Text(
            _installingAgent
                ? context.l10n.installingAgent
                : (_selectedAgentInstalled
                    ? context.l10n.create
                    : context.l10n.installAgent),
          ),
        ),
      ],
    );
  }
}
