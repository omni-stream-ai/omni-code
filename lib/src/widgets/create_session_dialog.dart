import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

typedef CreateSessionDialogResult = (String?, String, String?);

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
  List<ModelProviderConfig> _allProviders = const [];
  bool _loadingProviders = true;

  BridgeClient get _client => widget.client ?? bridgeClient;

  List<ModelProviderConfig> get _providers {
    final agent = parseAgentKind(_agent);
    final compatible = agent.compatibleFormats;
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
      if (_providers.isNotEmpty) {
        _providerId = autoProviderId;
      }
      return;
    }
    final stillValid = _providers.any((p) => p.id == _providerId);
    if (!stillValid) {
      _providerId = _providers.isNotEmpty ? autoProviderId : null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProviders();
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
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProviders = false;
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
            initialValue: _agent,
            items: AgentKind.selectableValues
                .map(
                  (agent) => DropdownMenuItem(
                    value: agent.id,
                    child: Text(agent.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _agent = value;
                _normalizeProviderSelection();
              });
            },
            decoration: InputDecoration(labelText: context.l10n.agentLabel),
          ),
          if (!_loadingProviders) ...[
            const SizedBox(height: AppSpacing.stack),
            DropdownButtonFormField<String>(
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
                });
              },
              decoration: InputDecoration(
                labelText: context.l10n.providerSessionLabel,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            Navigator.of(context).pop((
              title.isEmpty ? null : title,
              _agent,
              _providerId,
            ));
          },
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}
