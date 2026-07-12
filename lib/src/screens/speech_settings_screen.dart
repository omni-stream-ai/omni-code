import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String name(String localeTag) =>
      installedPlugin?.manifest.localizedName(localeTag) ??
      entry!.localizedName(localeTag);
  String description(String localeTag) =>
      entry?.localizedDescription(localeTag) ?? '';
  List<SpeechPluginCapability> get capabilities =>
      installedPlugin?.manifest.capabilities ?? entry?.capabilities ?? const [];
}

class SpeechSettingsScreen extends StatefulWidget {
  const SpeechSettingsScreen({
    super.key,
    this.client,
    this.speechPluginRegistry,
    this.debugPlatformOverride,
    this.debugIsWebOverride,
  });

  static const routeName = '/settings/speech';

  final BridgeClient? client;
  final SpeechPluginRegistry? speechPluginRegistry;
  final TargetPlatform? debugPlatformOverride;
  final bool? debugIsWebOverride;

  @override
  State<SpeechSettingsScreen> createState() => _SpeechSettingsScreenState();
}

class _SpeechSettingsScreenState extends State<SpeechSettingsScreen> {
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

  late TtsProvider _ttsProvider;
  late bool _bridgeLocalTtsStreaming;
  late AsrProvider _asrProvider;
  late bool _speechPlaybackPromptEnabled;
  late bool _callModeAllowInterruptions;
  late int _callModeSpeechPauseMillis;
  final TextEditingController _callModeSpeechPauseController =
      TextEditingController();
  String? _callModeSpeechPauseError;
  late Map<String, String?> _selectedSpeechPluginByCapability;
  late Map<String, String> _speechPluginApiKeysByPluginId;
  late Map<String, Map<String, String>> _speechPluginSettingsByPluginId;
  bool _saving = false;
  bool _speechLoading = false;
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
  Timer? _speechPollingTimer;

  BridgeClient get _client => widget.client ?? bridgeClient;
  SpeechPluginRegistry get _speechPluginRegistry =>
      widget.speechPluginRegistry ?? speechPluginRegistry;

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

  String _pluginLocaleTag() {
    return preferredLocaleTagFromSetting(
      appSettingsController.settings.appLanguage,
    );
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

  bool get _showLocalBridgeModelSettings => false;

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
      final localeTag = _pluginLocaleTag();
      return left
          .name(localeTag)
          .toLowerCase()
          .compareTo(right.name(localeTag).toLowerCase());
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
    for (final controller in _speechPluginApiKeyControllers.values) {
      controller.dispose();
    }
    for (final controller in _speechPluginSettingControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _pluginConfigurationFieldFocusNodes.values) {
      focusNode.dispose();
    }
    _callModeSpeechPauseController.dispose();
    _speakerNameController.dispose();
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
    final speechPauseText = settings.callModeSpeechPauseMillis.toString();
    if (_callModeSpeechPauseController.text != speechPauseText) {
      _callModeSpeechPauseController.text = speechPauseText;
    }
    _callModeSpeechPauseError = null;
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
        final viewportHeight = MediaQuery.of(context).size.height;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.card,
            AppSpacing.screenX,
            AppSpacing.block,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
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
      if (_showLocalBridgeModelSettings) ...[
        const SizedBox(height: AppSpacing.stackTight),
        _buildSectionCard(
          context,
          title: l10n.localBridgeModelsSection.toUpperCase(),
          children: [_buildLocalBridgeContent(context)],
        ),
      ],
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
                  tooltip: l10n.openNavigation,
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.speechRoutingSystemDefaultIntro,
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
              title: context.l10n.speechProfileRealtimeAsrTitle,
              subtitle: l10n.realtimeAsrRouteSubtitle,
              activeRouteLabel:
                  _activeRouteLabel(SpeechPluginCapability.realtimeAsr),
              builtInHelpText: asrHelpText,
              showBuiltInWarning: (!_systemAsrSupportedOnPlatform &&
                      _asrProvider == AsrProvider.system) ||
                  (!_isWebPlatform &&
                      _platform == TargetPlatform.macOS &&
                      _asrProvider == AsrProvider.system),
              footer: l10n.realtimeAsrRouteFooter,
            ),
            _buildSpeechRouteCard(
              context,
              capability: SpeechPluginCapability.batchAsr,
              title: context.l10n.speechProfileBatchAsrTitle,
              subtitle: l10n.batchAsrRouteSubtitle,
              activeRouteLabel:
                  _activeRouteLabel(SpeechPluginCapability.batchAsr),
              builtInHelpText: null,
              showBuiltInWarning: (!_systemAsrSupportedOnPlatform &&
                      _asrProvider == AsrProvider.system) ||
                  (!_isWebPlatform &&
                      _platform == TargetPlatform.macOS &&
                      _asrProvider == AsrProvider.system),
              footer: l10n.batchAsrRouteFooter,
            ),
            _buildSpeechRouteCard(
              context,
              capability: SpeechPluginCapability.tts,
              title: context.l10n.speechProfileTtsTitle,
              subtitle: l10n.ttsRouteSubtitle,
              activeRouteLabel: _activeRouteLabel(SpeechPluginCapability.tts),
              builtInHelpText: ttsHelpText,
              showBuiltInWarning: !_systemTtsSupportedOnPlatform &&
                  _ttsProvider == TtsProvider.system,
              footer: l10n.ttsRouteFooter,
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
      return plugin.manifest.localizedName(_pluginLocaleTag());
    }
    return switch (capability) {
      SpeechPluginCapability.tts => context.l10n.systemDefault,
      SpeechPluginCapability.realtimeAsr ||
      SpeechPluginCapability.batchAsr =>
        context.l10n.systemDefault,
    };
  }

  Future<void> _openCapabilitySelection(
    BuildContext context,
    SpeechPluginCapability capability,
  ) async {
    final title = _speechPluginCapabilityLabel(capability);

    Future<void> importAndRefresh(StateSetter routeSetState) async {
      final typeGroup = XTypeGroup(
        label: context.l10n.pluginManifest,
        extensions: <String>['json'],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
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
        await _speechPluginRegistry.installManifest(manifest);
        final installed = await _speechPluginRegistry.listInstalled();
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
                    label: Text(context.l10n.importLabel),
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
                        context.l10n.chooseSpeechCapabilityProvider,
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
                        title: context.l10n.systemDefault,
                        subtitle: context.l10n.systemDefaultCapabilitySubtitle,
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
          context.l10n.systemTtsTestUnavailable,
        SpeechPluginCapability.realtimeAsr
            when !_systemAsrSupportedOnPlatform =>
          context.l10n.systemRealtimeAsrTestUnavailable,
        SpeechPluginCapability.batchAsr =>
          context.l10n.systemBatchAsrTestUnavailable,
        _ => null,
      };
    }

    final plugin = testPlugin ?? _selectedInstalledSpeechPlugin(capability);
    if (plugin == null) {
      return context.l10n.selectedPluginNotInstalled;
    }
    final config = plugin.manifest.configFor(capability);
    if (config == null) {
      return context.l10n.selectedPluginMissingCapabilityConfig(
        _speechPluginCapabilityLabel(capability),
      );
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
        SpeechPluginCapability.tts => context.l10n.expectedTtsEndpoint,
        SpeechPluginCapability.batchAsr =>
          context.l10n.expectedTranscriptionEndpoint,
        SpeechPluginCapability.realtimeAsr =>
          context.l10n.expectedRealtimeWebsocketEndpoint,
      };
      return context.l10n.currentSelectionMissingExpectedEndpoint(expected);
    }

    final requiredMissing = _missingRequiredPluginSetting(
      plugin.manifest,
      capability,
      resolvedConfig,
    );
    if (requiredMissing != null) {
      return context.l10n.currentSelectionMissingRequiredSetting(
        requiredMissing.localizedLabel(_pluginLocaleTag()),
      );
    }
    if (capability == SpeechPluginCapability.realtimeAsr) {
      final websocketUrl = resolvedConfig.websocketUrl?.trim() ?? '';
      if (websocketUrl.isEmpty) {
        return context.l10n.currentSelectionMissingRealtimeWebsocketUrl;
      }
      final uri = Uri.tryParse(websocketUrl);
      if (uri == null ||
          (uri.scheme != 'ws' && uri.scheme != 'wss') ||
          (uri.host.isEmpty)) {
        return context.l10n.currentSelectionInvalidRealtimeWebsocketUrl;
      }
      if (uri.path.toLowerCase().contains('nostream')) {
        return context.l10n.currentSelectionNonStreamingEndpoint;
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
    final l10n = context.l10n;
    if (!_applyCallModeSpeechPauseInput(l10n)) {
      return;
    }
    setState(() {
      _savingPluginConfigurationIds.add(pluginId);
      _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
        kind: _CapabilityTestFeedbackKind.info,
        message: l10n.savingPluginSettings,
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
        selectedSpeechPluginByCapability: _selectedSpeechPluginByCapability,
        speechPluginApiKeysByPluginId: _speechPluginApiKeysByPluginId,
        speechPluginSettingsByPluginId: _speechPluginSettingsByPluginId,
      );
      await appSettingsController.save(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
          kind: _CapabilityTestFeedbackKind.success,
          message: l10n.savedToSettings,
        );
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pluginSaveFeedbackById[pluginId] = _CapabilityTestFeedback(
          kind: _CapabilityTestFeedbackKind.error,
          message: l10n.pluginSettingsSaveFailed(err),
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
            context.l10n.fillRequiredPluginSettings;
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
    final l10n = context.l10n;
    final controller = TextEditingController(
      text: l10n.defaultTtsTestText,
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
      feedback = _CapabilityTestFeedback(
        kind: _CapabilityTestFeedbackKind.error,
        message: l10n.systemTtsTestUnavailable,
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
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: l10n.systemTtsTestUnavailable,
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.tts,
                  feedback!,
                );
                return;
              }
              setSheetState(() {
                feedback = _CapabilityTestFeedback(
                  kind: _CapabilityTestFeedbackKind.info,
                  message: l10n.startingPlaybackTest,
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
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.success,
                    message: l10n.playbackStartedSuccessfully,
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
              title: Text(l10n.testTts),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        systemUnavailable
                            ? l10n.systemDefaultTtsCannotBeTested
                            : l10n.ttsTestUsesCurrentConfiguration,
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      TextField(
                        controller: controller,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: l10n.testText,
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
                  child: Text(l10n.close),
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
                  child: Text(l10n.stop),
                ),
                FilledButton(
                  onPressed: speaking || systemUnavailable ? null : play,
                  child: Text(speaking ? l10n.playing : l10n.play),
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
    final l10n = context.l10n;
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
                return l10n.batchAsrAuthOrParameterError(message);
              }
              if (message.contains('401') || message.contains('Unauthorized')) {
                return l10n.batchAsrAuthenticationFailed(message);
              }
              if (message.contains('403') || message.contains('Forbidden')) {
                return l10n.batchAsrAccessDenied(message);
              }
              return message;
            }

            Future<void> startRecording() async {
              final hasPermission = await recorder.hasPermission();
              if (!hasPermission) {
                setSheetState(() {
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: l10n.microphonePermissionRequired,
                  );
                });
                return;
              }
              try {
                final path = await recorder.start();
                setSheetState(() {
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message: l10n.recordingStartedSpeakThenStop,
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
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message: l10n.transcribingRecordedAudio,
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
                    message: l10n.transcriptionSucceeded,
                  );
                });
                _setCapabilityTestFeedback(
                  SpeechPluginCapability.batchAsr,
                  _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.success,
                    message: text.trim().isEmpty
                        ? l10n.transcriptionSucceeded
                        : l10n.transcriptionSucceededWithText(text.trim()),
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
              title: Text(l10n.testBatchAsr),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.batchAsrTestDescription,
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: recording || transcribing
                                ? null
                                : startRecording,
                            child: Text(l10n.record),
                          ),
                          const SizedBox(width: AppSpacing.compact),
                          TextButton(
                            onPressed: recording ? stopAndTranscribe : null,
                            child: Text(
                              transcribing
                                  ? l10n.transcribing
                                  : l10n.stopAndTranscribe,
                            ),
                          ),
                        ],
                      ),
                      if (recording) ...[
                        const SizedBox(height: AppSpacing.compact),
                        Text(
                          l10n.recordingSpeakThenStop,
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
                  child: Text(l10n.close),
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
    final l10n = context.l10n;
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
                return l10n.realtimeAsrAuthenticationRejected(message);
              }
              if (message.contains('HTTP status code: 403')) {
                return l10n.realtimeAsrAccessRefused(message);
              }
              if (message.contains('was not upgraded to websocket') ||
                  message.contains('HTTP status code: 400')) {
                return l10n.realtimeAsrStartFailed(message);
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
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.error,
                    message: l10n.microphonePermissionRequired,
                  );
                });
                return;
              }
              setSheetState(() {
                feedback = _CapabilityTestFeedback(
                  kind: _CapabilityTestFeedbackKind.info,
                  message: l10n.startingRealtimeSpeechTest,
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
                          feedback = _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: l10n.realtimeTranscriptReceived,
                          );
                        } else {
                          partial = words;
                          feedback = _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: l10n.realtimeSpeechComingThrough,
                          );
                        }
                      });
                      _setCapabilityTestFeedback(
                        SpeechPluginCapability.realtimeAsr,
                        _CapabilityTestFeedback(
                          kind: _CapabilityTestFeedbackKind.success,
                          message: words.trim().isEmpty
                              ? l10n.realtimeSpeechComingThrough
                              : l10n.realtimeSpeechComingThroughWithText(
                                  words.trim(),
                                ),
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
                            feedback = _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.success,
                              message: l10n.realtimeTranscriptReceived,
                            );
                          } else {
                            partial = utterance.text;
                            feedback = _CapabilityTestFeedback(
                              kind: _CapabilityTestFeedbackKind.success,
                              message: l10n.realtimeSpeechComingThrough,
                            );
                          }
                        });
                        _setCapabilityTestFeedback(
                          SpeechPluginCapability.realtimeAsr,
                          _CapabilityTestFeedback(
                            kind: _CapabilityTestFeedbackKind.success,
                            message: utterance.text.trim().isEmpty
                                ? l10n.realtimeSpeechComingThrough
                                : l10n.realtimeSpeechComingThroughWithText(
                                    utterance.text.trim(),
                                  ),
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
                  feedback = _CapabilityTestFeedback(
                    kind: _CapabilityTestFeedbackKind.info,
                    message: l10n.listeningSpeakShortSentence,
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
              title: Text(l10n.testRealtimeAsr),
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
                                ? l10n.realtimeAsrSystemTestDescription
                                : l10n.realtimeAsrPluginTestDescription),
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
                  child: Text(l10n.close),
                ),
                FilledButton(
                  onPressed: starting || testUnavailableReason != null
                      ? null
                      : listening
                          ? stopRealtimeTest
                          : startRealtimeTest,
                  child: Text(
                    starting
                        ? l10n.starting
                        : listening
                            ? l10n.stop
                            : l10n.start,
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
    final localeTag = _pluginLocaleTag();
    final optionDescription = option.description(localeTag);
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
                        option.name(localeTag),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        optionDescription.isNotEmpty
                            ? optionDescription
                            : option.isInstalled
                                ? context.l10n.installedAndReady
                                : context.l10n.installBeforeSelectingPlugin,
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
                                        context.l10n.fillRequiredPluginSettings;
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
                              child: Text(context.l10n.use),
                            ),
                            PopupMenuButton<String>(
                              tooltip: context.l10n.more,
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
                                          option
                                              .id] = context.l10n
                                          .fillRequiredPluginSettingsBeforeTesting;
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
                                PopupMenuItem<String>(
                                  value: 'test',
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 20),
                                    title: Text(context.l10n.test),
                                    contentPadding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'uninstall',
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20),
                                    title: Text(context.l10n.uninstall),
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
                    child: Text(context.l10n.install),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.micro),
            Row(
              children: [
                if (!option.isInstalled) ...[
                  Text(
                    context.l10n.speechNotInstalled,
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
              ? context.l10n.commandSucceeded(command)
              : context.l10n.commandFailed(result.exitCode, result.stderr),
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
    final statusLabel =
        savedKey.isEmpty ? context.l10n.missingKey : context.l10n.keySaved;
    final saveFeedback = _pluginSaveFeedbackById[plugin.manifest.id];
    final savingPluginConfig =
        _savingPluginConfigurationIds.contains(plugin.manifest.id);
    final highlightApiKey = _highlightedPluginFieldKeys
        .contains('${plugin.manifest.id}::$_pluginApiKeyFieldKey');
    final localeTag = _pluginLocaleTag();
    final pluginName = plugin.manifest.localizedName(localeTag);
    final pluginDescription = plugin.manifest.localizedDescription(localeTag);
    final apiKeyLabel = plugin.manifest.localizedApiKeyLabel(localeTag);

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
                              context.l10n.pluginApiKeyTitle(pluginName),
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
                if (pluginDescription.isNotEmpty) ...[
                  MarkdownBody(
                    data: pluginDescription,
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
                    label: context.l10n.getApiKey,
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
                          label: Text(context.l10n.startService),
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
                          child: Text(context.l10n.stopService),
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
                        labelText: apiKeyLabel.isNotEmpty
                            ? apiKeyLabel
                            : context.l10n.apiKey,
                        helperText: context.l10n.sentAsXApiKey,
                        errorText:
                            highlightApiKey ? context.l10n.fieldRequired : null,
                        filled: true,
                        fillColor: highlightApiKey
                            ? AppColors.errorBgFor(brightness)
                            : null,
                      ),
                      onChanged: (value) {
                        _setPluginApiKeyValue(
                          plugin.manifest.id,
                          value,
                          onStateChanged: onStateChanged,
                        );
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
                            ? context.l10n.saving
                            : context.l10n.savePluginSettings,
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
                          savingPluginConfig
                              ? context.l10n.saving
                              : context.l10n.saveAndUse,
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
        context.l10n.additionalPluginSettings,
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
                                  Text(
                                    option.localizedLabel(_pluginLocaleTag()),
                                  ),
                                  if (option
                                      .localizedHelp(_pluginLocaleTag())
                                      .isNotEmpty)
                                    Text(
                                      option.localizedHelp(_pluginLocaleTag()),
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
                              option.localizedLabel(_pluginLocaleTag()),
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
    final localeTag = _pluginLocaleTag();
    final label = field.localizedLabel(localeTag);
    final help = field.localizedHelp(localeTag);
    final placeholder = field.localizedPlaceholder(localeTag);
    return InputDecoration(
      labelText: field.required ? '$label *' : label,
      hintText: placeholder.isNotEmpty ? placeholder : null,
      helperText: help.isNotEmpty ? help : null,
      errorText: highlighted ? context.l10n.fieldRequired : null,
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
    _updateSpeechPluginLocalSetting(pluginId, fieldKey, trimmed);
    _refreshPluginConfigurationFieldState(
      pluginId,
      fieldKey,
      hasValue: trimmed.isNotEmpty,
      onStateChanged: onStateChanged,
    );
  }

  void _setPluginApiKeyValue(
    String pluginId,
    String value, {
    StateSetter? onStateChanged,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _speechPluginApiKeysByPluginId.remove(pluginId);
    } else {
      _speechPluginApiKeysByPluginId[pluginId] = trimmed;
    }
    _refreshPluginConfigurationFieldState(
      pluginId,
      _pluginApiKeyFieldKey,
      hasValue: trimmed.isNotEmpty,
      onStateChanged: onStateChanged,
    );
  }

  void _refreshPluginConfigurationFieldState(
    String pluginId,
    String fieldKey, {
    required bool hasValue,
    StateSetter? onStateChanged,
  }) {
    var needsRebuild = false;
    if (_pluginConfigurationErrorsById.containsKey(pluginId)) {
      _clearPluginConfigurationError(pluginId);
      needsRebuild = true;
    }
    if (hasValue &&
        _highlightedPluginFieldKeys.remove('$pluginId::$fieldKey')) {
      needsRebuild = true;
    }
    if (!needsRebuild) {
      return;
    }
    setState(() {});
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

  Future<void> _openPluginRegistrationUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _speechPluginCapabilityLabel(SpeechPluginCapability capability) {
    return switch (capability) {
      SpeechPluginCapability.realtimeAsr =>
        context.l10n.speechProfileRealtimeAsrTitle,
      SpeechPluginCapability.batchAsr =>
        context.l10n.speechProfileBatchAsrTitle,
      SpeechPluginCapability.tts => context.l10n.speechProfileTtsTitle,
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
    final deleting = _deletingModelIds.contains(model.id);

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
                _profileSummaryLine(l10n, model),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.compact),
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
            title: l10n.targetSpeakerOnly,
            subtitle: _speakers.isEmpty
                ? l10n.enrollSpeakerBeforeFiltering
                : l10n.batchAsrIgnoresUnmatchedSpeaker,
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
                        ? l10n.voiceprintModelInstalled
                        : l10n.voiceprintModelRequired,
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
                          ? l10n.speechDownloading
                          : l10n.speechDownload,
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
              decoration: InputDecoration(
                labelText: l10n.speakerName,
                hintText: l10n.myVoice,
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
                      ? l10n.savingSpeaker
                      : _speakerEnrollmentRecording
                          ? l10n.finishEnrollment
                          : l10n.recordEnrollmentSample,
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
                    decoration: InputDecoration(labelText: l10n.speaker),
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

  SpeechDownloadTask? _latestDownloadTask(
    SpeechDownloadTask? current,
    SpeechDownloadTask candidate,
  ) {
    if (current == null || candidate.updatedAt.isAfter(current.updatedAt)) {
      return candidate;
    }
    return current;
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
          _buildCallModeSettingRow(
            context,
            title: l10n.callModeAllowInterruptionsLabel,
            subtitle: l10n.callModeAllowInterruptionsHelp,
            control: Switch(
              value: _callModeAllowInterruptions,
              onChanged: (value) {
                setState(() {
                  _callModeAllowInterruptions = value;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.compact),
          _buildCallModeSettingRow(
            context,
            title: l10n.callModeSpeechPauseLabel,
            subtitle: l10n.callModeSpeechPauseHelp,
            control: SizedBox(
              width: 148,
              child: TextFormField(
                controller: _callModeSpeechPauseController,
                style: formValueTextStyle,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  suffixText: 'ms',
                  errorText: _callModeSpeechPauseError,
                  isDense: true,
                ),
                onChanged: (value) {
                  _handleCallModeSpeechPauseChanged(l10n, value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallModeSettingRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget control,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final label = Column(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: AppSpacing.compact),
              Align(
                alignment: Alignment.centerRight,
                child: control,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: label),
            const SizedBox(width: AppSpacing.tileX),
            control,
          ],
        );
      },
    );
  }

  String? _callModeSpeechPauseInputError(
    AppLocalizations l10n,
    String value,
  ) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return l10n.fieldRequired;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null ||
        parsed < minCallModeSpeechPauseMillis ||
        parsed > maxCallModeSpeechPauseMillis) {
      return l10n.callModeSpeechPauseRangeError(
        minCallModeSpeechPauseMillis,
        maxCallModeSpeechPauseMillis,
      );
    }
    return null;
  }

  void _handleCallModeSpeechPauseChanged(
    AppLocalizations l10n,
    String value,
  ) {
    final nextError = _callModeSpeechPauseInputError(l10n, value);
    final parsed = int.tryParse(value);
    final nextMillis = nextError == null && parsed != null
        ? parsed
        : _callModeSpeechPauseMillis;
    if (nextError == _callModeSpeechPauseError &&
        nextMillis == _callModeSpeechPauseMillis) {
      return;
    }
    setState(() {
      _callModeSpeechPauseError = nextError;
      _callModeSpeechPauseMillis = nextMillis;
    });
  }

  bool _applyCallModeSpeechPauseInput(AppLocalizations l10n) {
    final text = _callModeSpeechPauseController.text;
    final error = _callModeSpeechPauseInputError(l10n, text);
    if (error != null) {
      if (_callModeSpeechPauseError == error) {
        return false;
      }
      setState(() {
        _callModeSpeechPauseError = error;
      });
      return false;
    }
    final nextMillis = int.parse(text.trim());
    if (_callModeSpeechPauseMillis == nextMillis &&
        _callModeSpeechPauseError == null) {
      return true;
    }
    setState(() {
      _callModeSpeechPauseMillis = nextMillis;
      _callModeSpeechPauseError = null;
    });
    return true;
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
    try {
      final indexes = await _speechPluginRegistry.fetchRepositoryIndexes();
      final installed = await _speechPluginRegistry.listInstalled();
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
    } catch (_) {}
  }

  Future<void> _installSpeechPlugin(
    SpeechPluginRepositoryEntry entry,
  ) async {
    try {
      await _speechPluginRegistry.installFromRepositoryEntry(entry);
      final installed = await _speechPluginRegistry.listInstalled();
      if (!mounted) {
        return;
      }
      setState(() {
        _installedSpeechPlugins = installed;
      });
    } catch (_) {}
  }

  Future<void> _uninstallSpeechPlugin(String pluginId) async {
    try {
      await _speechPluginRegistry.uninstall(pluginId);
      final installed = await _speechPluginRegistry.listInstalled();
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
    } catch (_) {}
  }

  Future<void> _downloadSpeechModel(String modelId) async {
    setState(() {
      _downloadingModelIds.add(modelId);
      _downloadErrorsByModelId.remove(modelId);
      _speechStatusError = null;
    });
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
      return context.l10n.bridgeErrorWithStatus(statusMatch.group(1)!, raw);
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
          _speechStatusError = context.l10n.microphonePermissionRequired;
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
        throw Exception(context.l10n.noEnrollmentAudioRecorded);
      }
      final name = _speakerNameController.text.trim().isEmpty
          ? context.l10n.defaultSpeakerName(_speakers.length + 1)
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

  bool _isWakeWordModel(SpeechModelSummary model) {
    return model.kind == SpeechModelKind.wakeWord ||
        model.capabilities.wakeWord;
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
    final l10n = context.l10n;
    if (!_applyCallModeSpeechPauseInput(l10n)) {
      return;
    }
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
}
