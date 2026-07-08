import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../bridge_speech_models.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../responsive/app_responsive_layout.dart';
import '../plugins/speech_plugin_models.dart';
import '../plugins/speech_plugin_registry.dart';
import '../services/audio_recording_service.dart';
import '../services/bridge_realtime_asr_service.dart';
import '../services/cloud_speech_service.dart';
import '../services/speech_input_service.dart';
import '../services/tts_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/new_session_flow.dart';
import '../../l10n/generated/app_localizations.dart';

SpeechStatus? _cachedSpeechStatus;
const String _speechPluginStartCommandKey = 'start_command';
const String _speechPluginStopCommandKey = 'stop_command';

enum _CapabilityTestFeedbackKind { success, error, info }

class _CapabilityTestFeedback {
  const _CapabilityTestFeedback({
    required this.kind,
    required this.message,
  });

  final _CapabilityTestFeedbackKind kind;
  final String message;
}

class _CapabilityPluginOption {
  const _CapabilityPluginOption({
    required this.entry,
    required this.installedPlugin,
  });

  final SpeechPluginRepositoryEntry? entry;
  final InstalledSpeechPlugin? installedPlugin;

  bool get isInstalled => installedPlugin != null;
  String get id => installedPlugin?.manifest.id ?? entry!.id;
  String get name => installedPlugin?.manifest.name ?? entry!.name;
  String get description => entry?.description ?? '';
  List<SpeechPluginCapability> get capabilities =>
      installedPlugin?.manifest.capabilities ?? entry?.capabilities ?? const [];
}

class SpeechSettingsScreen extends StatefulWidget {
  const SpeechSettingsScreen({
    super.key,
    this.client,
    this.debugPlatformOverride,
    this.debugIsWebOverride,
  });

  static const routeName = '/settings/speech';

  final BridgeClient? client;
  final TargetPlatform? debugPlatformOverride;
  final bool? debugIsWebOverride;

  @override
  State<SpeechSettingsScreen> createState() => _SpeechSettingsScreenState();
}

class _SpeechSettingsScreenState extends State<SpeechSettingsScreen> {
  final _whisperApiKeyController = TextEditingController();
  final _whisperBaseUrlController = TextEditingController();
  final Map<String, TextEditingController> _speechPluginApiKeyControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _speechPluginSettingControllers =
      <String, TextEditingController>{};
  final _speakerNameController = TextEditingController();
  final _speakerEnrollmentRecorder = AudioRecordingService();
  final _speechInputService = SpeechInputService();
  final _ttsService = TtsService();
  final _bridgeRealtimeAsrService = BridgeRealtimeAsrService();
  final Set<String> _downloadingModelIds = <String>{};
  final Map<String, String> _downloadErrorsByModelId = <String, String>{};
  final Set<String> _updatingProfileKeys = <String>{};
  final Set<String> _updatingVoiceModelIds = <String>{};
  final Set<String> _deletingModelIds = <String>{};
  final Set<String> _savingPluginConfigurationIds = <String>{};
  final Set<String> _expandedPluginCredentialIds = <String>{};
  final Set<String> _highlightedPluginFieldKeys = <String>{};
  final Map<String, String> _pluginConfigurationErrorsById = <String, String>{};
  final Map<String, _CapabilityTestFeedback> _capabilityTestFeedbackById =
      <String, _CapabilityTestFeedback>{};
  final Map<String, _CapabilityTestFeedback> _pluginSaveFeedbackById =
      <String, _CapabilityTestFeedback>{};
  final Map<String, GlobalKey> _pluginConfigurationCardKeys =
      <String, GlobalKey>{};
  final Map<String, GlobalKey> _pluginConfigurationFieldKeys =
      <String, GlobalKey>{};
  final Map<String, FocusNode> _pluginConfigurationFieldFocusNodes =
      <String, FocusNode>{};
  final Set<String> _hoveredPluginRegistrationUrls = <String>{};
  final ValueNotifier<int> _modelPickerRevision = ValueNotifier<int>(0);
  SpeechProfile? _openModelPickerProfile;

  late TtsProvider _ttsProvider;
  late bool _bridgeLocalTtsStreaming;
  late AsrProvider _asrProvider;
  late bool _speechPlaybackPromptEnabled;
  late bool _callModeAllowInterruptions;
  late int _callModeSpeechPauseMillis;
  late Map<String, String?> _selectedSpeechPluginByCapability;
  late Map<String, String> _speechPluginApiKeysByPluginId;
  late Map<String, Map<String, String>> _speechPluginSettingsByPluginId;
  bool _saving = false;
  bool _speechLoading = false;
  bool _speechPluginLoading = false;
  bool _updatingSpeakerFilter = false;
  bool _speakerEnrollmentRecording = false;
  bool _speakerEnrollmentSaving = false;
  String? _deletingSpeakerId;
  SpeechStatus? _speechStatus;
  SpeechPluginRepositoryIndex? _speechPluginIndex;
  List<InstalledSpeechPlugin> _installedSpeechPlugins = const [];
  List<SpeakerRecord> _speakers = const <SpeakerRecord>[];
  SpeakerFilterSettings _speakerFilter =
      const SpeakerFilterSettings(enabled: false);
  String? _speechStatusError;
  String? _speechPluginError;
  Timer? _speechPollingTimer;

  BridgeClient get _client => widget.client ?? bridgeClient;

  bool get _isWebPlatform => widget.debugIsWebOverride ?? kIsWeb;
  TargetPlatform get _platform =>
      widget.debugPlatformOverride ?? defaultTargetPlatform;

  bool get _systemTtsSupportedOnPlatform {
    if (_isWebPlatform) {
      return true;
    }
    return switch (_platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.linux => false,
      _ => false,
    };
  }

  bool get _systemAsrSupportedOnPlatform {
    if (_isWebPlatform) {
      return true;
    }
    return switch (_platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.linux => false,
      _ => false,
    };
  }

  bool get _ttsProviderSupportedOnCurrentPlatform {
    return switch (_ttsProvider) {
      TtsProvider.system => _systemTtsSupportedOnPlatform,
      TtsProvider.bridgeLocal => true,
    };
  }

  bool get _asrProviderSupportedOnCurrentPlatform {
    return switch (_asrProvider) {
      AsrProvider.system => _systemAsrSupportedOnPlatform,
      AsrProvider.whisper || AsrProvider.bridgeLocal => true,
    };
  }

  List<_CapabilityPluginOption> _pluginOptionsForCapability(
    SpeechPluginCapability capability,
  ) {
    final repositoryEntries = _speechPluginIndex?.plugins ?? const [];
    final installedById = {
      for (final plugin in _installedSpeechPlugins) plugin.manifest.id: plugin,
    };
    final options = repositoryEntries
        .where((entry) => entry.capabilities.contains(capability))
        .map(
          (entry) => _CapabilityPluginOption(
            entry: entry,
            installedPlugin: installedById[entry.id],
          ),
        )
        .toList(growable: true);

    for (final plugin in _installedSpeechPlugins) {
      if (!plugin.manifest.supports(capability) ||
          options.any((item) => item.id == plugin.manifest.id)) {
        continue;
      }
      options.add(
        _CapabilityPluginOption(
          entry: null,
          installedPlugin: plugin,
        ),
      );
    }

    options.sort((left, right) {
      final installCompare =
          (right.isInstalled ? 1 : 0).compareTo(left.isInstalled ? 1 : 0);
      if (installCompare != 0) {
        return installCompare;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return options;
  }

  @override
  void initState() {
    super.initState();
    _syncFromSettings(appSettingsController.settings);
    appSettingsController.addListener(_onSettingsChanged);
    final cachedStatus = _cachedSpeechStatus;
    if (cachedStatus != null) {
      _speechStatus = cachedStatus;
      _syncSpeechPolling(cachedStatus);
      unawaited(_refreshSpeechStatus(silent: true));
    } else {
      unawaited(_refreshSpeechStatus());
    }
    unawaited(_refreshSpeechPlugins());
  }

  @override
  void dispose() {
    appSettingsController.removeListener(_onSettingsChanged);
    _speechPollingTimer?.cancel();
    unawaited(_speakerEnrollmentRecorder.cancel());
    unawaited(_speechInputService.cancel());
    unawaited(_ttsService.stop(notifyCancel: false));
    unawaited(_bridgeRealtimeAsrService.cancel());
    _whisperApiKeyController.dispose();
    _whisperBaseUrlController.dispose();
    for (final controller in _speechPluginApiKeyControllers.values) {
      controller.dispose();
    }
    for (final controller in _speechPluginSettingControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _pluginConfigurationFieldFocusNodes.values) {
      focusNode.dispose();
    }
    _speakerNameController.dispose();
    _modelPickerRevision.dispose();
    super.dispose();
  }

  static const String _pluginApiKeyFieldKey = '__api_key__';

  GlobalKey _pluginConfigurationCardKeyFor(String pluginId) =>
      _pluginConfigurationCardKeys.putIfAbsent(pluginId, GlobalKey.new);

  String _pluginConfigurationFieldCompositeKey(
          String pluginId, String fieldKey) =>
      '$pluginId::$fieldKey';

  GlobalKey _pluginConfigurationFieldKeyFor(String pluginId, String fieldKey) =>
      _pluginConfigurationFieldKeys.putIfAbsent(
        _pluginConfigurationFieldCompositeKey(pluginId, fieldKey),
        GlobalKey.new,
      );

  FocusNode _pluginConfigurationFieldFocusNodeFor(
    String pluginId,
    String fieldKey,
  ) =>
      _pluginConfigurationFieldFocusNodes.putIfAbsent(
        _pluginConfigurationFieldCompositeKey(pluginId, fieldKey),
        FocusNode.new,
      );

  void _syncFromSettings(AppSettings settings) {
    _ttsProvider = switch (settings.ttsProvider) {
      TtsProvider.system => TtsProvider.system,
      TtsProvider.bridgeLocal => TtsProvider.system,
    };
    _bridgeLocalTtsStreaming = settings.bridgeLocalTtsStreaming;
    _asrProvider = switch (settings.asrProvider) {
      AsrProvider.system => AsrProvider.system,
      AsrProvider.bridgeLocal || AsrProvider.whisper => AsrProvider.system,
    };
    _speechPlaybackPromptEnabled = settings.speechPlaybackPromptEnabled;
    _callModeAllowInterruptions = settings.callModeAllowInterruptions;
    _callModeSpeechPauseMillis = settings.callModeSpeechPauseMillis;
    _selectedSpeechPluginByCapability =
        Map<String, String?>.from(settings.selectedSpeechPluginByCapability);
    _speechPluginApiKeysByPluginId =
        Map<String, String>.from(settings.speechPluginApiKeysByPluginId);
    _speechPluginSettingsByPluginId =
        settings.speechPluginSettingsByPluginId.map(
      (key, value) => MapEntry(key, Map<String, String>.from(value)),
    );
    _installedSpeechPlugins = settings.installedSpeechPlugins
        .map((item) {
          try {
            return InstalledSpeechPlugin.fromJson(item);
          } catch (_) {
            return null;
          }
        })
        .whereType<InstalledSpeechPlugin>()
        .toList(growable: false);
    _whisperApiKeyController.text = settings.whisperApiKey;
    _whisperBaseUrlController.text = settings.whisperBaseUrl;
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncFromSettings(appSettingsController.settings);
      _pruneSpeechPluginApiKeyControllers();
      _pruneSpeechPluginSettingControllers();
    });
  }

  Future<void> _startNewSession() async {
    await startNewSessionFlow(context, client: _client);
  }

  TextStyle _formValueTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w400,
        ) ??
        TextStyle(
          fontSize: 14,
          height: 1.45,
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w400,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ttsHelpText = _ttsPlatformHelp(l10n);
    final asrHelpText = _asrPlatformHelp(l10n);
    final formValueTextStyle = _formValueTextStyle(context);
    final useWideDesktop = AppResponsiveLayout.isWideDesktopWidth(
        MediaQuery.sizeOf(context).width);
    final recentProjects = _client.peekProjects() ?? const <ProjectSummary>[];
    final recentSessions = _client.peekSessions() ?? const <SessionSummary>[];
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;
    return AppNavigationScaffold(
      activeRoute: AppRouteKind.settings,
      recentProjects: recentProjects,
      recentSessions: recentSessions,
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      onNavigateHome: () => Navigator.of(context).popUntil(
        (route) => route.settings.name == AppRoutes.home || route.isFirst,
      ),
      onNavigateProjects: () =>
          Navigator.of(context).pushNamed(AppRoutes.projects),
      onNavigateSettings: () => Navigator.of(context).pop(),
      onOpenProject: (project) {
        Navigator.of(context).pushNamed(
          AppRoutes.project(project.id),
          arguments: project,
        );
      },
      onOpenSession: (session) {
        Navigator.of(context).pushNamed(
          AppRoutes.session(session.projectId, session.id),
          arguments: session,
        );
      },
      onNewSession: _startNewSession,
      onNewSessionForProject: (project) => startNewSessionFlow(
        context,
        client: _client,
        initialProject: project,
      ),
      onNewSessionForSession: (session) => startNewSessionFlow(
        context,
        client: _client,
        initialProjects: recentProjects,
        initialProject: _client.peekProject(session.projectId),
      ),
      agentLabelFor: _client.agentLabelFor,
      bodyBuilder: (context, useDesktop, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.card,
            AppSpacing.screenX,
            AppSpacing.block,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: useDesktop ? 1240 : AppSpacing.contentMaxWidth,
                ),
                child: useDesktop && useWideDesktop
                    ? _buildDesktopLayout(
                        context,
                        l10n,
                        formValueTextStyle,
                        ttsHelpText,
                        asrHelpText,
                      )
                    : _buildMobileLayout(
                        context,
                        l10n,
                        formValueTextStyle,
                        ttsHelpText,
                        asrHelpText,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AppLocalizations l10n,
    TextStyle formValueTextStyle,
    String? ttsHelpText,
    String? asrHelpText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, l10n),
        const SizedBox(height: AppSpacing.stackTight),
        ..._buildSpeechSettingSections(
          context,
          l10n,
          formValueTextStyle,
          ttsHelpText,
          asrHelpText,
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    AppLocalizations l10n,
    TextStyle formValueTextStyle,
    String? ttsHelpText,
    String? asrHelpText,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, l10n),
          const SizedBox(height: AppSpacing.card),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildSpeechBridgeSections(
                    context,
                    l10n,
                    formValueTextStyle,
                    ttsHelpText,
                    asrHelpText,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.card),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildSpeechControlSections(
                    context,
                    l10n,
                    formValueTextStyle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSpeechSettingSections(
    BuildContext context,
    AppLocalizations l10n,
    TextStyle formValueTextStyle,
    String? ttsHelpText,
    String? asrHelpText,
  ) {
    return [
      ..._buildSpeechBridgeSections(
        context,
        l10n,
        formValueTextStyle,
        ttsHelpText,
        asrHelpText,
      ),
      const SizedBox(height: AppSpacing.stackTight),
      ..._buildSpeechControlSections(context, l10n, formValueTextStyle),
    ];
  }

  List<Widget> _buildSpeechBridgeSections(
    BuildContext context,
    AppLocalizations l10n,
    TextStyle formValueTextStyle,
    String? ttsHelpText,
    String? asrHelpText,
  ) {
    return [
      _buildSectionCard(
        context,
        title: l10n.speechSection.toUpperCase(),
        children: [
          _buildSpeechRoutingContent(
            context,
            formValueTextStyle: formValueTextStyle,
            ttsHelpText: ttsHelpText,
            asrHelpText: asrHelpText,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.stackTight),
      _buildSectionCard(
        context,
        title: 'SPEECH PLUGINS',
        children: [_buildSpeechPluginContent(context)],
      ),
      const SizedBox(height: AppSpacing.stackTight),
      _buildSectionCard(
        context,
        title: l10n.localBridgeModelsSection.toUpperCase(),
        children: [_buildLocalBridgeContent(context)],
      ),
      if (_ttsProvider == TtsProvider.bridgeLocal) ...[
        const SizedBox(height: AppSpacing.stackTight),
        _buildSectionCard(
          context,
          title: l10n.localBridgeTtsVoiceLabel.toUpperCase(),
          children: [_buildLocalBridgeTtsVoiceContent(context)],
        ),
      ],
    ];
  }

  List<Widget> _buildSpeechControlSections(
    BuildContext context,
    AppLocalizations l10n,
    TextStyle formValueTextStyle,
  ) {
    return [
      _buildSectionCard(
        context,
        title: l10n.callModeSection.toUpperCase(),
        children: [
          _buildCallModeContent(context, formValueTextStyle),
        ],
      ),
      const SizedBox(height: AppSpacing.stackTight),
      _buildSectionCard(
        context,
        title: l10n.whisperApiSection,
        children: [
          TextField(
            controller: _whisperApiKeyController,
            obscureText: true,
            style: formValueTextStyle,
            decoration: InputDecoration(
              labelText: l10n.apiKey,
            ),
          ),
          TextField(
            controller: _whisperBaseUrlController,
            style: formValueTextStyle,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com/v1',
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final useDesktop =
        AppResponsiveLayout.isDesktopWidth(MediaQuery.sizeOf(context).width);
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!useDesktop) ...[
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.compact),
              child: SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.panelDeepFor(theme.brightness),
                    side: BorderSide.none,
                    minimumSize: const Size.square(34),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Open navigation',
                  icon: const Icon(Icons.menu_rounded, size: 18),
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: AppBackHeader(
            title: l10n.speechSection.toUpperCase(),
            titleStyle: titleStyle,
          ),
        ),
        SizedBox(
          width: 72,
          height: 32,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.tileX,
              ),
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? l10n.saving : l10n.save),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.3,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.stackTight),
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _interleave(children),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleDesktopSidebarCollapsed() {
    return toggleDesktopNavigationCollapsed().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  Widget _buildProviderHelpText(
    BuildContext context,
    String text, {
    required bool warning,
  }) {
    final brightness = Theme.of(context).brightness;
    final color = warning
        ? AppColors.warningTextFor(brightness)
        : AppColors.mutedSoftFor(brightness);
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            height: 1.4,
          ),
    );
  }

  Widget _buildSpeechRoutingContent(
    BuildContext context, {
    required TextStyle formValueTextStyle,
    required String? ttsHelpText,
    required String? asrHelpText,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Speech uses the system by default. Install a plugin only for the capabilities that need a custom service.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.mutedSoftFor(brightness),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.compact),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _interleave([
            _buildSpeechRouteCard(
              context,
              capability: SpeechPluginCapability.realtimeAsr,
              title: 'Realtime ASR',
              subtitle:
                  'Mic streaming, live transcripts, and interrupt detection.',
              activeRouteLabel:
                  _activeRouteLabel(SpeechPluginCapability.realtimeAsr),
              builtInHelpText: asrHelpText,
              showBuiltInWarning: (!_systemAsrSupportedOnPlatform &&
                      _asrProvider == AsrProvider.system) ||
                  (!_isWebPlatform &&
                      _platform == TargetPlatform.macOS &&
                      _asrProvider == AsrProvider.system),
              footer:
                  'Good default for on-device dictation and interruption handling.',
            ),
            _buildSpeechRouteCard(
              context,
              capability: SpeechPluginCapability.batchAsr,
              title: 'Batch ASR',
              subtitle:
                  'Recorded clips, uploads, and non-realtime recognition.',
              activeRouteLabel:
                  _activeRouteLabel(SpeechPluginCapability.batchAsr),
              builtInHelpText: null,
              showBuiltInWarning: (!_systemAsrSupportedOnPlatform &&
                      _asrProvider == AsrProvider.system) ||
                  (!_isWebPlatform &&
                      _platform == TargetPlatform.macOS &&
                      _asrProvider == AsrProvider.system),
              footer:
                  'Useful for cloud transcription providers or higher-accuracy offline jobs.',
            ),
            _buildSpeechRouteCard(
              context,
              capability: SpeechPluginCapability.tts,
              title: 'TTS',
              subtitle:
                  'Reply playback, voice output, and spoken call-mode responses.',
              activeRouteLabel: _activeRouteLabel(SpeechPluginCapability.tts),
              builtInHelpText: ttsHelpText,
              showBuiltInWarning: !_systemTtsSupportedOnPlatform &&
                  _ttsProvider == TtsProvider.system,
              footer:
                  'Use a plugin when you want a cloud voice or a local TTS service.',
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.compact),
        _buildSwitchRow(
          context,
          title: context.l10n.speechPlaybackPrompt,
          subtitle: context.l10n.speechPlaybackPromptSubtitle,
          value: _speechPlaybackPromptEnabled,
          onChanged: (value) {
            setState(() {
              _speechPlaybackPromptEnabled = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSpeechRouteCard(
    BuildContext context, {
    required SpeechPluginCapability capability,
    required String title,
    required String subtitle,
    required String activeRouteLabel,
    required String? builtInHelpText,
    required bool showBuiltInWarning,
    String? footer,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final plugin = _selectedInstalledSpeechPlugin(capability);
    final usingPlugin = plugin != null;

    return Material(
      color: AppColors.surfaceDeepFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(color: AppColors.outlineFor(brightness)),
      ),
      child: InkWell(
        onTap: () => _openCapabilitySelection(context, capability),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.tileX,
            vertical: AppSpacing.tileY,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      usingPlugin ? subtitle : (builtInHelpText ?? subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: showBuiltInWarning && !usingPlugin
                            ? AppColors.warningTextFor(brightness)
                            : AppColors.mutedSoftFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.compact,
                          vertical: AppSpacing.micro,
                        ),
                        decoration: BoxDecoration(
                          color: usingPlugin
                              ? AppColors.accentBlueFor(brightness)
                                  .withValues(alpha: 0.12)
                              : AppColors.panelAltFor(brightness),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          activeRouteLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.compact),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.accentBlueFor(brightness),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InstalledSpeechPlugin? _selectedInstalledSpeechPlugin(
    SpeechPluginCapability capability,
  ) {
    final pluginId = _selectedSpeechPluginByCapability[capability.id];
    if (pluginId == null) {
      return null;
    }
    for (final plugin in _installedSpeechPlugins) {
      if (plugin.manifest.id == pluginId) {
        return plugin;
      }
    }
    return null;
  }

  String _activeRouteLabel(SpeechPluginCapability capability) {
    final plugin = _selectedInstalledSpeechPlugin(capability);
    if (plugin != null) {
      return plugin.manifest.name;
    }
    return switch (capability) {
      SpeechPluginCapability.tts => 'System default',
      SpeechPluginCapability.realtimeAsr ||
      SpeechPluginCapability.batchAsr =>
        'System default',
    };
  }

  Widget _buildSpeechPluginContent(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final availablePluginCount = _speechPluginIndex?.plugins.length ?? 0;
    final installedPluginCount = _installedSpeechPlugins.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: AppSpacing.tilePadding,
          decoration: BoxDecoration(
            color: AppColors.surfaceDeepFor(brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
            border: Border.all(color: AppColors.outlineFor(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plugin manifests carry static transport and model metadata. Omni Code stores the local API key plus optional start and stop commands for local services.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.compact),
              Wrap(
                spacing: AppSpacing.compact,
                runSpacing: AppSpacing.compact,
                children: [
                  _buildPluginStatChip(
                    context,
                    icon: Icons.extension_outlined,
                    label: 'Available',
                    value: '$availablePluginCount',
                  ),
                  _buildPluginStatChip(
                    context,
                    icon: Icons.key_outlined,
                    label: 'Installed',
                    value: '$installedPluginCount',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_speechPluginError != null) ...[
          const SizedBox(height: AppSpacing.stack),
          _buildSpeechErrorBanner(context, _speechPluginError!),
        ],
        const SizedBox(height: AppSpacing.stack),
        _buildPluginSubsection(
          context,
          icon: Icons.widgets_outlined,
          title: 'Find plugins',
          description:
              'Install only the plugins you actually need. They will appear in the capability cards above automatically.',
          child: _speechPluginLoading && _speechPluginIndex == null
              ? _buildPluginLoadingState(
                  context,
                  message: 'Loading plugin catalog...',
                )
              : (_speechPluginIndex == null ||
                      _speechPluginIndex!.plugins.isEmpty)
                  ? _buildPluginEmptyState(
                      context,
                      icon: Icons.search_off_rounded,
                      message: 'No speech plugins found.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _speechPluginIndex!.plugins
                          .map(
                            (plugin) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.compact,
                              ),
                              child: _buildSpeechPluginRepositoryCard(
                                context,
                                plugin,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
        ),
        const SizedBox(height: AppSpacing.stack),
        _buildPluginSubsection(
          context,
          icon: Icons.admin_panel_settings_outlined,
          title: 'Installed plugins',
          description:
              'Configure API keys and optional start or stop commands for local services.',
          child: _installedSpeechPlugins.isEmpty
              ? _buildPluginEmptyState(
                  context,
                  icon: Icons.key_off_outlined,
                  message:
                      'Install a plugin first to configure its API key locally.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _installedSpeechPlugins
                      .map(
                        (plugin) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.compact,
                          ),
                          child: _buildSpeechPluginApiKeyCard(context, plugin),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Widget _buildPluginSubsection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.panelAltFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceDeepFor(brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: AppColors.accentBlueFor(brightness),
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.compact),
          child,
        ],
      ),
    );
  }

  Widget _buildPluginStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.micro,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelAltFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.accentBlueFor(brightness),
          ),
          const SizedBox(width: AppSpacing.micro),
          Text(
            '$label ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginEmptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.mutedSoftFor(brightness),
          ),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(brightness),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginLoadingState(
    BuildContext context, {
    required String message,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_rounded,
            size: 16,
            color: AppColors.accentBlueFor(brightness),
          ),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(brightness),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechPluginRepositoryCard(
    BuildContext context,
    SpeechPluginRepositoryEntry plugin,
  ) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final installed = _installedSpeechPlugins.any(
      (item) => item.manifest.id == plugin.id,
    );
    final installedPlugin = _installedSpeechPlugins
        .where((item) => item.manifest.id == plugin.id)
        .firstOrNull;
    final registrationUrl = plugin.registrationUrl.trim().isNotEmpty
        ? plugin.registrationUrl.trim()
        : (installedPlugin?.manifest.registrationUrl.trim() ?? '');

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plugin.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                style: installed
                    ? _pluginSecondaryButtonStyle(context)
                    : _pluginPrimaryButtonStyle(context),
                onPressed: () => installed
                    ? _uninstallSpeechPlugin(plugin.id)
                    : _installSpeechPlugin(plugin),
                child: Text(installed ? 'Uninstall' : 'Install'),
              ),
            ],
          ),
          if (plugin.version.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.micro),
            Text(
              plugin.version,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(brightness),
                height: 1.35,
              ),
            ),
          ],
          if (registrationUrl.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.compact),
            _buildPluginRegistrationLink(
              context,
              registrationUrl,
              label: 'Register',
            ),
          ],
          const SizedBox(height: AppSpacing.micro),
          Wrap(
            spacing: AppSpacing.micro,
            runSpacing: AppSpacing.micro,
            children: plugin.capabilities
                .map(
                  (capability) => _buildCapabilityChip(
                    context,
                    label: _speechPluginCapabilityLabel(capability),
                  ),
                )
                .toList(growable: false),
          ),
          if (installedPlugin != null) ...[
            const SizedBox(height: AppSpacing.compact),
            ...SpeechPluginCapability.values
                .where(installedPlugin.manifest.supports)
                .map(
                  (capability) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.micro),
                    child: _buildSpeechPluginCapabilityLine(
                      context,
                      installedPlugin.manifest,
                      capability,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _openCapabilitySelection(
    BuildContext context,
    SpeechPluginCapability capability,
  ) async {
    final title = _speechPluginCapabilityLabel(capability);

    Future<void> importAndRefresh(StateSetter routeSetState) async {
      const typeGroup = XTypeGroup(
        label: 'Plugin manifest',
        extensions: <String>['json'],
      );
      final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
      if (files.isEmpty) {
        return;
      }
      final file = files.first;
      String content;
      try {
        content = await file.readAsString();
      } catch (err) {
        return;
      }
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final manifest = SpeechPluginManifest.fromJson(decoded);
      if (manifest.id.isEmpty) {
        return;
      }
      try {
        await speechPluginRegistry.installManifest(manifest);
        final installed = await speechPluginRegistry.listInstalled();
        if (!mounted) {
          return;
        }
        setState(() {
          _installedSpeechPlugins = installed;
          _pruneSpeechPluginApiKeyControllers();
        });
        routeSetState(() {});
      } catch (_) {}
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, routeSetState) {
            final options = _pluginOptionsForCapability(capability);
            final selectedPluginId =
                _selectedSpeechPluginByCapability[capability.id];
            return Scaffold(
              appBar: AppBar(
                title: Text(title),
                actions: [
                  TextButton.icon(
                    onPressed: () => importAndRefresh(routeSetState),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentBlueFor(
                        Theme.of(routeContext).brightness,
                      ),
                    ),
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Import'),
                  ),
                ],
              ),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    AppSpacing.card,
                    AppSpacing.screenX,
                    AppSpacing.block,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose system default or pick a plugin for this capability.',
                        style: Theme.of(routeContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: AppColors.mutedSoftFor(
                                Theme.of(routeContext).brightness,
                              ),
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      _buildCapabilityChoiceTile(
                        routeContext,
                        title: 'System default',
                        subtitle:
                            'Use the built-in behavior for this capability.',
                        selected: selectedPluginId == null,
                        onTap: () {
                          setState(() {
                            _selectedSpeechPluginByCapability.remove(
                              capability.id,
                            );
                          });
                          Navigator.of(routeContext).pop();
                        },
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      Expanded(
                        child: ListView.separated(
                          itemCount: options.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.compact),
                          itemBuilder: (context, index) {
                            final option = options[index];
                            return _buildCapabilityPluginOptionTile(
                              routeContext,
                              capability: capability,
                              option: option,
                              selected: selectedPluginId == option.id,
                              onInstalledSelected: () {
                                setState(() {
                                  _selectedSpeechPluginByCapability[
                                      capability.id] = option.id;
                                });
                                Navigator.of(routeContext).pop();
                              },
                              onStateChanged: routeSetState,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _capabilityTestUnavailableReasonFor(
    SpeechPluginCapability capability, {
    InstalledSpeechPlugin? testPlugin,
  }) {
    final selectedPluginId = testPlugin?.manifest.id ??
        _selectedSpeechPluginByCapability[capability.id];
    if (selectedPluginId == null || selectedPluginId.trim().isEmpty) {
      return switch (capability) {
        SpeechPluginCapability.tts when !_systemTtsSupportedOnPlatform =>
          'System default TTS cannot be tested on this platform. Choose a TTS plugin to test playback here.',
        SpeechPluginCapability.realtimeAsr
            when !_systemAsrSupportedOnPlatform =>
          'System realtime ASR cannot be tested on this platform. Choose a realtime ASR plugin to test here.',
        SpeechPluginCapability.batchAsr =>
          'System default does not provide batch ASR testing. Choose a batch ASR plugin to test transcription here.',
        _ => null,
      };
    }

    final plugin = testPlugin ?? _selectedInstalledSpeechPlugin(capability);
    if (plugin == null) {
      return 'The selected plugin is not installed, so it cannot be tested.';
    }
    final config = plugin.manifest.configFor(capability);
    if (config == null) {
      return 'The selected plugin does not expose ${_speechPluginCapabilityLabel(capability)} configuration, so it cannot be tested.';
    }
    final resolvedConfig = _capabilityTestConfigWithOverrides(
      plugin.manifest,
      config,
    );
    final supported = switch (capability) {
      SpeechPluginCapability.tts ||
      SpeechPluginCapability.batchAsr =>
        resolvedConfig.transport == SpeechPluginTransport.openAiCompatible ||
            resolvedConfig.transport ==
                SpeechPluginTransport.bridgeOpenAiCompatible,
      SpeechPluginCapability.realtimeAsr =>
        resolvedConfig.transport == SpeechPluginTransport.realtimeWebsocket,
    };
    if (!supported) {
      final expected = switch (capability) {
        SpeechPluginCapability.tts => 'an OpenAI-compatible TTS endpoint',
        SpeechPluginCapability.batchAsr =>
          'an OpenAI-compatible transcription endpoint',
        SpeechPluginCapability.realtimeAsr => 'a realtime websocket endpoint',
      };
      return 'The current selection does not expose $expected, so testing is unavailable.';
    }

    final requiredMissing = _missingRequiredPluginSetting(
      plugin.manifest,
      capability,
      resolvedConfig,
    );
    if (requiredMissing != null) {
      return 'The current selection is missing ${requiredMissing.label}, so testing is unavailable.';
    }
    if (capability == SpeechPluginCapability.realtimeAsr) {
      final websocketUrl = resolvedConfig.websocketUrl?.trim() ?? '';
      if (websocketUrl.isEmpty) {
        return 'The current selection is missing a realtime websocket URL, so testing is unavailable.';
      }
      final uri = Uri.tryParse(websocketUrl);
      if (uri == null ||
          (uri.scheme != 'ws' && uri.scheme != 'wss') ||
          (uri.host.isEmpty)) {
        return 'The current selection has an invalid realtime websocket URL, so testing is unavailable.';
      }
      if (uri.path.toLowerCase().contains('nostream')) {
        return 'The current selection points to a non-streaming endpoint, so testing is unavailable. Configure a realtime websocket URL first.';
      }
    }
    return null;
  }

  SpeechPluginCapabilityConfig _capabilityTestConfigWithOverrides(
    SpeechPluginManifest manifest,
    SpeechPluginCapabilityConfig base,
  ) {
    final overrides = _speechPluginSettingsByPluginId[manifest.id] ?? const {};
    return base.copyWith(
      model: overrides[SpeechPluginSettingFieldKey.model.id] ?? base.model,
      baseUrl:
          overrides[SpeechPluginSettingFieldKey.baseUrl.id] ?? base.baseUrl,
      path: overrides[SpeechPluginSettingFieldKey.path.id] ?? base.path,
      websocketUrl: overrides[SpeechPluginSettingFieldKey.websocketUrl.id] ??
          base.websocketUrl,
      authHeader: overrides[SpeechPluginSettingFieldKey.authHeader.id] ??
          base.authHeader,
      authScheme: overrides[SpeechPluginSettingFieldKey.authScheme.id] ??
          base.authScheme,
    );
  }

  SpeechPluginSettingField? _missingRequiredPluginSetting(
    SpeechPluginManifest manifest,
    SpeechPluginCapability capability,
    SpeechPluginCapabilityConfig config,
  ) {
    for (final field in manifest.settingFieldsForCapability(capability)) {
      final value = switch (field.key) {
        SpeechPluginSettingFieldKey.model => config.model.trim(),
        SpeechPluginSettingFieldKey.baseUrl => config.baseUrl.trim(),
        SpeechPluginSettingFieldKey.path => config.path?.trim() ?? '',
        SpeechPluginSettingFieldKey.websocketUrl =>
          config.websocketUrl?.trim() ?? '',
        SpeechPluginSettingFieldKey.resourceId =>
          (_speechPluginSettingsByPluginId[manifest.id]?[field.key.id] ??
                  config.eventMap[field.key.id] ??
                  '')
              .trim(),
        SpeechPluginSettingFieldKey.authHeader =>
          config.authHeader?.trim() ?? '',
        SpeechPluginSettingFieldKey.authScheme =>
          config.authScheme?.trim() ?? '',
      };
      if (field.required && value.isEmpty) {
        return field;
      }
    }
    return null;
  }

  Widget _buildCapabilityTestFeedbackBanner(
    BuildContext context,
    _CapabilityTestFeedback feedback,
  ) {
    final brightness = Theme.of(context).brightness;
    final (background, border, textColor, icon) = switch (feedback.kind) {
      _CapabilityTestFeedbackKind.success => (
          AppColors.accentBlueFor(brightness).withValues(alpha: 0.10),
          AppColors.accentBlueFor(brightness).withValues(alpha: 0.26),
          AppColors.accentBlueFor(brightness),
          Icons.check_circle_rounded,
        ),
      _CapabilityTestFeedbackKind.error => (
          AppColors.errorBgFor(brightness),
          AppColors.errorBorderFor(brightness),
          AppColors.errorTextFor(brightness),
          Icons.error_rounded,
        ),
      _CapabilityTestFeedbackKind.info => (
          AppColors.panelAltFor(brightness),
          AppColors.outlineFor(brightness),
          Theme.of(context).colorScheme.onSurface,
          Icons.info_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.compact,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: SelectableText(
              feedback.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _setCapabilityTestFeedback(
    SpeechPluginCapability capability,
    _CapabilityTestFeedback feedback,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _capabilityTestFeedbackById[capability.id] = feedback;
    });
  }

  AppSettings _temporaryTestSettingsForCapability(
    SpeechPluginCapability capability, {
    String? pluginId,
  }) {
    final selected = Map<String, String?>.from(
      appSettingsController.settings.selectedSpeechPluginByCapability,
    );
    final selectedPluginId =
        pluginId ?? _selectedSpeechPluginByCapability[capability.id];
    if (selectedPluginId == null || selectedPluginId.trim().isEmpty) {
      selected.remove(capability.id);
    } else {
      selected[capability.id] = selectedPluginId.trim();
    }
    return appSettingsController.settings.copyWith(
      ttsProvider: TtsProvider.system,
      asrProvider: AsrProvider.system,
      installedSpeechPlugins: _installedSpeechPlugins
          .map((item) => item.toJson())
          .toList(growable: false),
      selectedSpeechPluginByCapability: selected,
      speechPluginApiKeysByPluginId: Map<String, String>.from(
        _speechPluginApiKeysByPluginId,
      ),
      speechPluginSettingsByPluginId: _speechPluginSettingsByPluginId.map(
        (key, value) => MapEntry(key, Map<String, String>.from(value)),
      ),
    );
  }

  Future<T> _runWithTemporaryTestSettings<T>(
    SpeechPluginCapability capability,
    Future<T> Function() action, {
    String? pluginId,
  }) async {
    appSettingsController.pushEphemeralSettings(
      _temporaryTestSettingsForCapability(capability, pluginId: pluginId),
    );
    try {
      return await action();
    } finally {
      appSettingsController.popEphemeralSettings();
    }
  }

  Future<void> _savePluginConfiguration(String pluginId) async {
    setState(() {
      _savingPluginConfigurationIds.add(pluginId);
      _pluginSaveFeedbackById[pluginId] = const _CapabilityTestFeedback(
        kind: _CapabilityTestFeedbackKind.info,
        message: 'Saving plugin settings...',
      );
    });
    try {
      final next = appSettingsController.settings.copyWith(
        ttsProvider: TtsProvider.system,
        bridgeLocalTtsStreaming: false,
        asrProvider: AsrProvider.system,
        speechPlaybackPromptEnabled: _speechPlaybackPromptEnabled,
        callModeAllowInterruptions: _callModeAllowInterruptions,
        callModeSpeechPauseMillis: _callModeSpeechPauseMillis,
        callModeWakeWordEnabled: false,
        callModeWakeWords: defaultCallModeWakeWords,
        whisperApiKey: _whisperApiKeyController.text.trim(),
        whisperBaseUrl: _whisperBaseUrlController.text.trim(),
        selectedSpeechPluginByCapability: _selectedSpeechPluginByCapability,
        speechPluginApiKeysByPluginId: _speechPluginApiKeysByPluginId,
        speechPluginSettingsByPluginId: _speechPluginSettingsByPluginId,
      );
      await appSettingsController.save(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _pluginSaveFeedbackById[pluginId] = const _CapabilityTestFeedback(
          kind: _CapabilityTestFeedbackKind.success,
          message: 'Saved to settings.',
        );
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
          kind: _CapabilityTestFeedbackKind.error,
          message: 'Failed to save plugin settings.\n\nRaw error:\n$err',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingPluginConfigurationIds.remove(pluginId);
        });
      }
    }
  }

  Future<bool> _savePluginConfigurationAndUse(
    InstalledSpeechPlugin plugin,
    VoidCallback onInstalledSelected,
    StateSetter? onStateChanged,
  ) async {
    await _savePluginConfiguration(plugin.manifest.id);
    if (!mounted) {
      return false;
    }
    final missing = _missingPluginFields(plugin.manifest);
    if (missing.isNotEmpty) {
      await _expandAndHighlightPluginFields(plugin.manifest.id, missing);
      if (!mounted) {
        return false;
      }
      setState(() {
        _pluginConfigurationErrorsById[plugin.manifest.id] =
            'Fill in the required settings below before using this plugin.';
      });
      onStateChanged?.call(() {});
      return false;
    }
    setState(() {
      _pluginConfigurationErrorsById.remove(plugin.manifest.id);
    });
    onStateChanged?.call(() {});
    onInstalledSelected();
    return true;
  }

  Future<void> _showCapabilityTestSheet(
    BuildContext context,
    SpeechPluginCapability capability, {
    String? pluginId,
  }) {
    return switch (capability) {
      SpeechPluginCapability.tts =>
        _showTtsTestSheet(context, pluginId: pluginId),
      SpeechPluginCapability.batchAsr =>
        _showBatchAsrTestSheet(context, pluginId: pluginId),
      SpeechPluginCapability.realtimeAsr =>
        _showRealtimeAsrTestSheet(context, pluginId: pluginId),
    };
  }

  Future<void> _showTtsTestSheet(
    BuildContext context, {
    String? pluginId,
  }) async {
    final controller = TextEditingController(
      text: 'Hello from Omni Code speech settings.',
    );
    final usesSystemDefault = pluginId == null &&
        _selectedSpeechPluginByCapability[SpeechPluginCapability.tts.id] ==
            null;
    final systemUnavailable =
        usesSystemDefault && !_systemTtsSupportedOnPlatform;
    var speaking = false;
    _CapabilityTestFeedback? feedback;
    if (!systemUnavailable) {
      await _ttsService.initialize(
        onStart: () {
          speaking = true;
        },
        onComplete: () {
          speaking = false;
        },
        onCancel: () {
          speaking = false;
        },
        onError: (message) {
          feedback = _CapabilityTestFeedback(
            kind: _CapabilityTestFeedbackKind.error,
            message: message,
          );
        },
      );
    } else {
      feedback = const _CapabilityTestFeedback(
        kind: _CapabilityTestFeedbackKind.error,
        message:
            'System TTS test is not available on this platform. Choose a TTS plugin to test playback here.',
      );
    }
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> play() async {
              if (systemUnavailable) {
                setSheetState(() {
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message:
                        'System TTS test is not available on this platform. Choose a TTS plugin to test playback here.',
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.tts,
                  feedback!,
                );
                return;
              }
              setSheetState(() {
                feedback = const _CapabilityTestFeedback(
                  kind: _CapabilityTestFeedbackKind.info,
                  message: 'Starting playback test...',
                );
              });
              try {
                await _runWithTemporaryTestSettings(
                  SpeechPluginCapability.tts,
                  () async {
                    await _ttsService.initialize(
                      onStart: () {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            speaking = true;
                          });
                        }
                      },
                      onComplete: () {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            speaking = false;
                          });
                        }
                      },
                      onCancel: () {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            speaking = false;
                          });
                        }
                      },
                      onError: (message) {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            speaking = false;
                            feedback = _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.error,
                              message: message,
                            );
                          });
                        }
                      },
                    );
                    await _ttsService.speak(controller.text);
                  },
                  pluginId: pluginId,
                );
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.success,
                    message: 'Playback started successfully.',
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.tts,
                  feedback!,
                );
              } catch (err) {
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {
                  speaking = false;
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: '$err',
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.tts,
                  feedback!,
                );
              }
            }

            return AlertDialog(
              title: const Text('Test TTS'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        systemUnavailable
                            ? 'System default TTS cannot be tested on this platform.'
                            : 'TTS test uses your current saved speech configuration.',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      TextField(
                        controller: controller,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Test text',
                        ),
                      ),
                      if (feedback != null) ...[
                        const SizedBox(height: AppSpacing.compact),
                        _buildCapabilityTestFeedbackBanner(
                          sheetContext,
                          feedback!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: speaking
                      ? () async {
                          await _ttsService.stop();
                          if (!sheetContext.mounted) {
                            return;
                          }
                          setSheetState(() {
                            speaking = false;
                          });
                        }
                      : null,
                  child: const Text('Stop'),
                ),
                FilledButton(
                  onPressed: speaking || systemUnavailable ? null : play,
                  child: Text(speaking ? 'Playing...' : 'Play'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showBatchAsrTestSheet(
    BuildContext context, {
    String? pluginId,
  }) async {
    final recorder = AudioRecordingService();
    String? recordingPath;
    var recording = false;
    var transcribing = false;
    String transcript = '';
    _CapabilityTestFeedback? feedback;
    await showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            String normalizeBatchAsrTestError(Object err) {
              final message = '$err';
              if (message.contains('1001') || message.contains('1002')) {
                return 'Authentication or parameter error. '
                    'Check that APPID and API Key (Access Token) are correct.\n\n'
                    'Raw error:\n$message';
              }
              if (message.contains('401') || message.contains('Unauthorized')) {
                return 'Authentication failed. Check that the API Key is correct and enabled for this service.\n\n'
                    'Raw error:\n$message';
              }
              if (message.contains('403') || message.contains('Forbidden')) {
                return 'Access denied. Check that the API Key has permission for the selected Resource ID.\n\n'
                    'Raw error:\n$message';
              }
              return message;
            }

            Future<void> startRecording() async {
              final hasPermission = await recorder.hasPermission();
              if (!hasPermission) {
                setSheetState(() {
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: 'Microphone permission is required.',
                  );
                });
                return;
              }
              try {
                final path = await recorder.start();
                setSheetState(() {
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message:
                        'Recording started. Speak a short sentence, then stop.',
                  );
                  transcript = '';
                  recordingPath = path;
                  recording = true;
                });
              } catch (err) {
                setSheetState(() {
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: '$err',
                  );
                });
              }
            }

            Future<void> stopAndTranscribe() async {
              try {
                final path = await recorder.stop();
                setSheetState(() {
                  recording = false;
                  transcribing = true;
                  recordingPath = path ?? recordingPath;
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message: 'Transcribing recorded audio...',
                  );
                });
                final finalPath = recordingPath;
                if (finalPath == null) {
                  throw Exception('Recording file was not created.');
                }
                final text = await _runWithTemporaryTestSettings(
                  SpeechPluginCapability.batchAsr,
                  () => cloudSpeechService.transcribeAudio(File(finalPath)),
                  pluginId: pluginId,
                );
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {
                  transcribing = false;
                  transcript = text;
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.success,
                    message: 'Transcription succeeded.',
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.batchAsr,
                  _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.success,
                    message: text.trim().isEmpty
                        ? 'Transcription succeeded.'
                        : 'Transcription succeeded: ${text.trim()}',
                  ),
                );
              } catch (err) {
                if (!sheetContext.mounted) {
                  return;
                }
                final message = '$err';
                final friendly = normalizeBatchAsrTestError(message);
                setSheetState(() {
                  recording = false;
                  transcribing = false;
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: friendly,
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.batchAsr,
                  feedback!,
                );
              }
            }

            return AlertDialog(
              title: const Text('Test Batch ASR'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Batch ASR test records a short clip, then transcribes it with your current saved speech configuration.',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: recording || transcribing
                                ? null
                                : startRecording,
                            child: const Text('Record'),
                          ),
                          const SizedBox(width: AppSpacing.compact),
                          TextButton(
                            onPressed: recording ? stopAndTranscribe : null,
                            child: Text(
                              transcribing
                                  ? 'Transcribing...'
                                  : 'Stop & Transcribe',
                            ),
                          ),
                        ],
                      ),
                      if (recording) ...[
                        const SizedBox(height: AppSpacing.compact),
                        const Text(
                          'Recording... speak a short sentence, then stop.',
                        ),
                      ],
                      if (transcript.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.compact),
                        SelectableText(transcript),
                      ],
                      if (feedback != null) ...[
                        const SizedBox(height: AppSpacing.compact),
                        _buildCapabilityTestFeedbackBanner(
                          sheetContext,
                          feedback!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    await recorder.cancel();
  }

  Future<void> _showRealtimeAsrTestSheet(
    BuildContext context, {
    String? pluginId,
  }) async {
    final recorder = AudioRecordingService();
    var listening = false;
    var starting = false;
    String transcript = '';
    String? partial;
    _CapabilityTestFeedback? feedback;
    final useSystem = pluginId == null &&
        _selectedSpeechPluginByCapability[
                SpeechPluginCapability.realtimeAsr.id] ==
            null;
    InstalledSpeechPlugin? testPlugin;
    if (pluginId != null) {
      for (final plugin in _installedSpeechPlugins) {
        if (plugin.manifest.id == pluginId) {
          testPlugin = plugin;
          break;
        }
      }
    }
    final testUnavailableReason = _capabilityTestUnavailableReasonFor(
      SpeechPluginCapability.realtimeAsr,
      testPlugin: testPlugin,
    );
    if (testUnavailableReason != null) {
      feedback = _CapabilityTestFeedback(
        kind: _CapabilityTestFeedbackKind.error,
        message: testUnavailableReason,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            String normalizeRealtimeTestError(Object err) {
              final message = '$err';
              if (message.contains('HTTP status code: 401')) {
                return 'The current service rejected realtime speech authentication. '
                    'Check the selected plugin credentials, especially API Key and Resource ID.\n\n'
                    'Raw error:\n$message';
              }
              if (message.contains('HTTP status code: 403')) {
                return 'The current service refused realtime speech access. '
                    'Check that the API Key is enabled for the selected Volcengine speech resource, '
                    'and that Resource ID exactly matches the purchased duration or concurrent edition.\n\n'
                    'Raw error:\n$message';
              }
              if (message.contains('was not upgraded to websocket') ||
                  message.contains('HTTP status code: 400')) {
                return 'The current service could not start realtime speech. '
                    'This usually means the selected plugin is not exposing a valid realtime websocket endpoint.\n\n'
                    'Raw error:\n$message';
              }
              return message;
            }

            Future<void> startRealtimeTest() async {
              if (testUnavailableReason != null) {
                setSheetState(() {
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: testUnavailableReason,
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.realtimeAsr,
                  feedback!,
                );
                return;
              }
              final hasPermission = await recorder.hasPermission();
              if (!hasPermission) {
                setSheetState(() {
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: 'Microphone permission is required.',
                  );
                });
                return;
              }
              setSheetState(() {
                feedback = const _CapabilityTestFeedback(
                  kind: _CapabilityTestFeedbackKind.info,
                  message: 'Starting realtime speech test...',
                );
                transcript = '';
                partial = null;
                starting = true;
              });
              try {
                if (useSystem) {
                  final ready = await _runWithTemporaryTestSettings(
                    SpeechPluginCapability.realtimeAsr,
                    () => _speechInputService.initialize(
                      onError: (message, _) {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            feedback = _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.error,
                              message: message,
                            );
                            listening = false;
                            starting = false;
                          });
                        }
                      },
                    ),
                    pluginId: pluginId,
                  );
                  if (!ready) {
                    throw Exception('System speech input is not available.');
                  }
                  await _speechInputService.startListening(
                    onResult: (words, isFinal) {
                      if (!sheetContext.mounted) {
                        return;
                      }
                      setSheetState(() {
                        if (isFinal) {
                          transcript = words;
                          partial = null;
                          feedback = const _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: 'Realtime transcript received.',
                          );
                        } else {
                          partial = words;
                          feedback = const _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: 'Realtime speech is coming through.',
                          );
                        }
                      });
                      _setCapabilityTestFeedback(
                        SpeechPluginCapability.realtimeAsr,
                        _CapabilityTestFeedback(
                          kind: _CapabilityTestFeedbackKind.success,
                          message: words.trim().isEmpty
                              ? 'Realtime speech is coming through.'
                              : 'Realtime speech is coming through: ${words.trim()}',
                        ),
                      );
                    },
                  );
                } else {
                  final audioStream = await recorder.startStream();
                  await _runWithTemporaryTestSettings(
                    SpeechPluginCapability.realtimeAsr,
                    () => _bridgeRealtimeAsrService.start(
                      audioStream: audioStream,
                      onUtterance: (utterance) {
                        if (!sheetContext.mounted) {
                          return;
                        }
                        setSheetState(() {
                          if (utterance.isFinal) {
                            transcript = utterance.text;
                            partial = null;
                            feedback = const _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.success,
                              message: 'Realtime transcript received.',
                            );
                          } else {
                            partial = utterance.text;
                            feedback = const _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.success,
                              message: 'Realtime speech is coming through.',
                            );
                          }
                        });
                        _setCapabilityTestFeedback(
                          SpeechPluginCapability.realtimeAsr,
                          _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: utterance.text.trim().isEmpty
                                ? 'Realtime speech is coming through.'
                                : 'Realtime speech is coming through: ${utterance.text.trim()}',
                          ),
                        );
                      },
                      onError: (message) {
                        if (!sheetContext.mounted) {
                          return;
                        }
                        setSheetState(() {
                          feedback = _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.error,
                            message: message,
                          );
                          listening = false;
                          starting = false;
                        });
                      },
                    ),
                    pluginId: pluginId,
                  );
                }
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {
                  starting = false;
                  listening = true;
                  feedback = const _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message: 'Listening now. Speak a short sentence.',
                  );
                });
              } catch (err) {
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: normalizeRealtimeTestError(err),
                  );
                  listening = false;
                  starting = false;
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.realtimeAsr,
                  feedback!,
                );
              }
            }

            Future<void> stopRealtimeTest() async {
              if (useSystem) {
                await _speechInputService.stopListening();
                await _speechInputService.cancel();
              } else {
                await _bridgeRealtimeAsrService.cancel();
                await recorder.cancel();
              }
              if (!sheetContext.mounted) {
                return;
              }
              setSheetState(() {
                listening = false;
                starting = false;
              });
            }

            return AlertDialog(
              title: const Text('Test Realtime ASR'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        testUnavailableReason ??
                            (useSystem
                                ? 'Realtime ASR test uses the current saved system speech input.'
                                : 'Realtime ASR test uses the current saved plugin configuration.'),
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      if ((partial ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.compact),
                        Text(
                          partial!,
                          style: Theme.of(sheetContext).textTheme.bodyMedium,
                        ),
                      ],
                      if (transcript.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.compact),
                        SelectableText(transcript),
                      ],
                      if (feedback != null) ...[
                        const SizedBox(height: AppSpacing.compact),
                        _buildCapabilityTestFeedbackBanner(
                          sheetContext,
                          feedback!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: starting || testUnavailableReason != null
                      ? null
                      : listening
                          ? stopRealtimeTest
                          : startRealtimeTest,
                  child: Text(
                    starting
                        ? 'Starting...'
                        : listening
                            ? 'Stop'
                            : 'Start',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    await _speechInputService.cancel();
    await _bridgeRealtimeAsrService.cancel();
    await recorder.cancel();
  }

  Widget _buildCapabilityChoiceTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Material(
      color: selected
          ? AppColors.accentBlueFor(brightness).withValues(alpha: 0.10)
          : AppColors.surfaceDeepFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(color: AppColors.outlineFor(brightness)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        child: Padding(
          padding: AppSpacing.tilePadding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppColors.accentBlueFor(brightness)
                    : AppColors.mutedSoftFor(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityPluginOptionTile(
    BuildContext context, {
    required SpeechPluginCapability capability,
    required _CapabilityPluginOption option,
    required bool selected,
    required VoidCallback onInstalledSelected,
    required StateSetter onStateChanged,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final pluginError = _pluginConfigurationErrorsById[option.id];
    return Material(
      color: pluginError != null
          ? AppColors.errorBgFor(brightness)
          : option.isInstalled
              ? AppColors.surfaceDeepFor(brightness)
              : AppColors.panelAltFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(
          color: pluginError != null
              ? AppColors.errorBorderFor(brightness)
              : AppColors.outlineFor(brightness),
        ),
      ),
      child: Padding(
        padding: AppSpacing.tilePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        option.description.isNotEmpty
                            ? option.description
                            : option.isInstalled
                                ? 'Installed and ready to use.'
                                : 'Install first before selecting this plugin.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedSoftFor(brightness),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                if (option.isInstalled)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.accentBlueFor(brightness)
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: AppColors.accentBlueFor(brightness),
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                final missing = _missingPluginFields(
                                  option.installedPlugin!.manifest,
                                );
                                if (missing.isNotEmpty) {
                                  unawaited(_expandAndHighlightPluginFields(
                                    option.id,
                                    missing,
                                  ));
                                  setState(() {
                                    _pluginConfigurationErrorsById[option.id] =
                                        'Fill in the required settings below before using this plugin.';
                                  });
                                  onStateChanged(() {});
                                  return;
                                }
                                setState(() {
                                  _pluginConfigurationErrorsById.remove(
                                    option.id,
                                  );
                                });
                                onStateChanged(() {});
                                onInstalledSelected();
                              },
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.compact,
                                  vertical: AppSpacing.micro,
                                ),
                                foregroundColor:
                                    AppColors.accentBlueFor(brightness),
                                textStyle:
                                    theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: const Text('Use'),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: AppColors.mutedSoftFor(brightness),
                                size: 18,
                              ),
                              onSelected: (value) async {
                                if (value == 'uninstall') {
                                  await _uninstallSpeechPlugin(option.id);
                                  if (!mounted) {
                                    return;
                                  }
                                  setState(() {});
                                } else if (value == 'test') {
                                  final missing = _missingPluginFields(
                                    option.installedPlugin!.manifest,
                                  );
                                  if (missing.isNotEmpty) {
                                    unawaited(_expandAndHighlightPluginFields(
                                      option.id,
                                      missing,
                                    ));
                                    setState(() {
                                      _pluginConfigurationErrorsById[
                                              option.id] =
                                          'Fill in the required settings before testing.';
                                    });
                                    onStateChanged(() {});
                                    return;
                                  }
                                  setState(() {
                                    _pluginConfigurationErrorsById.remove(
                                      option.id,
                                    );
                                  });
                                  onStateChanged(() {});
                                  await _showCapabilityTestSheet(
                                    context,
                                    capability,
                                    pluginId: option.id,
                                  );
                                  onStateChanged(() {});
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'test',
                                  child: ListTile(
                                    leading: Icon(Icons.play_arrow_rounded,
                                        size: 20),
                                    title: Text('Test'),
                                    contentPadding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'uninstall',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline_rounded,
                                        size: 20),
                                    title: Text('Uninstall'),
                                    contentPadding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  )
                else
                  FilledButton(
                    onPressed: () async {
                      if (option.entry == null) {
                        return;
                      }
                      await _installSpeechPlugin(option.entry!);
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _pluginConfigurationErrorsById.remove(option.id);
                      });
                      onStateChanged(() {});
                    },
                    style: _pluginPrimaryButtonStyle(context),
                    child: const Text('Install'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.micro),
            Row(
              children: [
                if (!option.isInstalled) ...[
                  Text(
                    'Not installed',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.mutedSoftFor(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.compact),
                ],
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.micro,
                    runSpacing: AppSpacing.micro,
                    children: option.capabilities
                        .map(
                          (item) => _buildCapabilityChip(
                            context,
                            label: _speechPluginCapabilityLabel(item),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
            if (option.isInstalled && option.installedPlugin != null) ...[
              const SizedBox(height: AppSpacing.compact),
              _buildSpeechPluginApiKeyCard(
                context,
                option.installedPlugin!,
                pluginError: pluginError,
                onInstalledSelected: onInstalledSelected,
                onStateChanged: onStateChanged,
                useGlobalKeys: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _missingPluginFields(SpeechPluginManifest manifest) {
    final missing = <String>[];
    final apiKey = _speechPluginApiKeysByPluginId[manifest.id]?.trim() ?? '';
    if (apiKey.isEmpty) {
      missing.add(_pluginApiKeyFieldKey);
    }
    final configured = _speechPluginSettingsByPluginId[manifest.id] ?? const {};
    for (final field in manifest.settingFields) {
      if (!field.required) {
        continue;
      }
      final value = configured[field.key.id]?.trim() ?? '';
      if (value.isEmpty) {
        missing.add(field.key.id);
      }
    }
    return missing;
  }

  Future<void> _expandAndHighlightPluginFields(
    String pluginId,
    List<String> fieldKeys,
  ) async {
    setState(() {
      _expandedPluginCredentialIds.add(pluginId);
      for (final key in fieldKeys) {
        _highlightedPluginFieldKeys.add('$pluginId::$key');
      }
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    final cardContext = _pluginConfigurationCardKeyFor(pluginId).currentContext;
    if (cardContext != null && cardContext.mounted) {
      await Scrollable.ensureVisible(
        cardContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    if (!mounted || fieldKeys.isEmpty) {
      return;
    }
    final firstMissingFieldKey = fieldKeys.first;
    final fieldContext = _pluginConfigurationFieldKeyFor(
      pluginId,
      firstMissingFieldKey,
    ).currentContext;
    if (fieldContext != null && fieldContext.mounted) {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.16,
      );
    }
    if (!mounted) {
      return;
    }
    _pluginConfigurationFieldFocusNodeFor(
      pluginId,
      firstMissingFieldKey,
    ).requestFocus();
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) {
        return;
      }
      setState(() {
        for (final key in fieldKeys) {
          _highlightedPluginFieldKeys.remove('$pluginId::$key');
        }
      });
    });
  }

  void _clearPluginConfigurationError(String pluginId) {
    _pluginConfigurationErrorsById.remove(pluginId);
  }

  Future<void> _runServiceCommand(String pluginId, String command) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'cmd' : 'sh',
        Platform.isWindows ? ['/c', command] : ['-c', command],
      );
      if (!mounted) return;
      setState(() {
        _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
          kind: result.exitCode == 0
              ? _CapabilityTestFeedbackKind.success
              : _CapabilityTestFeedbackKind.error,
          message: result.exitCode == 0
              ? 'Command succeeded: $command'
              : 'Command failed (${result.exitCode}): ${result.stderr}',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
          kind: _CapabilityTestFeedbackKind.error,
          message: '$e',
        );
      });
    }
  }

  Widget _buildSpeechPluginApiKeyCard(
    BuildContext context,
    InstalledSpeechPlugin plugin, {
    String? pluginError,
    VoidCallback? onInstalledSelected,
    StateSetter? onStateChanged,
    bool useGlobalKeys = true,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final controller = _speechPluginApiKeyControllerFor(plugin.manifest.id);
    final savedKey =
        _speechPluginApiKeysByPluginId[plugin.manifest.id]?.trim() ?? '';
    final expanded = _expandedPluginCredentialIds.contains(plugin.manifest.id);
    final statusLabel = savedKey.isEmpty ? 'Missing key' : 'Key saved';
    final saveFeedback = _pluginSaveFeedbackById[plugin.manifest.id];
    final savingPluginConfig =
        _savingPluginConfigurationIds.contains(plugin.manifest.id);
    final highlightApiKey = _highlightedPluginFieldKeys
        .contains('${plugin.manifest.id}::$_pluginApiKeyFieldKey');

    void toggleExpanded() {
      setState(() {
        if (expanded) {
          _expandedPluginCredentialIds.remove(plugin.manifest.id);
        } else {
          _expandedPluginCredentialIds.add(plugin.manifest.id);
        }
      });
      onStateChanged?.call(() {});
    }

    return Material(
      color: AppColors.surfaceDeepFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(
          color: (pluginError ??
                      _pluginConfigurationErrorsById[plugin.manifest.id]) !=
                  null
              ? AppColors.errorBorderFor(brightness)
              : AppColors.outlineFor(brightness),
        ),
      ),
      key: useGlobalKeys
          ? _pluginConfigurationCardKeyFor(plugin.manifest.id)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        onTap: expanded ? null : toggleExpanded,
        child: Padding(
          padding: AppSpacing.tilePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                onTap: toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.micro),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.panelAltFor(brightness),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusControl,
                          ),
                        ),
                        child: Icon(
                          Icons.key_outlined,
                          size: 18,
                          color: AppColors.accentBlueFor(brightness),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.compact),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${plugin.manifest.name} · API Key',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.micro),
                            Wrap(
                              spacing: AppSpacing.micro,
                              runSpacing: AppSpacing.micro,
                              children: [
                                _buildCapabilityChip(
                                  context,
                                  label: statusLabel,
                                ),
                                ...plugin.manifest.capabilities.map(
                                  (capability) => _buildCapabilityChip(
                                    context,
                                    label: _speechPluginCapabilityLabel(
                                      capability,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.compact),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.mutedSoftFor(brightness),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: AppSpacing.compact),
                if ((pluginError ??
                        _pluginConfigurationErrorsById[plugin.manifest.id])
                    case final error?) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.compact,
                      vertical: AppSpacing.compact,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.errorBgFor(brightness),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusControl,
                      ),
                      border: Border.all(
                        color: AppColors.errorBorderFor(brightness),
                      ),
                    ),
                    child: Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.errorTextFor(brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.compact),
                ],
                if (saveFeedback != null) ...[
                  _buildCapabilityTestFeedbackBanner(context, saveFeedback),
                  const SizedBox(height: AppSpacing.compact),
                ],
                if (plugin.manifest.description.isNotEmpty) ...[
                  MarkdownBody(
                    data: plugin.manifest.description,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        color: AppColors.mutedSoftFor(brightness),
                      ),
                      listBullet: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        color: AppColors.mutedSoftFor(brightness),
                      ),
                      code: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        fontFamily: 'monospace',
                        color: AppColors.accentBlueFor(brightness),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.panelAltFor(brightness),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusControl),
                      ),
                      codeblockPadding:
                          const EdgeInsets.all(AppSpacing.compact),
                      blockSpacing: AppSpacing.micro,
                      listIndent: AppSpacing.compact,
                    ),
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        _openPluginRegistrationUrl(href);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.compact),
                ],
                if (plugin.manifest.registrationUrl.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.compact),
                  _buildPluginRegistrationLink(
                    context,
                    plugin.manifest.registrationUrl.trim(),
                    label: 'Get API key',
                  ),
                ],
                ..._buildPluginSettingFields(
                  context,
                  plugin,
                  onStateChanged: onStateChanged,
                  useGlobalKeys: useGlobalKeys,
                ),
                if (plugin.manifest.serviceCommands.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.compact),
                  Row(
                    children: [
                      if (plugin.manifest.serviceCommands['start']
                          case final start?) ...[
                        OutlinedButton.icon(
                          onPressed: () => _runServiceCommand(
                            plugin.manifest.id,
                            start,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('Start Service'),
                        ),
                        const SizedBox(width: AppSpacing.compact),
                      ],
                      if (plugin.manifest.serviceCommands['stop']
                          case final stop?) ...[
                        OutlinedButton(
                          onPressed: () => _runServiceCommand(
                            plugin.manifest.id,
                            stop,
                          ),
                          child: const Text('Stop Service'),
                        ),
                      ],
                    ],
                  ),
                ],
                if (plugin.manifest.requiresApiKey) ...[
                  const SizedBox(height: AppSpacing.compact),
                  KeyedSubtree(
                    key: useGlobalKeys
                        ? _pluginConfigurationFieldKeyFor(
                            plugin.manifest.id,
                            _pluginApiKeyFieldKey,
                          )
                        : null,
                    child: TextField(
                      key: ValueKey<String>(
                        'speech-plugin-field-${plugin.manifest.id}-$_pluginApiKeyFieldKey',
                      ),
                      focusNode: _pluginConfigurationFieldFocusNodeFor(
                        plugin.manifest.id,
                        _pluginApiKeyFieldKey,
                      ),
                      controller: controller,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: plugin.manifest.apiKeyLabel.isNotEmpty
                            ? plugin.manifest.apiKeyLabel
                            : 'API Key',
                        helperText: 'Sent as X-Api-Key.',
                        errorText: highlightApiKey ? 'Required' : null,
                        filled: true,
                        fillColor: highlightApiKey
                            ? AppColors.errorBgFor(brightness)
                            : null,
                      ),
                      onChanged: (value) {
                        final trimmed = value.trim();
                        setState(() {
                          _clearPluginConfigurationError(plugin.manifest.id);
                          if (trimmed.isEmpty) {
                            _speechPluginApiKeysByPluginId.remove(
                              plugin.manifest.id,
                            );
                          } else {
                            _speechPluginApiKeysByPluginId[plugin.manifest.id] =
                                trimmed;
                          }
                          if (trimmed.isNotEmpty) {
                            _highlightedPluginFieldKeys.remove(
                              '${plugin.manifest.id}::$_pluginApiKeyFieldKey',
                            );
                          }
                        });
                        onStateChanged?.call(() {});
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.compact),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: savingPluginConfig
                          ? null
                          : () async {
                              await _savePluginConfiguration(
                                  plugin.manifest.id);
                              onStateChanged?.call(() {});
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.mutedSoftFor(brightness),
                        side: BorderSide(
                          color: AppColors.outlineFor(brightness),
                        ),
                      ),
                      child: Text(
                        savingPluginConfig
                            ? 'Saving...'
                            : 'Save plugin settings',
                      ),
                    ),
                    if (onInstalledSelected != null) ...[
                      const SizedBox(width: AppSpacing.compact),
                      FilledButton(
                        onPressed: savingPluginConfig
                            ? null
                            : () async {
                                await _savePluginConfigurationAndUse(
                                  plugin,
                                  onInstalledSelected,
                                  onStateChanged,
                                );
                              },
                        child: Text(
                          savingPluginConfig ? 'Saving...' : 'Save and use',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeechPluginCapabilityLine(
    BuildContext context,
    SpeechPluginManifest manifest,
    SpeechPluginCapability capability,
  ) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final config = manifest.configFor(capability);
    final transportLabel = config == null
        ? 'unknown'
        : _speechPluginTransportLabel(config.transport);
    final endpointLabel = switch (config?.transport) {
      SpeechPluginTransport.realtimeWebsocket =>
        (config?.websocketUrl?.trim().isNotEmpty ?? false)
            ? 'websocket'
            : 'websocket',
      SpeechPluginTransport.openAiCompatible ||
      SpeechPluginTransport.bridgeOpenAiCompatible =>
        (config?.path?.trim().isNotEmpty ?? false)
            ? config!.path!.trim()
            : 'http',
      SpeechPluginTransport.metadataOnly => 'metadata only',
      null => 'unknown',
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            '${_speechPluginCapabilityLabel(capability)} · $transportLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.compact),
        Text(
          endpointLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.mutedSoftFor(brightness),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPluginSettingFields(
    BuildContext context,
    InstalledSpeechPlugin plugin, {
    StateSetter? onStateChanged,
    bool useGlobalKeys = true,
  }) {
    final fields = plugin.manifest.settingFields;
    if (fields.isEmpty) {
      return const <Widget>[];
    }
    final widgets = <Widget>[
      const SizedBox(height: AppSpacing.compact),
      Text(
        'Additional plugin settings',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    ];
    for (final field in fields) {
      final controller = _speechPluginSettingControllerFor(
        plugin.manifest.id,
        field.key.id,
      );
      final highlighted = _highlightedPluginFieldKeys
          .contains('${plugin.manifest.id}::${field.key.id}');
      widgets.add(const SizedBox(height: AppSpacing.compact));
      widgets.add(
        InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          onTap: () {
            setState(() {
              _expandedPluginCredentialIds.add(plugin.manifest.id);
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.micro),
            child: KeyedSubtree(
              key: useGlobalKeys
                  ? _pluginConfigurationFieldKeyFor(
                      plugin.manifest.id,
                      field.key.id,
                    )
                  : null,
              child: field.options.isEmpty
                  ? TextField(
                      key: ValueKey<String>(
                        'speech-plugin-field-${plugin.manifest.id}-${field.key.id}',
                      ),
                      focusNode: _pluginConfigurationFieldFocusNodeFor(
                        plugin.manifest.id,
                        field.key.id,
                      ),
                      controller: controller,
                      decoration: _pluginSettingInputDecoration(
                        context,
                        field,
                        highlighted: highlighted,
                      ),
                      onChanged: (value) {
                        _setPluginSettingValue(
                          plugin.manifest.id,
                          field.key.id,
                          value,
                          onStateChanged: onStateChanged,
                        );
                      },
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'speech-plugin-field-${plugin.manifest.id}-${field.key.id}',
                      ),
                      initialValue: field.options.any(
                        (option) => option.value == controller.text,
                      )
                          ? controller.text
                          : null,
                      decoration: _pluginSettingInputDecoration(
                        context,
                        field,
                        highlighted: highlighted,
                      ),
                      isExpanded: true,
                      items: field.options
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.value,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(option.label),
                                  if (option.help.isNotEmpty)
                                    Text(
                                      option.help,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.mutedSoftFor(
                                              Theme.of(context).brightness,
                                            ),
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      selectedItemBuilder: (context) => field.options
                          .map(
                            (option) => Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        _setPluginSettingValue(
                          plugin.manifest.id,
                          field.key.id,
                          value ?? '',
                          controller: controller,
                          onStateChanged: onStateChanged,
                        );
                      },
                    ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  InputDecoration _pluginSettingInputDecoration(
    BuildContext context,
    SpeechPluginSettingField field, {
    required bool highlighted,
  }) {
    return InputDecoration(
      labelText: field.required ? '${field.label} *' : field.label,
      hintText: field.placeholder.isNotEmpty ? field.placeholder : null,
      helperText: field.help.isNotEmpty ? field.help : null,
      errorText: highlighted ? 'Required' : null,
      filled: true,
      fillColor: highlighted
          ? AppColors.errorBgFor(Theme.of(context).brightness)
          : null,
    );
  }

  void _setPluginSettingValue(
    String pluginId,
    String fieldKey,
    String value, {
    TextEditingController? controller,
    StateSetter? onStateChanged,
  }) {
    final trimmed = value.trim();
    if (controller != null && controller.text != trimmed) {
      controller.text = trimmed;
    }
    setState(() {
      _clearPluginConfigurationError(pluginId);
      _highlightedPluginFieldKeys.remove('$pluginId::$fieldKey');
    });
    _updateSpeechPluginLocalSetting(pluginId, fieldKey, trimmed);
    onStateChanged?.call(() {});
  }

  Widget _buildCapabilityChip(
    BuildContext context, {
    required String label,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.micro,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelAltFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPluginRegistrationLink(
    BuildContext context,
    String url, {
    required String label,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final hovered = _hoveredPluginRegistrationUrls.contains(url);
    final accent = AppColors.accentBlueFor(brightness);
    final hoverSurface = accent.withValues(
      alpha: brightness == Brightness.dark ? 0.16 : 0.10,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _hoveredPluginRegistrationUrls.add(url);
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredPluginRegistrationUrls.remove(url);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: hovered ? hoverSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
        child: InkWell(
          onTap: () => _openPluginRegistrationUrl(url),
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.compact,
              vertical: AppSpacing.micro,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: accent,
                ),
                const SizedBox(width: AppSpacing.micro),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationThickness: hovered ? 2 : 1,
                        ) ??
                        TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                    child: Text(label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _pluginPrimaryButtonStyle(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.controlTight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      ),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
  }

  ButtonStyle _pluginSecondaryButtonStyle(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      backgroundColor: AppColors.panelAltFor(brightness),
      foregroundColor: theme.colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.controlTight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      ),
      side: BorderSide(color: AppColors.outlineFor(brightness)),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Future<void> _openPluginRegistrationUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _speechPluginCapabilityLabel(SpeechPluginCapability capability) {
    return switch (capability) {
      SpeechPluginCapability.realtimeAsr => 'Realtime ASR',
      SpeechPluginCapability.batchAsr => 'Batch ASR',
      SpeechPluginCapability.tts => 'TTS',
    };
  }

  String _speechPluginTransportLabel(SpeechPluginTransport transport) {
    return switch (transport) {
      SpeechPluginTransport.openAiCompatible => 'OpenAI-compatible HTTP',
      SpeechPluginTransport.bridgeOpenAiCompatible => 'Bridge-compatible WS',
      SpeechPluginTransport.realtimeWebsocket => 'Custom realtime WS',
      SpeechPluginTransport.metadataOnly => 'Metadata only',
    };
  }

  TextEditingController _speechPluginApiKeyControllerFor(String pluginId) {
    return _speechPluginApiKeyControllers.putIfAbsent(pluginId, () {
      return TextEditingController(
        text: _speechPluginApiKeysByPluginId[pluginId] ?? '',
      );
    });
  }

  TextEditingController _speechPluginSettingControllerFor(
    String pluginId,
    String fieldKey,
  ) {
    final storageKey = '$pluginId::$fieldKey';
    return _speechPluginSettingControllers.putIfAbsent(storageKey, () {
      return TextEditingController(
        text: _speechPluginSettingsByPluginId[pluginId]?[fieldKey] ?? '',
      );
    });
  }

  void _pruneSpeechPluginApiKeyControllers() {
    final activePluginIds =
        _installedSpeechPlugins.map((plugin) => plugin.manifest.id).toSet();
    final removedPluginIds = _speechPluginApiKeyControllers.keys
        .where((pluginId) => !activePluginIds.contains(pluginId))
        .toList(growable: false);
    for (final pluginId in removedPluginIds) {
      _speechPluginApiKeyControllers.remove(pluginId)?.dispose();
    }
    for (final plugin in _installedSpeechPlugins) {
      final controller = _speechPluginApiKeyControllers[plugin.manifest.id];
      final expectedValue =
          _speechPluginApiKeysByPluginId[plugin.manifest.id] ?? '';
      if (controller != null && controller.text != expectedValue) {
        controller.text = expectedValue;
      }
    }
  }

  void _pruneSpeechPluginSettingControllers() {
    final activeKeys = <String>{};
    for (final plugin in _installedSpeechPlugins) {
      activeKeys.add('${plugin.manifest.id}::$_speechPluginStartCommandKey');
      activeKeys.add('${plugin.manifest.id}::$_speechPluginStopCommandKey');
      for (final field in plugin.manifest.settingFields) {
        activeKeys.add('${plugin.manifest.id}::${field.key.id}');
      }
    }
    final removedKeys = _speechPluginSettingControllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      _speechPluginSettingControllers.remove(key)?.dispose();
    }
    for (final activeKey in activeKeys) {
      final separator = activeKey.indexOf('::');
      if (separator <= 0) {
        continue;
      }
      final pluginId = activeKey.substring(0, separator);
      final fieldKey = activeKey.substring(separator + 2);
      final controller = _speechPluginSettingControllers[activeKey];
      final expectedValue =
          _speechPluginSettingsByPluginId[pluginId]?[fieldKey] ?? '';
      if (controller != null && controller.text != expectedValue) {
        controller.text = expectedValue;
      }
    }
  }

  void _updateSpeechPluginLocalSetting(
    String pluginId,
    String fieldKey,
    String value,
  ) {
    final trimmed = value.trim();
    setState(() {
      final next = Map<String, String>.from(
        _speechPluginSettingsByPluginId[pluginId] ?? const {},
      );
      if (trimmed.isEmpty) {
        next.remove(fieldKey);
      } else {
        next[fieldKey] = trimmed;
      }
      if (next.isEmpty) {
        _speechPluginSettingsByPluginId.remove(pluginId);
      } else {
        _speechPluginSettingsByPluginId[pluginId] = next;
      }
    });
  }

  Widget _buildLocalBridgeContent(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = _speechStatus;
    final ttsHelp = _ttsPlatformHelp(l10n);
    final asrHelp = _asrPlatformHelp(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.localBridgeSpeechIntro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            height: 1.45,
          ),
        ),
        if (ttsHelp != null || asrHelp != null) ...[
          const SizedBox(height: AppSpacing.compact),
          if (ttsHelp != null)
            _buildProviderHelpText(
              context,
              ttsHelp,
              warning: !_ttsProviderSupportedOnCurrentPlatform,
            ),
          if (ttsHelp != null && asrHelp != null)
            const SizedBox(height: AppSpacing.micro),
          if (asrHelp != null)
            _buildProviderHelpText(
              context,
              asrHelp,
              warning: !_asrProviderSupportedOnCurrentPlatform,
            ),
        ],
        if (_speechStatusError != null) ...[
          const SizedBox(height: AppSpacing.compact),
          _buildSpeechErrorBanner(context, _speechStatusError!),
        ],
        const SizedBox(height: AppSpacing.compact),
        if (_speechLoading && status == null)
          const Center(child: CircularProgressIndicator())
        else if (status != null)
          _buildLocalBridgeModelsPanel(context, status)
        else
          _buildLocalBridgeModelsUnavailable(context),
      ],
    );
  }

  Widget _buildLocalBridgeModelsUnavailable(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.outlineFor(brightness),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.localBridgeModelsUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(brightness),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
          TextButton(
            onPressed: _speechLoading ? null : () => _refreshSpeechStatus(),
            child: Text(_speechLoading ? l10n.refreshing : l10n.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechErrorBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.errorBgFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.errorBorderFor(brightness),
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.errorTextFor(brightness),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildLocalBridgeModelsPanel(
    BuildContext context,
    SpeechStatus status,
  ) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.outlineFor(brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBridgeDetailsTile(context, status),
          const SizedBox(height: AppSpacing.stack),
          ..._localBridgeProfileOrder.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.compact),
              child: _buildProfileSummaryTile(context, status, profile),
            ),
          ),
          _buildInstalledModelsManagement(context, status),
          const SizedBox(height: AppSpacing.compact),
          _buildSpeakerFilterTile(context),
        ],
      ),
    );
  }

  Widget _buildBridgeDetailsTile(BuildContext context, SpeechStatus status) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Material(
      color: AppColors.panelAltFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(color: AppColors.outlineFor(brightness)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.tileX,
            vertical: AppSpacing.micro,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.tileX,
            0,
            AppSpacing.tileX,
            AppSpacing.tileY,
          ),
          title: Text(
            l10n.bridgeDetails,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            _client.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.35,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _speechLoading ? l10n.refreshing : l10n.refresh,
                onPressed: _speechLoading ? null : () => _refreshSpeechStatus(),
                icon: _speechLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          children: [
            _buildBridgeDetailLine(
              context,
              label: l10n.bridgeUrlLabel,
              value: _client.baseUrl,
            ),
            if (status.rootDir.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.compact),
              _buildBridgeDetailLine(
                context,
                label: l10n.localBridgeModelRoot,
                value: status.rootDir,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBridgeDetailLine(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.mutedSoftFor(brightness),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.micro),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildInstalledModelsManagement(
    BuildContext context,
    SpeechStatus status,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final installedModels = status.models
        .where((model) => model.installed && !_isWakeWordModel(model))
        .toList(growable: false)
      ..sort((left, right) {
        final kindComparison = left.kind.name.compareTo(right.kind.name);
        if (kindComparison != 0) {
          return kindComparison;
        }
        return left.displayName.compareTo(right.displayName);
      });

    return Material(
      color: AppColors.panelAltFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        side: BorderSide(color: AppColors.outlineFor(brightness)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.tileX,
            vertical: AppSpacing.micro,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.tileX,
            0,
            AppSpacing.tileX,
            AppSpacing.tileY,
          ),
          title: Text(
            l10n.speechInstalledModels,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            installedModels.isEmpty
                ? l10n.speechNoInstalledModels
                : installedModels
                    .map((model) => model.displayName)
                    .take(2)
                    .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.35,
            ),
          ),
          children: [
            if (installedModels.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.speechNoInstalledModels,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedSoftFor(brightness),
                    height: 1.35,
                  ),
                ),
              )
            else
              for (var index = 0; index < installedModels.length; index++) ...[
                if (index > 0) const SizedBox(height: AppSpacing.micro),
                _buildInstalledModelManagementRow(
                  context,
                  status,
                  installedModels[index],
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledModelManagementRow(
    BuildContext context,
    SpeechStatus status,
    SpeechModelSummary model,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final selectedProfiles = _selectedProfilesForModel(status, model.id);
    final selected = selectedProfiles.isNotEmpty;
    final deleting = _deletingModelIds.contains(model.id);
    final selectedLabel = selectedProfiles
        .map((profile) => _profileLabel(l10n, profile))
        .join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.micro),
              Text(
                selected
                    ? '${_profileSummaryLine(l10n, model)} · $selectedLabel'
                    : _profileSummaryLine(l10n, model),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.compact),
        if (selected)
          Text(
            l10n.speechSelected,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              fontWeight: FontWeight.w700,
            ),
          )
        else
          IconButton.outlined(
            key: ValueKey<String>('delete-installed-model-${model.id}'),
            tooltip: l10n.speechDelete,
            onPressed: deleting ? null : () => _deleteSpeechModel(model.id),
            icon: deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }

  Widget _buildSpeakerFilterTile(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final brightness = theme.brightness;
    final speakerModel = (_speechStatus?.models ?? const <SpeechModelSummary>[])
        .where(
          (model) =>
              model.kind == SpeechModelKind.speaker ||
              model.capabilities.speakerEmbedding == true,
        )
        .firstOrNull;
    final speakerModelDownload = speakerModel == null
        ? null
        : _activeDownloadForModels(_speechStatus!, [speakerModel]);
    final selectedSpeakerId = _speakers.any(
      (speaker) => speaker.id == _speakerFilter.speakerId,
    )
        ? _speakerFilter.speakerId
        : null;
    final enabled = _speakerFilter.enabled && selectedSpeakerId != null;

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.panelAltFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(color: AppColors.outlineFor(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSwitchRow(
            context,
            title: 'Target speaker only',
            subtitle: _speakers.isEmpty
                ? 'Enroll a speaker on the bridge before enabling filtering.'
                : 'Batch ASR will ignore speech that does not match the selected voiceprint.',
            value: enabled,
            onChanged: _speakers.isEmpty || _updatingSpeakerFilter
                ? null
                : (value) => _updateSpeakerFilter(
                      enabled: value,
                      speakerId: selectedSpeakerId ?? _speakers.first.id,
                      threshold: _speakerFilter.threshold,
                    ),
          ),
          if (speakerModel != null) ...[
            const SizedBox(height: AppSpacing.compact),
            Row(
              children: [
                Expanded(
                  child: Text(
                    speakerModel.installed
                        ? 'Voiceprint model installed'
                        : 'Voiceprint model is required',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedSoftFor(brightness),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                if (!speakerModel.installed)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, 36),
                      maximumSize: const Size(140, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.compact,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: speakerModelDownload != null ||
                            _downloadingModelIds.contains(speakerModel.id)
                        ? null
                        : () => _downloadSpeechModel(speakerModel.id),
                    child: Text(
                      speakerModelDownload != null ||
                              _downloadingModelIds.contains(speakerModel.id)
                          ? 'Downloading'
                          : 'Download',
                    ),
                  ),
              ],
            ),
          ],
          if (speakerModel?.installed == true) ...[
            const SizedBox(height: AppSpacing.compact),
            TextField(
              controller: _speakerNameController,
              enabled:
                  !_speakerEnrollmentRecording && !_speakerEnrollmentSaving,
              decoration: const InputDecoration(
                labelText: 'Speaker name',
                hintText: 'My voice',
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _speakerEnrollmentSaving
                    ? null
                    : () => _toggleSpeakerEnrollmentRecording(),
                child: Text(
                  _speakerEnrollmentSaving
                      ? 'Saving speaker'
                      : _speakerEnrollmentRecording
                          ? 'Finish enrollment'
                          : 'Record enrollment sample',
                ),
              ),
            ),
          ],
          if (_speakers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.compact),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedSpeakerId ?? _speakers.first.id,
                    decoration: const InputDecoration(labelText: 'Speaker'),
                    items: _speakers
                        .map(
                          (speaker) => DropdownMenuItem<String>(
                            value: speaker.id,
                            child: Text(
                              speaker.name.trim().isEmpty
                                  ? speaker.id
                                  : speaker.name.trim(),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _updatingSpeakerFilter
                        ? null
                        : (speakerId) {
                            if (speakerId == null) {
                              return;
                            }
                            _updateSpeakerFilter(
                              enabled: _speakerFilter.enabled,
                              speakerId: speakerId,
                              threshold: _speakerFilter.threshold,
                            );
                          },
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                IconButton.outlined(
                  key: ValueKey<String>(
                    'delete-speaker-${selectedSpeakerId ?? _speakers.first.id}',
                  ),
                  tooltip: l10n.speechDelete,
                  onPressed:
                      _deletingSpeakerId != null || _updatingSpeakerFilter
                          ? null
                          : () => _deleteSpeaker(
                                selectedSpeakerId ?? _speakers.first.id,
                              ),
                  icon: _deletingSpeakerId != null
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.compact),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: (_speakerFilter.threshold ?? 0.65).clamp(0.4, 0.95),
                    min: 0.4,
                    max: 0.95,
                    divisions: 11,
                    label:
                        '${((_speakerFilter.threshold ?? 0.65) * 100).round()}%',
                    onChanged: _updatingSpeakerFilter
                        ? null
                        : (value) {
                            setState(() {
                              _speakerFilter = SpeakerFilterSettings(
                                enabled: _speakerFilter.enabled,
                                speakerId: _speakerFilter.speakerId,
                                threshold: value,
                              );
                            });
                          },
                    onChangeEnd: _updatingSpeakerFilter
                        ? null
                        : (value) => _updateSpeakerFilter(
                              enabled: _speakerFilter.enabled,
                              speakerId:
                                  selectedSpeakerId ?? _speakers.first.id,
                              threshold: value,
                            ),
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    '${((_speakerFilter.threshold ?? 0.65) * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedSoftFor(brightness),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSummaryTile(
    BuildContext context,
    SpeechStatus status,
    SpeechProfile profile,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final models = _modelsForProfile(status, profile);
    final selectedModel =
        _modelById(status, status.profiles.modelForProfile(profile));
    final displayModel =
        selectedModel ?? (models.isEmpty ? null : models.first);
    final downloadTask = _activeDownloadForModels(status, models);
    final downloadError = _openModelPickerProfile == profile
        ? null
        : _downloadErrorForModels(models);
    final updatingProfile = _isUpdatingSpeechProfile(profile);
    final actionLabel = _profileSummaryActionLabel(
      l10n,
      models: models,
      selectedModel: selectedModel,
      downloadTask: downloadTask,
    );
    final highlighted = selectedModel?.installed ?? false;
    final canOpenSheet =
        models.isNotEmpty && downloadTask == null && !updatingProfile;
    final accent = downloadTask != null
        ? AppColors.accentBlueFor(brightness)
        : highlighted
            ? AppColors.successTextFor(brightness)
            : (displayModel?.installed ?? false)
                ? AppColors.warningTextFor(brightness)
                : AppColors.warningTextFor(brightness);

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.panelAltFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.outlineFor(brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profileLabel(l10n, profile),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      displayModel == null
                          ? l10n.localBridgeNoCompatibleModels
                          : _profileSummaryLine(l10n, displayModel),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              _buildProfileSummaryActionButton(
                context,
                label: actionLabel,
                highlighted: highlighted,
                loading: downloadTask != null || updatingProfile,
                onPressed: canOpenSheet
                    ? () => _showModelPickerSheet(status, profile)
                    : null,
              ),
            ],
          ),
          if (downloadTask?.progress != null) ...[
            const SizedBox(height: AppSpacing.compact),
            LinearProgressIndicator(value: downloadTask!.progress),
            const SizedBox(height: AppSpacing.micro),
            Text(
              '${_downloadStatusLabel(l10n, downloadTask.status)} · ${l10n.speechDownloadProgressPercent((downloadTask.progress! * 100).round())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(brightness),
              ),
            ),
          ] else if (downloadTask != null) ...[
            const SizedBox(height: AppSpacing.compact),
            Text(
              _downloadStatusLabel(l10n, downloadTask.status),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.accentBlueFor(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (downloadError != null) ...[
            const SizedBox(height: AppSpacing.compact),
            Container(
              padding: AppSpacing.tilePadding,
              decoration: BoxDecoration(
                color: AppColors.errorBgFor(brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
                border: Border.all(
                  color: AppColors.errorBorderFor(brightness),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      downloadError,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.errorTextFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.micro),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () {
                      setState(() {
                        for (final model in models) {
                          _downloadErrorsByModelId.remove(model.id);
                        }
                      });
                    },
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSummaryActionButton(
    BuildContext context, {
    required String label,
    required bool highlighted,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    const minSize = Size(0, 38);
    if (loading) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(minimumSize: minSize),
        child: _buildButtonLoadingChild(context, label),
      );
    }
    if (highlighted) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: minSize),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: minSize),
      child: Text(label),
    );
  }

  ButtonStyle _sheetActionButtonStyle({
    required bool filled,
  }) {
    return (filled ? FilledButton.styleFrom : OutlinedButton.styleFrom)(
      minimumSize: const Size(84, 42),
      maximumSize: const Size(140, 42),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.tileX),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool toggleOnTap = false,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.micro),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.compact),
        Switch(value: value, onChanged: onChanged),
      ],
    );
    if (!toggleOnTap || onChanged == null) {
      return content;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
      onTap: () => onChanged(!value),
      child: content,
    );
  }

  Future<void> _showModelPickerSheet(
    SpeechStatus status,
    SpeechProfile profile,
  ) async {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final models = _modelsForProfile(status, profile);
    if (models.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _openModelPickerProfile = profile;
    });

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.panelFor(brightness),
        isScrollControlled: true,
        builder: (sheetContext) {
          final sheetTheme = Theme.of(sheetContext);
          final height = MediaQuery.of(sheetContext).size.height * 0.72;
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return ValueListenableBuilder<int>(
                valueListenable: _modelPickerRevision,
                builder: (sheetContext, _, __) {
                  final currentStatus = _speechStatus ?? status;
                  final currentModels =
                      _modelsForProfile(currentStatus, profile);
                  final selectedModelId =
                      currentStatus.profiles.modelForProfile(profile);

                  return SafeArea(
                    child: SizedBox(
                      height: height,
                      child: Column(
                        children: [
                          _buildModelPickerHeader(
                            sheetContext,
                            l10n,
                            profile,
                            brightness,
                            sheetTheme,
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.block,
                                0,
                                AppSpacing.block,
                                AppSpacing.block,
                              ),
                              itemCount: currentModels.length,
                              itemBuilder: (context, index) {
                                final model = currentModels[index];
                                final selected = selectedModelId == model.id;
                                final downloadTask = _downloadTaskForModel(
                                  currentStatus,
                                  model.id,
                                );
                                return _buildModelPickerItem(
                                  sheetContext,
                                  setSheetState,
                                  l10n,
                                  profile,
                                  model,
                                  selected: selected,
                                  downloadTask: downloadTask,
                                  brightness: brightness,
                                  sheetTheme: sheetTheme,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_openModelPickerProfile == profile) {
            _openModelPickerProfile = null;
          }
        });
      }
    }
  }

  Widget _buildModelPickerHeader(
    BuildContext sheetContext,
    AppLocalizations l10n,
    SpeechProfile profile,
    Brightness brightness,
    ThemeData sheetTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.block,
        AppSpacing.block,
        AppSpacing.block,
        AppSpacing.compact,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileLabel(l10n, profile),
                  style: sheetTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  _profileSubtitle(l10n, profile),
                  style: sheetTheme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedSoftFor(brightness),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildModelPickerItem(
    BuildContext sheetContext,
    StateSetter setSheetState,
    AppLocalizations l10n,
    SpeechProfile profile,
    SpeechModelSummary model, {
    required bool selected,
    required SpeechDownloadTask? downloadTask,
    required Brightness brightness,
    required ThemeData sheetTheme,
  }) {
    final downloadError = _downloadErrorsByModelId[model.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.compact),
      child: Container(
        padding: AppSpacing.tilePadding,
        decoration: BoxDecoration(
          color: AppColors.surfaceDeepFor(brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
          border: Border.all(
            color: selected
                ? AppColors.outlineStrongFor(brightness)
                : AppColors.outlineFor(brightness),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.displayName,
                    style: sheetTheme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.micro),
                  Text(
                    _profileSummaryLine(l10n, model),
                    style: sheetTheme.textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedSoftFor(brightness),
                      height: 1.35,
                    ),
                  ),
                  if (downloadTask != null) ...[
                    const SizedBox(height: AppSpacing.compact),
                    _buildDownloadProgress(sheetContext, downloadTask),
                  ],
                  if (downloadError != null) ...[
                    const SizedBox(height: AppSpacing.compact),
                    Text(
                      downloadError,
                      style: sheetTheme.textTheme.bodySmall?.copyWith(
                        color: AppColors.errorTextFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            _buildModelPickerAction(
              sheetContext,
              setSheetState,
              l10n,
              profile,
              model,
              selected: selected,
              downloadTask: downloadTask,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelPickerAction(
    BuildContext sheetContext,
    StateSetter setSheetState,
    AppLocalizations l10n,
    SpeechProfile profile,
    SpeechModelSummary model, {
    required bool selected,
    required SpeechDownloadTask? downloadTask,
  }) {
    final updateKey = _speechProfileUpdateKey(profile, model.id);
    final selecting = _updatingProfileKeys.contains(updateKey);
    final downloadFailed = downloadTask?.status == SpeechDownloadStatus.failed;
    final downloading = _downloadingModelIds.contains(model.id) ||
        (downloadTask != null && !downloadTask.isTerminal);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 42),
      child: downloading
          ? FilledButton(
              onPressed: null,
              style: _sheetActionButtonStyle(filled: true),
              child: _buildButtonLoadingChild(
                sheetContext,
                l10n.speechDownloading,
              ),
            )
          : selecting
              ? OutlinedButton(
                  onPressed: null,
                  style: _sheetActionButtonStyle(filled: false),
                  child: _buildButtonLoadingChild(
                    sheetContext,
                    l10n.speechSelect,
                  ),
                )
              : !model.installed || downloadFailed
                  ? FilledButton(
                      onPressed: () async {
                        await _downloadSpeechModel(model.id);
                      },
                      style: _sheetActionButtonStyle(filled: true),
                      child: Text(l10n.speechDownload),
                    )
                  : FilledButton.tonal(
                      onPressed: selected
                          ? null
                          : () async {
                              setSheetState(() {});
                              final updated = await _updateSpeechProfile(
                                profile,
                                model.id,
                              );
                              if (!sheetContext.mounted) {
                                return;
                              }
                              if (updated) {
                                Navigator.of(sheetContext).pop();
                              } else {
                                setSheetState(() {});
                              }
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(84, 42),
                        maximumSize: const Size(140, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.tileX,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        selected ? l10n.speechSelected : l10n.speechSelect,
                      ),
                    ),
    );
  }

  Widget _buildButtonLoadingChild(BuildContext context, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.72,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.micro),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadProgress(
    BuildContext context,
    SpeechDownloadTask task,
  ) {
    final l10n = context.l10n;
    final progress = task.progress;
    final statusLabel = _downloadStatusLabel(l10n, task.status);
    final detail = progress == null
        ? statusLabel
        : '$statusLabel · '
            '${l10n.speechDownloadProgressPercent((progress * 100).round())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: AppSpacing.micro),
        Text(
          detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.mutedSoftFor(Theme.of(context).brightness),
              ),
        ),
      ],
    );
  }

  String _profileSummaryLine(
    AppLocalizations l10n,
    SpeechModelSummary model,
  ) {
    final parts = <String>[model.id];
    if (model.downloadSizeMb != null) {
      parts.add('${model.downloadSizeMb} MB');
    }
    if (!model.installed) {
      parts.add(l10n.speechNotInstalled);
    }
    return parts.join(' · ');
  }

  SpeechDownloadTask? _activeDownloadForModels(
    SpeechStatus status,
    List<SpeechModelSummary> models,
  ) {
    final modelIds = models.map((model) => model.id).toSet();
    return status.activeDownloads
        .where((task) => modelIds.contains(task.modelId))
        .fold<SpeechDownloadTask?>(null, _latestDownloadTask);
  }

  SpeechDownloadTask? _downloadTaskForModel(
    SpeechStatus status,
    String modelId,
  ) {
    return status.downloads
        .where((task) => task.modelId == modelId)
        .fold<SpeechDownloadTask?>(null, _latestDownloadTask);
  }

  SpeechDownloadTask? _latestDownloadTask(
    SpeechDownloadTask? current,
    SpeechDownloadTask candidate,
  ) {
    if (current == null || candidate.updatedAt.isAfter(current.updatedAt)) {
      return candidate;
    }
    return current;
  }

  List<SpeechProfile> _selectedProfilesForModel(
    SpeechStatus status,
    String modelId,
  ) {
    final profiles = <SpeechProfile>[];
    for (final profile in _localBridgeProfileOrder) {
      if (status.profiles.modelForProfile(profile) == modelId) {
        profiles.add(profile);
      }
    }
    return profiles;
  }

  String? _downloadErrorForModels(List<SpeechModelSummary> models) {
    for (final model in models) {
      final error = _downloadErrorsByModelId[model.id];
      if (error != null) {
        return error;
      }
      final task = _speechStatus == null
          ? null
          : _downloadTaskForModel(_speechStatus!, model.id);
      if (task?.status == SpeechDownloadStatus.failed) {
        return task?.error?.trim().isNotEmpty == true
            ? task!.error!
            : context.l10n.speechModelDownloadFailed(
                model.id,
                _downloadStatusLabel(context.l10n, SpeechDownloadStatus.failed),
              );
      }
    }
    return null;
  }

  String _profileSummaryActionLabel(
    AppLocalizations l10n, {
    required List<SpeechModelSummary> models,
    required SpeechModelSummary? selectedModel,
    required SpeechDownloadTask? downloadTask,
  }) {
    if (downloadTask != null) {
      if (downloadTask.status == SpeechDownloadStatus.failed) {
        return l10n.speechDownload;
      }
      return _downloadStatusLabel(l10n, downloadTask.status);
    }
    if (selectedModel != null && selectedModel.installed) {
      return models.any((model) => model.id != selectedModel.id)
          ? l10n.speechChange
          : l10n.speechSelected;
    }
    if (models.any((model) => model.installed)) {
      return l10n.speechSelect;
    }
    return l10n.speechDownload;
  }

  Widget _buildLocalBridgeTtsVoiceContent(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final status = _speechStatus;
    final selectedTtsModel =
        status == null ? null : _modelById(status, status.profiles.ttsDefault);
    final ttsVoiceOptions = _ttsVoiceOptions(selectedTtsModel);
    final selectedVoice = _resolvedTtsVoiceSelection(status, selectedTtsModel);

    if (selectedTtsModel == null) {
      return Text(
        l10n.speechNotSelected,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.mutedSoftFor(brightness),
          height: 1.4,
        ),
      );
    }
    final updatingVoice = _updatingVoiceModelIds.contains(selectedTtsModel.id);

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.outlineFor(brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            selectedTtsModel.displayName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            _profileSummaryLine(l10n, selectedTtsModel),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.35,
            ),
          ),
          if (ttsVoiceOptions.length > 1) ...[
            const SizedBox(height: AppSpacing.compact),
            DropdownButtonFormField<String>(
              initialValue: selectedVoice,
              decoration: InputDecoration(
                labelText: l10n.localBridgeTtsVoiceField,
              ),
              items: ttsVoiceOptions
                  .map(
                    (voice) => DropdownMenuItem<String>(
                      value: voice,
                      child: _buildTtsVoiceMenuItem(
                        context,
                        l10n,
                        selectedTtsModel,
                        voice,
                      ),
                    ),
                  )
                  .toList(growable: false),
              selectedItemBuilder: (context) => ttsVoiceOptions
                  .map(
                    (voice) => SizedBox(
                      width: _ttsVoiceLabelWidth(context),
                      child: Text(
                        _ttsVoiceCompactLabel(
                          l10n,
                          selectedTtsModel,
                          voice,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: updatingVoice
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      unawaited(
                        _updateTtsModelVoice(selectedTtsModel.id, value),
                      );
                    },
            ),
          ],
          const SizedBox(height: AppSpacing.compact),
          _buildSwitchRow(
            context,
            title: l10n.localBridgeTtsStreamingLabel,
            subtitle: l10n.localBridgeTtsStreamingHelp,
            value: _bridgeLocalTtsStreaming,
            onChanged: (value) {
              setState(() {
                _bridgeLocalTtsStreaming = value;
              });
            },
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            l10n.localBridgeTtsVoiceHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallModeContent(
    BuildContext context,
    TextStyle formValueTextStyle,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Container(
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
        border: Border.all(
          color: AppColors.outlineFor(brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.callModeAllowInterruptionsLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      l10n.callModeAllowInterruptionsHelp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedSoftFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Switch(
                value: _callModeAllowInterruptions,
                onChanged: (value) {
                  setState(() {
                    _callModeAllowInterruptions = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.compact),
          DropdownButtonFormField<int>(
            initialValue: _callModeSpeechPauseMillis,
            style: formValueTextStyle,
            decoration: InputDecoration(
              labelText: l10n.callModeSpeechPauseLabel,
              helperText: l10n.callModeSpeechPauseHelp,
            ),
            items: _callModeSpeechPauseOptions
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text(
                      l10n.callModeSpeechPauseOption(
                        (value / 1000).toStringAsFixed(1),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _callModeSpeechPauseMillis = value;
              });
            },
          ),
        ],
      ),
    );
  }

  String? _ttsPlatformHelp(AppLocalizations l10n) {
    if (!_systemTtsSupportedOnPlatform && !_isWebPlatform) {
      return switch (_platform) {
        TargetPlatform.linux => l10n.systemTtsUnavailableOnLinux,
        _ => l10n.speechSystemPreferredHelp,
      };
    }
    return l10n.speechSystemPreferredHelp;
  }

  String? _asrPlatformHelp(AppLocalizations l10n) {
    if (!_systemAsrSupportedOnPlatform && !_isWebPlatform) {
      return switch (_platform) {
        TargetPlatform.linux => l10n.systemAsrUnavailableOnLinux,
        _ => l10n.speechSystemPreferredHelp,
      };
    }
    if (_platform == TargetPlatform.macOS && !_isWebPlatform) {
      return l10n.systemAsrMacosPermissionHint;
    }
    return l10n.speechSystemPreferredHelp;
  }

  List<Widget> _interleave(List<Widget> children) {
    if (children.isEmpty) {
      return const [];
    }
    final result = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        result.add(const SizedBox(height: AppSpacing.compact));
      }
      result.add(children[index]);
    }
    return result;
  }

  Future<void> _refreshSpeechStatus({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _speechLoading = true;
        _speechStatusError = null;
      });
    }

    try {
      final status = await _client.getSpeechStatus();
      var speakers = _speakers;
      var speakerFilter = _speakerFilter;
      try {
        speakers = await _client.listSpeakers();
        speakerFilter = await _client.getSpeakerFilter();
      } catch (_) {
        // Older bridge builds do not expose speaker filtering endpoints yet.
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _speechLoading = false;
        _speechStatus = status;
        _speakers = speakers;
        _speakerFilter = speakerFilter;
        _speechStatusError = null;
      });
      _modelPickerRevision.value++;
      _cachedSpeechStatus = status;
      _syncSpeechPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechLoading = false;
        _speechStatusError = l10n.speechLocalModelsLoadFailed(error.toString());
      });
      _syncSpeechPolling(null);
    }
  }

  void _syncSpeechPolling(SpeechStatus? status) {
    final shouldPoll = status?.activeDownloads.isNotEmpty == true;
    if (!shouldPoll) {
      _speechPollingTimer?.cancel();
      _speechPollingTimer = null;
      return;
    }
    _speechPollingTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshSpeechStatus(silent: true));
    });
  }

  Future<void> _refreshSpeechPlugins() async {
    setState(() {
      _speechPluginLoading = true;
      _speechPluginError = null;
    });
    try {
      final indexes = await speechPluginRegistry.fetchRepositoryIndexes();
      final installed = await speechPluginRegistry.listInstalled();
      if (!mounted) {
        return;
      }
      setState(() {
        _speechPluginIndex = SpeechPluginRepositoryIndex(
          source: const SpeechPluginSource(
            id: 'aggregated',
            name: 'Aggregated',
            indexUrl: '',
          ),
          plugins:
              indexes.expand((index) => index.plugins).toList(growable: false),
        );
        _installedSpeechPlugins = installed;
        _pruneSpeechPluginApiKeyControllers();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechPluginError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _speechPluginLoading = false;
        });
      }
    }
  }

  Future<void> _installSpeechPlugin(
    SpeechPluginRepositoryEntry entry,
  ) async {
    setState(() {
      _speechPluginError = null;
    });
    try {
      await speechPluginRegistry.installFromRepositoryEntry(entry);
      final installed = await speechPluginRegistry.listInstalled();
      if (!mounted) {
        return;
      }
      setState(() {
        _installedSpeechPlugins = installed;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechPluginError = error.toString();
      });
    }
  }

  Future<void> _uninstallSpeechPlugin(String pluginId) async {
    setState(() {
      _speechPluginError = null;
    });
    try {
      await speechPluginRegistry.uninstall(pluginId);
      final installed = await speechPluginRegistry.listInstalled();
      if (!mounted) {
        return;
      }
      setState(() {
        _installedSpeechPlugins = installed;
        _selectedSpeechPluginByCapability.removeWhere(
          (_, value) => value == pluginId,
        );
        _speechPluginApiKeysByPluginId.remove(pluginId);
        _pruneSpeechPluginApiKeyControllers();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechPluginError = error.toString();
      });
    }
  }

  Future<void> _downloadSpeechModel(String modelId) async {
    setState(() {
      _downloadingModelIds.add(modelId);
      _downloadErrorsByModelId.remove(modelId);
      _speechStatusError = null;
    });
    _modelPickerRevision.value++;
    try {
      final task = await _client.createSpeechDownload(modelId);
      if (mounted && task.status == SpeechDownloadStatus.failed) {
        final l10n = context.l10n;
        setState(() {
          _downloadErrorsByModelId[modelId] =
              task.error?.trim().isNotEmpty == true
                  ? task.error!
                  : l10n.speechModelDownloadFailed(
                      modelId,
                      _downloadStatusLabel(l10n, task.status),
                    );
        });
      }
      await _refreshSpeechStatus(silent: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadErrorsByModelId[modelId] = _normalizeBridgeDownloadError(
          error,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloadingModelIds.remove(modelId);
        });
        _modelPickerRevision.value++;
      }
    }
  }

  String _normalizeBridgeDownloadError(Object error) {
    final raw = error.toString().trim();
    final statusMatch = RegExp(r'\b(\d{3})\b').firstMatch(raw);
    if (raw.startsWith('Bridge error')) {
      return raw;
    }
    if (statusMatch != null) {
      return 'Bridge error (${statusMatch.group(1)}): $raw';
    }
    return raw;
  }

  Future<void> _deleteSpeechModel(String modelId) async {
    setState(() {
      _deletingModelIds.add(modelId);
      _downloadErrorsByModelId.remove(modelId);
      _speechStatusError = null;
    });
    try {
      await _client.deleteSpeechModel(modelId);
      await _refreshSpeechStatus(silent: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadErrorsByModelId[modelId] = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingModelIds.remove(modelId);
        });
        _modelPickerRevision.value++;
      }
    }
  }

  Future<void> _updateTtsModelVoice(String modelId, String voice) async {
    setState(() {
      _updatingVoiceModelIds.add(modelId);
      _speechStatusError = null;
    });
    try {
      await _client.updateSpeechModelVoice(modelId, voice: voice);
      await _refreshSpeechStatus(silent: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.settingsSaveFailed(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingVoiceModelIds.remove(modelId);
        });
      }
    }
  }

  Future<void> _updateSpeakerFilter({
    required bool enabled,
    required String? speakerId,
    required double? threshold,
  }) async {
    setState(() {
      _updatingSpeakerFilter = true;
      _speechStatusError = null;
    });
    try {
      final settings = await _client.updateSpeakerFilter(
        SpeakerFilterSettings(
          enabled: enabled,
          speakerId: speakerId,
          threshold: threshold,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speakerFilter = settings;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.settingsSaveFailed(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingSpeakerFilter = false;
        });
      }
    }
  }

  Future<void> _toggleSpeakerEnrollmentRecording() async {
    if (_speakerEnrollmentRecording) {
      await _finishSpeakerEnrollmentRecording();
      return;
    }
    try {
      final hasPermission = await _speakerEnrollmentRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _speechStatusError = 'Microphone permission is required.';
        });
        return;
      }
      await _speakerEnrollmentRecorder.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _speakerEnrollmentRecording = true;
        _speechStatusError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.settingsSaveFailed(error.toString());
      });
    }
  }

  Future<void> _finishSpeakerEnrollmentRecording() async {
    setState(() {
      _speakerEnrollmentSaving = true;
      _speechStatusError = null;
    });
    try {
      final path = await _speakerEnrollmentRecorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _speakerEnrollmentRecording = false;
      });
      if (path == null || path.trim().isEmpty) {
        throw Exception('No enrollment audio was recorded.');
      }
      final name = _speakerNameController.text.trim().isEmpty
          ? 'Speaker ${_speakers.length + 1}'
          : _speakerNameController.text.trim();
      final result = await _client.enrollSpeaker(File(path), name: name);
      final speakers = await _client.listSpeakers();
      final settings = await _client.updateSpeakerFilter(
        SpeakerFilterSettings(
          enabled: true,
          speakerId: result.speaker.id,
          threshold: _speakerFilter.threshold,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speakers = speakers;
        _speakerFilter = settings;
        _speakerNameController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.settingsSaveFailed(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _speakerEnrollmentRecording = false;
          _speakerEnrollmentSaving = false;
        });
      }
    }
  }

  String _speechProfileUpdateKey(SpeechProfile profile, String? modelId) {
    return '${profile.name}:${modelId ?? 'clear'}';
  }

  bool _isUpdatingSpeechProfile(SpeechProfile profile) {
    final prefix = '${profile.name}:';
    return _updatingProfileKeys.any((key) => key.startsWith(prefix));
  }

  Future<bool> _updateSpeechProfile(
    SpeechProfile profile,
    String? modelId,
  ) async {
    final updateKey = _speechProfileUpdateKey(profile, modelId);
    setState(() {
      _updatingProfileKeys.add(updateKey);
      _speechStatusError = null;
    });
    try {
      await _client.updateSpeechProfileModel(profile, modelId: modelId);
      await _refreshSpeechStatus(silent: true);
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.speechProfileUpdateFailed(
          _profileLabel(l10n, profile),
          error.toString(),
        );
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _updatingProfileKeys.remove(updateKey);
        });
      }
    }
  }

  List<SpeechModelSummary> _modelsForProfile(
    SpeechStatus status,
    SpeechProfile profile,
  ) {
    final selectedId = status.profiles.modelForProfile(profile);
    final models = status.models
        .where((model) => _profilesForModel(model).contains(profile))
        .toList(growable: false)
      ..sort((left, right) {
        final selectedComparison = (selectedId == right.id ? 1 : 0)
            .compareTo(selectedId == left.id ? 1 : 0);
        if (selectedComparison != 0) {
          return selectedComparison;
        }
        final installedComparison =
            (right.installed ? 1 : 0).compareTo(left.installed ? 1 : 0);
        if (installedComparison != 0) {
          return installedComparison;
        }
        final recommendedComparison =
            (_isRecommendedForProfile(right, profile) ? 1 : 0)
                .compareTo(_isRecommendedForProfile(left, profile) ? 1 : 0);
        if (recommendedComparison != 0) {
          return recommendedComparison;
        }
        return left.displayName.compareTo(right.displayName);
      });
    return models;
  }

  List<SpeechProfile> _profilesForModel(SpeechModelSummary model) {
    final profiles = <SpeechProfile>{
      ...model.supportsProfiles,
      ...model.recommendedProfiles,
      ...model.selectedBy,
    }..remove(SpeechProfile.wakeWordDefault);
    if (profiles.isNotEmpty) {
      final sorted = profiles.toList(growable: false)
        ..sort((left, right) => left.index.compareTo(right.index));
      return sorted;
    }
    return _inferProfilesForModel(model);
  }

  bool _isWakeWordModel(SpeechModelSummary model) {
    return model.kind == SpeechModelKind.wakeWord ||
        model.capabilities.wakeWord;
  }

  List<SpeechProfile> _inferProfilesForModel(SpeechModelSummary model) {
    final profiles = <SpeechProfile>[];
    if (model.kind == SpeechModelKind.asr && model.capabilities.batchAsr) {
      profiles.add(SpeechProfile.asrBatch);
    }
    if ((model.kind == SpeechModelKind.asr &&
            (model.capabilities.realtimeAsr || model.capabilities.streaming)) ||
        model.runtime == SpeechRuntime.streaming) {
      profiles.add(SpeechProfile.asrRealtime);
    }
    if (model.kind == SpeechModelKind.tts &&
        model.capabilities.speechSynthesis) {
      profiles.add(SpeechProfile.ttsDefault);
    }
    if (model.kind == SpeechModelKind.vad || model.capabilities.vad) {
      profiles.add(SpeechProfile.vadDefault);
    }
    return profiles;
  }

  bool _isRecommendedForProfile(
    SpeechModelSummary model,
    SpeechProfile profile,
  ) {
    return model.recommendedProfiles.contains(profile);
  }

  List<String> _ttsVoiceOptions(SpeechModelSummary? model) {
    if (model == null) {
      return const <String>[];
    }
    final values = <String>{
      if (model.defaultVoice?.trim().isNotEmpty == true)
        model.defaultVoice!.trim(),
      ...model.voices
          .map((voice) => voice.trim())
          .where((voice) => voice.isNotEmpty),
    };
    final sorted = values.toList(growable: false)
      ..sort((left, right) => left.compareTo(right));
    return sorted;
  }

  String? _resolvedTtsVoiceSelection(
    SpeechStatus? status,
    SpeechModelSummary? model,
  ) {
    final options = _ttsVoiceOptions(model);
    if (options.isEmpty) {
      return null;
    }
    final saved = status?.voices.voiceForModel(model?.id)?.trim() ?? '';
    if (saved.isNotEmpty && options.contains(saved)) {
      return saved;
    }
    final defaultVoice = model?.defaultVoice?.trim();
    if (defaultVoice != null &&
        defaultVoice.isNotEmpty &&
        options.contains(defaultVoice)) {
      return defaultVoice;
    }
    return options.first;
  }

  String _ttsVoiceLabel(
    AppLocalizations l10n,
    SpeechModelSummary model,
    String voice,
  ) {
    final detail = _voiceDetailForId(model, voice);
    final name = detail?.name.trim();
    final language = detail?.language.trim();
    final accent = detail?.accent?.trim();
    final gender = detail?.gender?.trim();
    final parts = <String>[
      if (name != null && name.isNotEmpty) name,
      if (language != null && language.isNotEmpty)
        _voiceLanguageLabel(l10n, language),
      if (accent != null && accent.isNotEmpty) _voiceAccentLabel(l10n, accent),
      if (gender != null && gender.isNotEmpty) _voiceGenderLabel(l10n, gender),
    ];
    if (parts.isNotEmpty) {
      final label = parts.join(' · ');
      final defaultVoice = model.defaultVoice?.trim();
      if (defaultVoice != null &&
          defaultVoice.isNotEmpty &&
          defaultVoice == voice) {
        return l10n.localBridgeTtsNamedVoiceDefault(label);
      }
      return label;
    }

    final defaultVoice = model.defaultVoice?.trim();
    if (defaultVoice != null &&
        defaultVoice.isNotEmpty &&
        defaultVoice == voice) {
      return l10n.localBridgeTtsVoiceDefault(voice);
    }
    return l10n.localBridgeTtsVoiceOption(voice);
  }

  String _ttsVoiceCompactLabel(
    AppLocalizations l10n,
    SpeechModelSummary model,
    String voice,
  ) {
    final detail = _voiceDetailForId(model, voice);
    final name = detail?.name.trim();
    final language = detail?.language.trim();
    if (name != null && name.isNotEmpty) {
      final defaultVoice = model.defaultVoice?.trim();
      final suffix = language != null && language.isNotEmpty
          ? ' · ${_voiceLanguageLabel(l10n, language)}'
          : '';
      final label = '$name$suffix';
      if (defaultVoice != null &&
          defaultVoice.isNotEmpty &&
          defaultVoice == voice) {
        return l10n.localBridgeTtsNamedVoiceDefault(label);
      }
      return label;
    }
    return _ttsVoiceLabel(l10n, model, voice);
  }

  Widget _buildTtsVoiceMenuItem(
    BuildContext context,
    AppLocalizations l10n,
    SpeechModelSummary model,
    String voice,
  ) {
    final theme = Theme.of(context);
    final detail = _voiceDetailForId(model, voice);
    if (detail == null) {
      return Text(_ttsVoiceLabel(l10n, model, voice));
    }
    final primary = _ttsVoiceCompactLabel(l10n, model, voice);
    final meta = <String>[
      if (detail.accent?.trim().isNotEmpty == true &&
          !_voiceAccentMatchesLanguage(
            detail.accent!.trim(),
            detail.language.trim(),
          ))
        _voiceAccentLabel(l10n, detail.accent!.trim()),
      if (detail.gender?.trim().isNotEmpty == true)
        _voiceGenderLabel(l10n, detail.gender!.trim()),
      l10n.localBridgeTtsVoiceId(voice),
    ].join(' · ');
    return SizedBox(
      width: _ttsVoiceLabelWidth(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            meta,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(theme.brightness),
            ),
          ),
        ],
      ),
    );
  }

  double _ttsVoiceLabelWidth(BuildContext context) {
    return (MediaQuery.sizeOf(context).width - 128).clamp(160.0, 420.0);
  }

  SpeechVoiceSummary? _voiceDetailForId(
    SpeechModelSummary model,
    String voice,
  ) {
    for (final detail in model.voiceDetails) {
      if (detail.id.trim() == voice) {
        return detail;
      }
    }
    return null;
  }

  String _voiceLanguageLabel(AppLocalizations l10n, String language) {
    return switch (language.toLowerCase()) {
      'zh' => l10n.speechVoiceLanguageChinese,
      'en' => l10n.speechVoiceLanguageEnglish,
      'zh/en' || 'en/zh' => l10n.speechVoiceLanguageChineseEnglish,
      'ja' => l10n.speechVoiceLanguageJapanese,
      'es' => l10n.speechVoiceLanguageSpanish,
      'fr' => l10n.speechVoiceLanguageFrench,
      'hi' => l10n.speechVoiceLanguageHindi,
      'it' => l10n.speechVoiceLanguageItalian,
      'pt-br' => l10n.speechVoiceLanguagePortugueseBr,
      'unknown' => l10n.speechVoiceLanguageUnknown,
      _ => language,
    };
  }

  String _voiceAccentLabel(AppLocalizations l10n, String accent) {
    return switch (accent.toLowerCase()) {
      'chinese' => l10n.speechVoiceLanguageChinese,
      'english' => l10n.speechVoiceLanguageEnglish,
      'chinese + english' => l10n.speechVoiceLanguageChineseEnglish,
      'american english' => l10n.speechVoiceAccentAmericanEnglish,
      'british english' => l10n.speechVoiceAccentBritishEnglish,
      'spanish' => l10n.speechVoiceLanguageSpanish,
      'french' => l10n.speechVoiceLanguageFrench,
      'hindi' => l10n.speechVoiceLanguageHindi,
      'italian' => l10n.speechVoiceLanguageItalian,
      'japanese' => l10n.speechVoiceLanguageJapanese,
      'brazilian portuguese' => l10n.speechVoiceAccentBrazilianPortuguese,
      _ => accent,
    };
  }

  bool _voiceAccentMatchesLanguage(String accent, String language) {
    String normalized(String value) {
      return value.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '');
    }

    final normalizedAccent = normalized(accent);
    final normalizedLanguage = normalized(language);
    return normalizedAccent == normalizedLanguage ||
        (normalizedLanguage == 'zh' && normalizedAccent == 'chinese') ||
        (normalizedLanguage == 'en' && normalizedAccent == 'english') ||
        (normalizedLanguage == 'zhen' &&
            normalizedAccent == 'chineseenglish') ||
        (normalizedLanguage == 'enzh' &&
            normalizedAccent == 'chineseenglish') ||
        (normalizedLanguage == 'es' && normalizedAccent == 'spanish') ||
        (normalizedLanguage == 'fr' && normalizedAccent == 'french') ||
        (normalizedLanguage == 'hi' && normalizedAccent == 'hindi') ||
        (normalizedLanguage == 'it' && normalizedAccent == 'italian') ||
        (normalizedLanguage == 'ja' && normalizedAccent == 'japanese') ||
        (normalizedLanguage == 'ptbr' &&
            normalizedAccent == 'brazilianportuguese');
  }

  String _voiceGenderLabel(AppLocalizations l10n, String gender) {
    return switch (gender.toLowerCase()) {
      'female' => l10n.speechVoiceGenderFemale,
      'male' => l10n.speechVoiceGenderMale,
      _ => gender,
    };
  }

  SpeechModelSummary? _modelById(SpeechStatus status, String? modelId) {
    if (modelId == null) {
      return null;
    }
    for (final model in status.models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }

  String _profileLabel(AppLocalizations l10n, SpeechProfile profile) {
    return switch (profile) {
      SpeechProfile.asrBatch => l10n.speechProfileBatchAsrTitle,
      SpeechProfile.asrRealtime => l10n.speechProfileRealtimeAsrTitle,
      SpeechProfile.ttsDefault => l10n.speechProfileTtsTitle,
      SpeechProfile.vadDefault => l10n.speechProfileVadTitle,
      SpeechProfile.wakeWordDefault => l10n.speechProfileWakeWordTitle,
    };
  }

  String _profileSubtitle(AppLocalizations l10n, SpeechProfile profile) {
    return switch (profile) {
      SpeechProfile.asrBatch => l10n.speechProfileBatchAsrHelp,
      SpeechProfile.asrRealtime => l10n.speechProfileRealtimeAsrHelp,
      SpeechProfile.ttsDefault => l10n.speechProfileTtsHelp,
      SpeechProfile.vadDefault => l10n.speechProfileVadHelp,
      SpeechProfile.wakeWordDefault => l10n.speechProfileWakeWordHelp,
    };
  }

  String _downloadStatusLabel(
    AppLocalizations l10n,
    SpeechDownloadStatus status,
  ) {
    return switch (status) {
      SpeechDownloadStatus.queued => l10n.speechDownloadStatusQueued,
      SpeechDownloadStatus.downloading => l10n.speechDownloadStatusDownloading,
      SpeechDownloadStatus.extracting => l10n.speechDownloadStatusExtracting,
      SpeechDownloadStatus.verifying => l10n.speechDownloadStatusVerifying,
      SpeechDownloadStatus.completed => l10n.speechDownloadStatusCompleted,
      SpeechDownloadStatus.failed => l10n.speechDownloadStatusFailed,
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final next = appSettingsController.settings.copyWith(
        ttsProvider: TtsProvider.system,
        bridgeLocalTtsStreaming: false,
        asrProvider: AsrProvider.system,
        speechPlaybackPromptEnabled: _speechPlaybackPromptEnabled,
        callModeAllowInterruptions: _callModeAllowInterruptions,
        callModeSpeechPauseMillis: _callModeSpeechPauseMillis,
        callModeWakeWordEnabled: false,
        callModeWakeWords: defaultCallModeWakeWords,
        whisperApiKey: _whisperApiKeyController.text.trim(),
        whisperBaseUrl: _whisperBaseUrlController.text.trim(),
        selectedSpeechPluginByCapability: _selectedSpeechPluginByCapability,
        speechPluginApiKeysByPluginId: _speechPluginApiKeysByPluginId,
        speechPluginSettingsByPluginId: _speechPluginSettingsByPluginId,
      );
      await appSettingsController.save(next);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteSpeaker(String speakerId) async {
    setState(() {
      _deletingSpeakerId = speakerId;
      _speechStatusError = null;
    });
    try {
      await _client.deleteSpeaker(speakerId);
      final speakers = await _client.listSpeakers();
      final speakerFilter = await _client.getSpeakerFilter();
      if (!mounted) {
        return;
      }
      setState(() {
        _speakers = speakers;
        _speakerFilter = speakerFilter;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _speechStatusError = l10n.settingsSaveFailed(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingSpeakerId = null;
        });
      }
    }
  }

  static const List<int> _callModeSpeechPauseOptions = <int>[
    600,
    900,
    1200,
    1500,
    1800,
    2400,
  ];

  static const List<SpeechProfile> _localBridgeProfileOrder = <SpeechProfile>[
    SpeechProfile.asrRealtime,
    SpeechProfile.ttsDefault,
    SpeechProfile.asrBatch,
    SpeechProfile.vadDefault,
  ];
}
