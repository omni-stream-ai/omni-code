import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../bridge_speech_models.dart';
import '../l10n/app_locale.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../../l10n/generated/app_localizations.dart';

SpeechStatus? _cachedSpeechStatus;

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
  final Set<String> _downloadingModelIds = <String>{};
  final Map<String, String> _downloadErrorsByModelId = <String, String>{};
  final Set<String> _updatingProfileKeys = <String>{};

  late TtsProvider _ttsProvider;
  late String _bridgeLocalTtsVoice;
  late bool _bridgeLocalTtsStreaming;
  late AsrProvider _asrProvider;
  late bool _callModeAllowInterruptions;
  late int _callModeSpeechPauseMillis;
  bool _saving = false;
  bool _speechLoading = false;
  SpeechStatus? _speechStatus;
  String? _speechStatusError;
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
  }

  @override
  void dispose() {
    appSettingsController.removeListener(_onSettingsChanged);
    _speechPollingTimer?.cancel();
    _whisperApiKeyController.dispose();
    _whisperBaseUrlController.dispose();
    super.dispose();
  }

  void _syncFromSettings(AppSettings settings) {
    _ttsProvider = settings.ttsProvider;
    _bridgeLocalTtsVoice = settings.bridgeLocalTtsVoice;
    _bridgeLocalTtsStreaming = settings.bridgeLocalTtsStreaming;
    _asrProvider = settings.asrProvider;
    _callModeAllowInterruptions = settings.callModeAllowInterruptions;
    _callModeSpeechPauseMillis = settings.callModeSpeechPauseMillis;
    _whisperApiKeyController.text = settings.whisperApiKey;
    _whisperBaseUrlController.text = settings.whisperBaseUrl;
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncFromSettings(appSettingsController.settings);
    });
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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context, l10n),
                        const SizedBox(height: AppSpacing.stackTight),
                        _buildSectionCard(
                          context,
                          title: l10n.speechSection.toUpperCase(),
                          children: [
                            Builder(
                              builder: (context) {
                                final selectedTtsProvider =
                                    TtsProvider.values.contains(_ttsProvider)
                                        ? _ttsProvider
                                        : TtsProvider.system;
                                return DropdownButtonFormField<TtsProvider>(
                                  initialValue: selectedTtsProvider,
                                  style: formValueTextStyle,
                                  decoration: InputDecoration(
                                    labelText: l10n.ttsProviderLabel,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: TtsProvider.system,
                                      child: Text(l10n.speechSystem),
                                    ),
                                    DropdownMenuItem(
                                      value: TtsProvider.bridgeLocal,
                                      child: Text(l10n.omniBridgeLocal),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _ttsProvider = value;
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                            if (ttsHelpText != null)
                              _buildProviderHelpText(
                                context,
                                ttsHelpText,
                                warning: !_systemTtsSupportedOnPlatform &&
                                    _ttsProvider == TtsProvider.system,
                              ),
                            Builder(
                              builder: (context) {
                                final selectedAsrProvider =
                                    AsrProvider.values.contains(_asrProvider)
                                        ? _asrProvider
                                        : AsrProvider.system;
                                return DropdownButtonFormField<AsrProvider>(
                                  initialValue: selectedAsrProvider,
                                  style: formValueTextStyle,
                                  decoration: InputDecoration(
                                    labelText: l10n.asrProviderLabel,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: AsrProvider.system,
                                      child: Text(l10n.speechSystem),
                                    ),
                                    DropdownMenuItem(
                                      value: AsrProvider.bridgeLocal,
                                      child: Text(l10n.omniBridgeLocal),
                                    ),
                                    DropdownMenuItem(
                                      value: AsrProvider.whisper,
                                      child: Text(l10n.whisperCompatible),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _asrProvider = value;
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                            if (asrHelpText != null)
                              _buildProviderHelpText(
                                context,
                                asrHelpText,
                                warning: (!_systemAsrSupportedOnPlatform &&
                                        _asrProvider == AsrProvider.system) ||
                                    (!_isWebPlatform &&
                                        _platform == TargetPlatform.macOS &&
                                        _asrProvider == AsrProvider.system),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.stackTight),
                        _buildSectionCard(
                          context,
                          title: l10n.localBridgeModelsSection.toUpperCase(),
                          children: [
                            _buildLocalBridgeContent(context),
                          ],
                        ),
                        if (_ttsProvider == TtsProvider.bridgeLocal) ...[
                          const SizedBox(height: AppSpacing.stackTight),
                          _buildSectionCard(
                            context,
                            title: l10n.localBridgeTtsVoiceLabel.toUpperCase(),
                            children: [
                              _buildLocalBridgeTtsVoiceContent(context),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.stackTight),
                        _buildSectionCard(
                          context,
                          title: l10n.callModeSection.toUpperCase(),
                          children: [
                            _buildCallModeContent(
                              context,
                              formValueTextStyle,
                            ),
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
                              decoration: InputDecoration(
                                labelText: l10n.baseUrl,
                                hintText: 'https://api.openai.com/v1',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppBackHeader(
          title: l10n.speechSection.toUpperCase(),
          titleStyle: titleStyle,
        ),
        const Spacer(),
        const SizedBox(width: AppSpacing.compact),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accentBlueFor(theme.brightness),
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.saving : l10n.save),
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

  Widget _buildLocalBridgeContent(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = _speechStatus;

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
        if (_speechStatusError != null) ...[
          const SizedBox(height: AppSpacing.compact),
          _buildSpeechErrorBanner(context, _speechStatusError!),
        ],
        const SizedBox(height: AppSpacing.compact),
        if (_speechLoading && status == null)
          const Center(child: CircularProgressIndicator())
        else if (status != null)
          _buildLocalBridgeModelsPanel(context, status),
      ],
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
            children: [
              Expanded(
                child: Text(
                  l10n.localBridgeModelRoot,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _speechLoading ? null : () => _refreshSpeechStatus(),
                child: Text(_speechLoading ? l10n.refreshing : l10n.refresh),
              ),
            ],
          ),
          if (status.rootDir.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: AppSpacing.tilePadding,
              decoration: BoxDecoration(
                color: AppColors.panelAltFor(brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
              ),
              child: Text(
                status.rootDir,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoftFor(brightness),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
          ],
          Text(
            l10n.bridgeUrlLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            _client.baseUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.stack),
          ..._localBridgeProfileOrder.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.compact),
              child: _buildProfileSummaryTile(context, status, profile),
            ),
          ),
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
    final downloadError = _downloadErrorForModels(models);
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
                    child: Text(
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
    final selectedModelId = status.profiles.modelForProfile(profile);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panelFor(brightness),
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetTheme = Theme.of(sheetContext);
        final height = MediaQuery.of(sheetContext).size.height * 0.72;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: height,
                child: Column(
                  children: [
                    Padding(
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
                                  style: sheetTheme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.micro),
                                Text(
                                  _profileSubtitle(l10n, profile),
                                  style:
                                      sheetTheme.textTheme.bodySmall?.copyWith(
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
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.block,
                          0,
                          AppSpacing.block,
                          AppSpacing.block,
                        ),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final selected = selectedModelId == model.id;
                          final updateKey =
                              _speechProfileUpdateKey(profile, model.id);
                          final selecting =
                              _updatingProfileKeys.contains(updateKey);
                          final downloading =
                              _downloadingModelIds.contains(model.id) ||
                                  status.activeDownloads.any(
                                    (task) => task.modelId == model.id,
                                  );
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.compact,
                            ),
                            child: Container(
                              padding: AppSpacing.tilePadding,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceDeepFor(brightness),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusTile,
                                ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          model.displayName,
                                          style: sheetTheme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(
                                          height: AppSpacing.micro,
                                        ),
                                        Text(
                                          _profileSummaryLine(l10n, model),
                                          style: sheetTheme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: AppColors.mutedSoftFor(
                                              brightness,
                                            ),
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.compact),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 42),
                                    child: downloading
                                        ? FilledButton(
                                            onPressed: null,
                                            style: _sheetActionButtonStyle(
                                              filled: true,
                                            ),
                                            child: Text(l10n.speechDownloading),
                                          )
                                        : selecting
                                            ? OutlinedButton(
                                                onPressed: null,
                                                style: _sheetActionButtonStyle(
                                                  filled: false,
                                                ),
                                                child: _buildButtonLoadingChild(
                                                  sheetContext,
                                                  l10n.speechSelect,
                                                ),
                                              )
                                            : !model.installed
                                                ? FilledButton(
                                                    onPressed: () async {
                                                      Navigator.of(sheetContext)
                                                          .pop();
                                                      await _downloadSpeechModel(
                                                        model.id,
                                                      );
                                                    },
                                                    style:
                                                        _sheetActionButtonStyle(
                                                      filled: true,
                                                    ),
                                                    child: Text(
                                                      l10n.speechDownload,
                                                    ),
                                                  )
                                                : selected
                                                    ? FilledButton.tonal(
                                                        onPressed: null,
                                                        style: FilledButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              const Size(
                                                            84,
                                                            42,
                                                          ),
                                                          maximumSize:
                                                              const Size(
                                                            140,
                                                            42,
                                                          ),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal:
                                                                AppSpacing
                                                                    .tileX,
                                                          ),
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                        child: Text(
                                                          l10n.speechSelected,
                                                        ),
                                                      )
                                                    : OutlinedButton(
                                                        onPressed: () async {
                                                          setSheetState(() {
                                                            _updatingProfileKeys
                                                                .add(updateKey);
                                                          });
                                                          final updated =
                                                              await _updateSpeechProfile(
                                                            profile,
                                                            model.id,
                                                          );
                                                          if (!sheetContext
                                                              .mounted) {
                                                            return;
                                                          }
                                                          if (updated) {
                                                            Navigator.of(
                                                              sheetContext,
                                                            ).pop();
                                                          } else {
                                                            setSheetState(
                                                                () {});
                                                          }
                                                        },
                                                        style:
                                                            _sheetActionButtonStyle(
                                                          filled: false,
                                                        ),
                                                        child: Text(
                                                          l10n.speechSelect,
                                                        ),
                                                      ),
                                  ),
                                ],
                              ),
                            ),
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
  }

  Widget _buildButtonLoadingChild(BuildContext context, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.72,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.micro),
        Text(label),
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
    for (final task in status.activeDownloads) {
      if (modelIds.contains(task.modelId)) {
        return task;
      }
    }
    return null;
  }

  String? _downloadErrorForModels(List<SpeechModelSummary> models) {
    for (final model in models) {
      final error = _downloadErrorsByModelId[model.id];
      if (error != null) {
        return error;
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
    final selectedVoice = _resolvedTtsVoiceSelection(selectedTtsModel);

    if (selectedTtsModel == null) {
      return Text(
        l10n.speechNotSelected,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.mutedSoftFor(brightness),
          height: 1.4,
        ),
      );
    }

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
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _bridgeLocalTtsVoice = value;
                });
              },
            ),
          ],
          const SizedBox(height: AppSpacing.compact),
          SwitchListTile(
            value: _bridgeLocalTtsStreaming,
            onChanged: (value) {
              setState(() {
                _bridgeLocalTtsStreaming = value;
              });
            },
            title: Text(l10n.localBridgeTtsStreamingLabel),
            subtitle: Text(l10n.localBridgeTtsStreamingHelp),
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
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
          Text(
            l10n.callModeSpeechPauseBridgeOnlyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String? _ttsPlatformHelp(AppLocalizations l10n) {
    if (_ttsProvider == TtsProvider.bridgeLocal) {
      return l10n.bridgeLocalTtsHelp;
    }
    if (!_systemTtsSupportedOnPlatform && !_isWebPlatform) {
      return switch (_platform) {
        TargetPlatform.linux => l10n.systemTtsUnavailableOnLinux,
        _ => l10n.speechSystemPreferredHelp,
      };
    }
    return l10n.speechSystemPreferredHelp;
  }

  String? _asrPlatformHelp(AppLocalizations l10n) {
    if (_asrProvider == AsrProvider.bridgeLocal) {
      return l10n.bridgeLocalAsrHelp;
    }
    if (_asrProvider == AsrProvider.whisper) {
      return l10n.whisperApiHelp;
    }
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
      if (!mounted) {
        return;
      }
      setState(() {
        _speechLoading = false;
        _speechStatus = status;
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

  Future<void> _downloadSpeechModel(String modelId) async {
    setState(() {
      _downloadingModelIds.add(modelId);
      _downloadErrorsByModelId.remove(modelId);
      _speechStatusError = null;
    });
    try {
      await _client.createSpeechDownload(modelId);
      await _refreshSpeechStatus(silent: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      setState(() {
        _downloadErrorsByModelId[modelId] = l10n.speechModelDownloadFailed(
          modelId,
          error.toString(),
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
    };
    if (profiles.isNotEmpty) {
      final sorted = profiles.toList(growable: false)
        ..sort((left, right) => left.index.compareTo(right.index));
      return sorted;
    }
    return _inferProfilesForModel(model);
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

  String? _resolvedTtsVoiceSelection(SpeechModelSummary? model) {
    final options = _ttsVoiceOptions(model);
    if (options.isEmpty) {
      return null;
    }
    final saved = _bridgeLocalTtsVoice.trim();
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
    };
  }

  String _profileSubtitle(AppLocalizations l10n, SpeechProfile profile) {
    return switch (profile) {
      SpeechProfile.asrBatch => l10n.speechProfileBatchAsrHelp,
      SpeechProfile.asrRealtime => l10n.speechProfileRealtimeAsrHelp,
      SpeechProfile.ttsDefault => l10n.speechProfileTtsHelp,
      SpeechProfile.vadDefault => l10n.speechProfileVadHelp,
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
        ttsProvider: _ttsProvider,
        bridgeLocalTtsVoice: _bridgeLocalTtsVoice,
        bridgeLocalTtsStreaming: _bridgeLocalTtsStreaming,
        asrProvider: _asrProvider,
        callModeAllowInterruptions: _callModeAllowInterruptions,
        callModeSpeechPauseMillis: _callModeSpeechPauseMillis,
        whisperApiKey: _whisperApiKeyController.text.trim(),
        whisperBaseUrl: _whisperBaseUrlController.text.trim(),
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
