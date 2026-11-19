import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../services/bridge_setup_agent_controller.dart';
import '../services/bridge_setup_agent_host.dart';
import '../services/bridge_setup_agent_model.dart';
import '../services/local_bridge_setup.dart';
import '../settings/app_settings.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_card.dart';
import '../widgets/copyable_message.dart';
import 'model_provider_screen.dart';

class BridgeSetupAgentScreen extends StatefulWidget {
  const BridgeSetupAgentScreen(
      {super.key,
      required this.failure,
      this.diagnostic,
      this.client,
      this.setup,
      this.host,
      this.model});
  final LocalBridgeSetupFailure failure;
  final String? diagnostic;
  final BridgeClient? client;
  final LocalBridgeSetupService? setup;
  final BridgeSetupAgentHost? host;
  final BridgeSetupAgentModel? model;

  @override
  State<BridgeSetupAgentScreen> createState() => _BridgeSetupAgentScreenState();
}

class _BridgeSetupAgentScreenState extends State<BridgeSetupAgentScreen> {
  late final _host = widget.host ?? createBridgeSetupAgentHost();
  late final _model = widget.model ?? HttpBridgeSetupAgentModel();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  BridgeSetupAgentController? _agent;
  List<ModelProviderConfig> _providers = [];
  ModelProviderConfig? _provider;
  bool _loading = true,
      _configuring = false,
      _saveFailed = false,
      _returning = false;
  bool get _busy => _loading || _configuring || (_agent?.busy ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepare());
    });
  }

  Future<void> _prepare() async {
    final sources = await Future.wait([
      _host.discoverProviders().catchError((_) => <ModelProviderConfig>[]),
      (widget.client ?? bridgeClient)
          .getModelProviders()
          .timeout(const Duration(seconds: 2))
          .catchError((_) => <ModelProviderConfig>[]),
    ]);
    if (!mounted) return;
    final providers = <String, ModelProviderConfig>{
      for (final provider in appSettingsController.settings.localModelProviders)
        provider.id: provider,
      for (final source in sources)
        for (final provider in source) provider.id: provider,
    }.values.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final usable = providers.where(isUsableBridgeSetupModel).firstOrNull;
    setState(() {
      _providers = providers;
      _provider =
          usable ?? providers.where((provider) => provider.enabled).firstOrNull;
      _loading = false;
    });
    if (usable == null) {
      await _configureModel();
    } else {
      _startAgent(usable);
    }
  }

  Future<void> _configureModel() async {
    if (_configuring || (_agent?.busy ?? false)) return;
    final l10n = context.l10n;
    setState(() {
      _configuring = true;
      _saveFailed = false;
    });
    try {
      final provider = await showModelProviderEditor(
        context,
        provider: _provider,
        requireModel: true,
        title: l10n.bridgeAgentConfigureModel,
        saveLabel: l10n.bridgeAgentSaveAndContinue,
      );
      if (!mounted || provider == null) return;
      if (!isUsableBridgeSetupModel(provider)) return;
      // Keep the entered values available for a retry if persistence fails.
      _provider = provider;
      final providers = [
        for (final existing in _providers)
          if (existing.id != provider.id) existing,
        provider,
      ];
      await appSettingsController.save(appSettingsController.settings.copyWith(
        localModelProviders: providers,
      ));
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _provider = provider;
      });
      _startAgent(provider);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  void _startAgent(ModelProviderConfig provider) {
    _agent?.removeListener(_agentChanged);
    _agent?.dispose();
    final agent = BridgeSetupAgentController(
      model: _model,
      host: _host,
      setup: widget.setup ?? createLocalBridgeSetupService(),
      clientId: appSettingsController.settings.clientId,
      failure: widget.failure,
      diagnostic: widget.diagnostic,
      language: Localizations.localeOf(context).languageCode,
      secrets: [
        appSettingsController.settings.bridgeToken,
        for (final item in _providers) item.apiKey
      ],
      closeDependenciesOnDispose: false,
    )..addListener(_agentChanged);
    setState(() {
      _agent = agent;
      _provider = provider;
    });
    unawaited(agent.start(provider, context.l10n.bridgeAgentInitialRequest));
  }

  void _agentChanged() {
    if (!mounted) return;
    final result = _agent?.result;
    if (result != null) {
      if (_returning) return;
      _returning = true;
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _composer.text.trim();
    if (_busy || text.isEmpty) return;
    _composer.clear();
    unawaited(_agent?.send(text));
  }

  String _messageText(BridgeAgentMessage message) {
    if (message.role != 'tool') return message.text;
    final output = jsonDecode(message.text) as Map<String, dynamic>;
    if (output['output'] is String && (output['output'] as String).isNotEmpty) {
      return output['output'] as String;
    }
    if (output['ok'] == true) return context.l10n.bridgeAgentActionDone;
    if (output['error'].toString().contains('declined')) {
      return context.l10n.bridgeAgentCommandSkipped;
    }
    return context.l10n.bridgeAgentActionFailed;
  }

  @override
  void dispose() {
    _agent?.removeListener(_agentChanged);
    _agent?.dispose();
    _host.close();
    _model.close();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = _agent;
    final pending = agent?.pendingCommand;
    final problem = switch (agent?.problem) {
      BridgeSetupAgentProblem.modelAuthentication => l10n.bridgeAgentAuthError,
      BridgeSetupAgentProblem.modelRateLimit => l10n.bridgeAgentRateLimit,
      BridgeSetupAgentProblem.turnLimit => l10n.bridgeAgentTurnLimit,
      BridgeSetupAgentProblem.modelRequest => l10n.bridgeAgentRequestError,
      null => null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bridgeAgentTitle), actions: [
        TextButton(
            onPressed: _busy ? null : _configureModel,
            child: Text(l10n.bridgeAgentConfigureModel)),
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.tileX),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.bridgeAgentIntro),
            if (_provider != null)
              Row(children: [
                Expanded(
                    child:
                        Text('${_provider!.name} · ${_provider!.model ?? ""}')),
                if (_providers.where(isUsableBridgeSetupModel).length > 1)
                  PopupMenuButton<ModelProviderConfig>(
                    enabled: !_busy,
                    tooltip: l10n.bridgeAgentChooseModel,
                    onSelected: _startAgent,
                    itemBuilder: (_) => [
                      for (final provider
                          in _providers.where(isUsableBridgeSetupModel))
                        PopupMenuItem(
                            value: provider,
                            child: Text('${provider.name} · ${provider.model}'))
                    ],
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
              ]),
            if (_loading || (agent?.busy == true && pending == null))
              const LinearProgressIndicator(),
            Expanded(
                child: ListView(controller: _scroll, children: [
              if (agent == null && !_loading) ...[
                Text(l10n.bridgeAgentModelRequired),
                FilledButton(
                    onPressed: _configuring ? null : _configureModel,
                    child: Text(l10n.bridgeAgentConfigureModel)),
              ],
              if (_saveFailed)
                Text(l10n.bridgeAgentSaveError,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final message in agent?.messages ?? <BridgeAgentMessage>[])
                if (message.text.trim().isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.compact),
                      child: CopyableMessage(
                          message: _messageText(message),
                          showCopyButton: message.role != 'user',
                          copyLabel: l10n.copy,
                          copiedLabel: l10n.copied)),
              if (pending != null)
                AppCard(
                    padding: const EdgeInsets.all(AppSpacing.tileX),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(pending.reason),
                          const SizedBox(height: AppSpacing.compact),
                          CopyableMessage(
                              message: pending.command,
                              copyLabel: l10n.copy,
                              copiedLabel: l10n.copied),
                          Wrap(spacing: AppSpacing.compact, children: [
                            FilledButton(
                                key: const Key('bridge-agent-approve'),
                                onPressed: () => agent!.approveCommand(true),
                                child: Text(l10n.bridgeAgentRunCommand)),
                            TextButton(
                                onPressed: () => agent!.approveCommand(false),
                                child: Text(l10n.bridgeAgentDeclineCommand)),
                          ]),
                        ])),
              if (problem != null) ...[
                Text(problem,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => agent?.send(l10n.bridgeAgentInitialRequest),
                    child: Text(l10n.retry)),
              ],
            ])),
            if (agent != null)
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: TextField(
                        key: const Key('bridge-agent-composer'),
                        controller: _composer,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                            hintText: l10n.bridgeAgentMessageHint),
                        onSubmitted: (_) => _send())),
                IconButton(
                    onPressed: _busy ? null : _send,
                    tooltip: l10n.send,
                    icon: const Icon(Icons.send_rounded)),
              ]),
          ]),
        ),
      )),
    );
  }
}
