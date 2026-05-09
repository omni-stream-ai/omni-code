import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../services/app_update_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/copyable_message.dart';
import 'speech_settings_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bridgeUrlController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _updateManifestUrlController = TextEditingController();
  final _aiApprovalBaseUrlController = TextEditingController();
  final _aiApprovalApiKeyController = TextEditingController();
  final _aiApprovalModelController = TextEditingController();
  final _notificationMaxCharsController = TextEditingController();

  late bool _aiApprovalEnabled;
  late String _aiApprovalMaxRisk;
  late AppThemeModeSetting _themeMode;
  late bool _autoSpeakReplies;
  late bool _compressAssistantReplies;
  late String _appLanguage;
  String _currentVersion = '';
  bool _saving = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _syncFromSettings(appSettingsController.settings);
    appSettingsController.addListener(_onSettingsChanged);
    unawaited(_loadCurrentVersion());
  }

  @override
  void dispose() {
    appSettingsController.removeListener(_onSettingsChanged);
    _bridgeUrlController.dispose();
    _clientIdController.dispose();
    _updateManifestUrlController.dispose();
    _aiApprovalBaseUrlController.dispose();
    _aiApprovalApiKeyController.dispose();
    _aiApprovalModelController.dispose();
    _notificationMaxCharsController.dispose();
    super.dispose();
  }

  void _syncFromSettings(AppSettings settings) {
    _bridgeUrlController.text = settings.bridgeUrl;
    _clientIdController.text = settings.clientId;
    _appLanguage = settings.appLanguage;
    _updateManifestUrlController.text = settings.updateManifestUrl;
    _aiApprovalBaseUrlController.text = settings.aiApprovalBaseUrl;
    _aiApprovalApiKeyController.text = settings.aiApprovalApiKey;
    _aiApprovalModelController.text = settings.aiApprovalModel;
    _aiApprovalEnabled = settings.aiApprovalEnabled;
    _aiApprovalMaxRisk = settings.aiApprovalMaxRisk;
    _notificationMaxCharsController.text =
        settings.notificationMaxChars.toString();
    _themeMode = settings.themeMode;
    _autoSpeakReplies = settings.autoSpeakReplies;
    _compressAssistantReplies = settings.compressAssistantReplies;
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {
      _syncFromSettings(appSettingsController.settings);
    });
  }

  Future<void> _loadCurrentVersion() async {
    var version = '0.1.4';
    try {
      if (kIsWeb) {
        version = const String.fromEnvironment(
          'PACKAGE_VERSION',
          defaultValue: '0.1.4',
        );
      } else {
        final info = await PackageInfo.fromPlatform();
        if (info.version.trim().isNotEmpty) {
          version = info.version.trim();
        }
      }
    } catch (_) {
      version = '0.1.4';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentVersion = version;
    });
  }

  void _showCopyableErrorSnackBar(String message) {
    final brightness = Theme.of(context).brightness;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: CopyableMessage(
          message: message,
          copyLabel: context.l10n.copy,
          copiedLabel: context.l10n.copied,
          showCopyButton: false,
          backgroundColor: Colors.transparent,
          borderColor: Colors.transparent,
          iconColor: AppColors.errorIconFor(brightness),
          textColor: AppColors.errorTextFor(brightness),
        ),
        action: SnackBarAction(
          label: context.l10n.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
          },
        ),
      ),
    );
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
    final theme = Theme.of(context);
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
                        const SizedBox(height: AppSpacing.fieldGap),
                        _buildSpeechSection(context, l10n),
                        const SizedBox(height: AppSpacing.fieldGap),
                        _buildSectionCard(
                          context,
                          title: l10n.aiApprovalSection.toUpperCase(),
                          children: [
                            SwitchListTile(
                              value: _aiApprovalEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _aiApprovalEnabled = value;
                                });
                              },
                              title: Text(l10n.enableAiApproval),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: AppSpacing.micro),
                            TextField(
                              controller: _aiApprovalBaseUrlController,
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.baseUrl,
                                hintText: 'https://api.openai.com/v1',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.compact),
                            TextField(
                              controller: _aiApprovalApiKeyController,
                              obscureText: true,
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.apiKey,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.fieldGap),
                            TextField(
                              controller: _aiApprovalModelController,
                              style: formValueTextStyle,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                                hintText: 'gpt-4.1-mini',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.compact),
                            DropdownButtonFormField<String>(
                              initialValue: _aiApprovalMaxRisk,
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.aiApprovalMaxRisk,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'low',
                                  child: Text(l10n.riskLow),
                                ),
                                DropdownMenuItem(
                                  value: 'medium',
                                  child: Text(l10n.riskMedium),
                                ),
                                DropdownMenuItem(
                                  value: 'high',
                                  child: Text(l10n.riskHigh),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _aiApprovalMaxRisk = value;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.fieldGap),
                        _buildSectionCard(
                          context,
                          title: 'REPLY BEHAVIOR',
                          children: [
                            SwitchListTile(
                              value: _autoSpeakReplies,
                              onChanged: _saving
                                  ? null
                                  : (value) => _saveLocalToggle(
                                        applyLocalState: () {
                                          _autoSpeakReplies = value;
                                        },
                                        buildNextSettings: (settings) =>
                                            settings.copyWith(
                                          autoSpeakReplies: value,
                                        ),
                                      ),
                              title: Text(l10n.autoSpeakReplies),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: AppSpacing.stackTight),
                            SwitchListTile(
                              value: _compressAssistantReplies,
                              onChanged: _saving
                                  ? null
                                  : (value) => _saveLocalToggle(
                                        applyLocalState: () {
                                          _compressAssistantReplies = value;
                                        },
                                        buildNextSettings: (settings) =>
                                            settings.copyWith(
                                          compressAssistantReplies: value,
                                        ),
                                      ),
                              title: Text(l10n.compressReplies),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                            ),
                            TextField(
                              controller: _notificationMaxCharsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: formValueTextStyle,
                              decoration: InputDecoration(
                                labelText: l10n.notificationPreviewMaxChars,
                                hintText: '160',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.fieldGap),
                        _buildSystemSection(context, l10n),
                        const SizedBox(height: AppSpacing.compact),
                        _buildSectionCard(
                          context,
                          title: l10n.appUpdateSection.toUpperCase(),
                          children: [
                            _buildLabeledRow(
                              context,
                              label: 'Current version',
                              value: _currentVersion.isEmpty
                                  ? '...'
                                  : 'v$_currentVersion',
                            ),
                            const SizedBox(height: AppSpacing.micro),
                            _buildLabeledRow(
                              context,
                              label: 'Update manifest',
                              value: 'GitHub releases',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.micro),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                              backgroundColor: AppColors.panelFor(
                                theme.brightness,
                              ),
                              foregroundColor: theme.colorScheme.onSurface,
                              side: BorderSide(
                                color: AppColors.outlineFor(theme.brightness),
                              ),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: kIsWeb
                                ? _openGithubReleases
                                : (_saving || _checkingUpdate
                                    ? null
                                    : _checkAppUpdate),
                            child: Text(l10n.checkAppUpdate),
                          ),
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
          title: l10n.settingsTitle.toUpperCase(),
          titleStyle: titleStyle,
        ),
        const Spacer(),
        SizedBox(
          width: 72,
          height: 32,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.tileX),
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

  Widget _buildSpeechSection(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: () async {
        await Navigator.of(context).pushNamed(SpeechSettingsScreen.routeName);
        if (!mounted) {
          return;
        }
        setState(() {});
      },
      padding: AppSpacing.cardPadding,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.panelDeepFor(theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: AppColors.accentBlueFor(theme.brightness),
            ),
          ),
          const SizedBox(width: AppSpacing.stack),
          Expanded(
            child: Text(
              l10n.speechSection.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.iconTheme.color,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSection(BuildContext context, AppLocalizations l10n) {
    final formValueTextStyle = _formValueTextStyle(context);
    final selectedLanguage = switch (_appLanguage) {
      'system' || 'en' || 'zh' => _appLanguage,
      _ => 'system',
    };
    return _buildSectionCard(
      context,
      title: l10n.systemSection.toUpperCase(),
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedLanguage,
          style: formValueTextStyle,
          decoration: InputDecoration(
            labelText: l10n.languageLabel,
          ),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(l10n.languageSystem),
            ),
            DropdownMenuItem(
              value: 'en',
              child: Text(l10n.languageEnglish),
            ),
            DropdownMenuItem(
              value: 'zh',
              child: Text(l10n.languageChinese),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _appLanguage = value;
              });
            }
          },
        ),
        DropdownButtonFormField<AppThemeModeSetting>(
          initialValue: _themeMode,
          style: formValueTextStyle,
          decoration: InputDecoration(
            labelText: l10n.themeSection,
          ),
          items: [
            DropdownMenuItem(
              value: AppThemeModeSetting.system,
              child: Text(l10n.themeFollowSystem),
            ),
            DropdownMenuItem(
              value: AppThemeModeSetting.light,
              child: Text(l10n.themeLight),
            ),
            DropdownMenuItem(
              value: AppThemeModeSetting.dark,
              child: Text(l10n.themeDark),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _themeMode = value;
              });
            }
          },
        ),
        TextField(
          controller: _bridgeUrlController,
          style: formValueTextStyle,
          decoration: InputDecoration(
            labelText: l10n.bridgeUrlLabel,
            hintText: 'http://127.0.0.1:8787',
          ),
        ),
        TextField(
          controller: _clientIdController,
          readOnly: true,
          style: formValueTextStyle,
          decoration: InputDecoration(
            labelText: 'Client ID',
            suffixIcon: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(18),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: context.l10n.retry,
              onPressed: _regenerateClientId,
              icon: const Icon(Icons.refresh_rounded),
            ),
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
        const SizedBox(height: AppSpacing.micro),
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

  Widget _buildLabeledRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _interleave(List<Widget> children) {
    if (children.isEmpty) {
      return const [];
    }
    final result = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        result.add(const SizedBox(height: AppSpacing.stackTight));
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
        bridgeUrl: _bridgeUrlController.text.trim(),
        clientId: _clientIdController.text.trim(),
        appLanguage: _appLanguage,
        themeMode: _themeMode,
        updateManifestUrl: _updateManifestUrlController.text.trim(),
        aiApprovalEnabled: _aiApprovalEnabled,
        aiApprovalBaseUrl: _aiApprovalBaseUrlController.text.trim(),
        aiApprovalApiKey: _aiApprovalApiKeyController.text.trim(),
        aiApprovalModel: _aiApprovalModelController.text.trim(),
        aiApprovalMaxRisk: _aiApprovalMaxRisk,
        notificationMaxChars: _parseNotificationMaxCharsInput(
          _notificationMaxCharsController.text,
          appSettingsController.settings.notificationMaxChars,
        ),
        autoSpeakReplies: _autoSpeakReplies,
        compressAssistantReplies: _compressAssistantReplies,
      );
      await appSettingsController.save(next);
      await bridgeClient.updateBridgeSettings(next);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsSaved)),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveLocalToggle({
    required VoidCallback applyLocalState,
    required AppSettings Function(AppSettings settings) buildNextSettings,
  }) async {
    final previousSettings = appSettingsController.settings;
    setState(() {
      applyLocalState();
    });
    try {
      await appSettingsController.save(buildNextSettings(previousSettings));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final current = appSettingsController.settings;
      setState(() {
        _autoSpeakReplies = current.autoSpeakReplies;
        _compressAssistantReplies = current.compressAssistantReplies;
      });
      _showCopyableErrorSnackBar(context.l10n.settingsSaveFailed('$error'));
    }
  }

  void _regenerateClientId() {
    final next = AppSettings.defaults().clientId;
    setState(() {
      _clientIdController.text = next;
    });
  }

  int _parseNotificationMaxCharsInput(String raw, int fallback) {
    final value = int.tryParse(raw.trim());
    if (value == null || value <= 0) {
      return fallback;
    }
    return value;
  }

  Future<void> _checkAppUpdate() async {
    setState(() {
      _checkingUpdate = true;
    });
    try {
      await appSettingsController.save(
        appSettingsController.settings.copyWith(
          updateManifestUrl: _updateManifestUrlController.text.trim(),
        ),
      );
      final result = await appUpdateService.checkForUpdate(
        manifestUrl: _resolvedUpdateManifestUrl(),
      );
      if (!mounted) {
        return;
      }
      if (!result.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.alreadyLatestVersion(result.currentVersionName),
            ),
          ),
        );
        return;
      }
      await _showUpdateDialog(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showCopyableErrorSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

  Future<void> _openGithubReleases() async {
    final uri = Uri.parse(
      'https://github.com/omni-stream-ai/omni-code/releases/latest',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _resolvedUpdateManifestUrl() {
    final configured = _updateManifestUrlController.text.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return appSettingsController.settings.updateManifestUrl.trim();
  }

  Future<void> _showUpdateDialog(AppUpdateCheckResult result) async {
    final update = result.update!;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.force,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.newVersionFound(update.versionName)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.currentVersion(result.currentVersionName)),
                const SizedBox(height: AppSpacing.compact),
                if (update.releaseNotes.trim().isNotEmpty)
                  Text(update.releaseNotes.trim()),
              ],
            ),
          ),
          actions: [
            if (!update.force)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.later),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _downloadAndInstallUpdate(update);
              },
              child: Text(context.l10n.updateNow),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstallUpdate(AppUpdateInfo update) async {
    final progress = ValueNotifier<AppUpdateDownloadProgress?>(null);
    var dialogClosed = false;
    try {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: Text(context.l10n.downloadingUpdate),
              content: ValueListenableBuilder<AppUpdateDownloadProgress?>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final fraction = value?.fraction;
                  final received = _formatBytes(value?.receivedBytes ?? 0);
                  final total = value?.totalBytes == null
                      ? null
                      : _formatBytes(value!.totalBytes!);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: fraction),
                      const SizedBox(height: AppSpacing.stack),
                      Text(
                        total == null
                            ? context.l10n.downloadedBytes(received)
                            : context.l10n.downloadProgress(received, total),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ).then((_) {
          dialogClosed = true;
        }),
      );

      final file = await appUpdateService.downloadApk(
        update.apkUrl,
        onProgress: (value) {
          progress.value = value;
        },
      );
      if (!mounted) {
        return;
      }
      if (!dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await appUpdateService.installApk(file);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (!dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showCopyableErrorSnackBar(error.toString());
    } finally {
      progress.dispose();
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) {
      return '${value.toStringAsFixed(0)} ${units[unitIndex]}';
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
