import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../../l10n/generated/app_localizations.dart';

class SpeechSettingsScreen extends StatefulWidget {
  const SpeechSettingsScreen({
    super.key,
    this.debugPlatformOverride,
    this.debugIsWebOverride,
  });

  static const routeName = '/settings/speech';

  final TargetPlatform? debugPlatformOverride;
  final bool? debugIsWebOverride;

  @override
  State<SpeechSettingsScreen> createState() => _SpeechSettingsScreenState();
}

class _SpeechSettingsScreenState extends State<SpeechSettingsScreen> {
  final _zhipuApiKeyController = TextEditingController();
  final _whisperApiKeyController = TextEditingController();
  final _whisperBaseUrlController = TextEditingController();

  late TtsProvider _ttsProvider;
  late AsrProvider _asrProvider;
  bool _saving = false;

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
  }

  @override
  void dispose() {
    appSettingsController.removeListener(_onSettingsChanged);
    _zhipuApiKeyController.dispose();
    _whisperApiKeyController.dispose();
    _whisperBaseUrlController.dispose();
    super.dispose();
  }

  void _syncFromSettings(AppSettings settings) {
    _ttsProvider = settings.ttsProvider;
    _asrProvider = settings.asrProvider;
    _zhipuApiKeyController.text = settings.zhipuApiKey;
    _whisperApiKeyController.text = settings.whisperApiKey;
    _whisperBaseUrlController.text = settings.whisperBaseUrl;
  }

  void _onSettingsChanged() {
    if (!mounted) return;
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
                                      value: TtsProvider.zhipu,
                                      child: const Text('Zhipu'),
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
                            if (ttsHelpText != null) ...[
                              const SizedBox(height: AppSpacing.compact),
                              _buildProviderHelpText(
                                context,
                                ttsHelpText,
                                warning: !_systemTtsSupportedOnPlatform &&
                                    _ttsProvider == TtsProvider.system,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.compact),
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
                                      value: AsrProvider.zhipu,
                                      child: const Text('Zhipu'),
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
                            if (asrHelpText != null) ...[
                              const SizedBox(height: AppSpacing.compact),
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
                          ],
                        ),
                        const SizedBox(height: AppSpacing.stackTight),
                        _buildSectionCard(
                          context,
                          title: 'ZHIPU API',
                          children: [
                            TextField(
                              controller: _zhipuApiKeyController,
                              obscureText: true,
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.apiKey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.stackTight),
                        _buildSectionCard(
                          context,
                          title: 'WHISPER API',
                          children: [
                            TextField(
                              controller: _whisperApiKeyController,
                              obscureText: true,
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.apiKey,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.stack),
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

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final next = appSettingsController.settings.copyWith(
        ttsProvider: _ttsProvider,
        asrProvider: _asrProvider,
        zhipuApiKey: _zhipuApiKeyController.text.trim(),
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
}
