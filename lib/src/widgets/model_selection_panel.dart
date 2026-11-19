import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../models.dart';
import 'composer_settings_dropdown.dart';
import '../theme/app_spacing.dart';

/// Shared catalog loading, selection and custom model input. The owner decides
/// whether to apply a choice immediately or save it with other settings.
class ModelSelectionPanel extends StatefulWidget {
  const ModelSelectionPanel(
      {super.key,
      required this.client,
      required this.customController,
      required this.onSelected,
      required this.customHint,
      required this.keyPrefix,
      this.provider,
      this.models = const [],
      this.selectedModel,
      this.defaultLabel,
      this.onCustomChanged,
      this.loadErrorText});

  final BridgeClient client;
  final ModelProviderConfig? provider;
  final List<String> models;
  final String? selectedModel, defaultLabel, loadErrorText;
  final String customHint, keyPrefix;
  final TextEditingController customController;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String>? onCustomChanged;

  @override
  State<ModelSelectionPanel> createState() => _ModelSelectionPanelState();
}

class _ModelSelectionPanelState extends State<ModelSelectionPanel> {
  List<String> _fetched = [];
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  late int _connectionRevision;

  @override
  void initState() {
    super.initState();
    _connectionRevision = widget.client.connectionRevision;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ModelSelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.provider;
    final after = widget.provider;
    if (oldWidget.client != widget.client ||
        _connectionRevision != widget.client.connectionRevision ||
        before?.id != after?.id ||
        before?.baseUrl != after?.baseUrl ||
        before?.apiKey != after?.apiKey ||
        before?.format != after?.format) {
      _connectionRevision = widget.client.connectionRevision;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final provider = widget.provider;
    setState(() {
      _fetched = [];
      _failed = false;
      _loading = provider != null;
    });
    if (provider == null) return;
    try {
      final models = await widget.client
          .getProviderModels(provider)
          .timeout(const Duration(seconds: 12));
      if (!mounted ||
          generation != _generation ||
          _connectionRevision != widget.client.connectionRevision) {
        return;
      }
      setState(() => _fetched = models);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Key _key(String suffix) => Key([widget.keyPrefix, suffix].join('-'));

  @override
  Widget build(BuildContext context) {
    final models = {
      ...widget.models,
      ..._fetched,
      if (widget.provider?.model != null) widget.provider!.model!,
    }.map((model) => model.trim()).where((model) => model.isNotEmpty).toList()
      ..sort();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_failed && widget.loadErrorText != null)
            Padding(
                padding: const EdgeInsets.all(AppSpacing.compact),
                child: Text(widget.loadErrorText!,
                    style: Theme.of(context).textTheme.bodySmall)),
          if (widget.defaultLabel != null)
            ComposerSettingsOption(
                key: _key('option-default'),
                label: widget.defaultLabel!,
                selected: widget.selectedModel == null,
                onTap: () => widget.onSelected(null)),
          for (final model in models)
            ComposerSettingsOption(
                key: _key('option-$model'),
                label: model,
                selected: widget.selectedModel == model,
                onTap: () => widget.onSelected(model)),
          Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.compact,
                  AppSpacing.stack, AppSpacing.compact, AppSpacing.stack),
              child: TextField(
                  key: _key('custom-input'),
                  controller: widget.customController,
                  maxLength: 200,
                  decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: widget.customHint,
                      contentPadding: const EdgeInsets.all(AppSpacing.compact),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusControl))),
                  onChanged: widget.onCustomChanged,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      widget.onSelected(value.trim());
                    }
                  },
                  textInputAction: TextInputAction.done)),
        ]);
  }
}
