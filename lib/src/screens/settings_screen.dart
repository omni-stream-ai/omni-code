import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../services/app_update_service.dart';
import '../settings/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bridgeUrlController = TextEditingController();
  final _bridgeTokenController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _zhipuApiKeyController = TextEditingController();
  final _whisperApiKeyController = TextEditingController();
  final _whisperBaseUrlController = TextEditingController();
  final _updateManifestUrlController = TextEditingController();
  final _aiApprovalBaseUrlController = TextEditingController();
  final _aiApprovalApiKeyController = TextEditingController();
  final _aiApprovalModelController = TextEditingController();

  late TtsProvider _ttsProvider;
  late AsrProvider _asrProvider;
  late bool _aiApprovalEnabled;
  late String _aiApprovalMaxRisk;
  late bool _autoSpeakReplies;
  late bool _compressAssistantReplies;
  late String _appLanguage;
  bool _saving = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    final settings = appSettingsController.settings;
    _bridgeUrlController.text = settings.bridgeUrl;
    _bridgeTokenController.text = settings.bridgeToken;
    _clientIdController.text = settings.clientId;
    _appLanguage = settings.appLanguage;
    _zhipuApiKeyController.text = settings.zhipuApiKey;
    _whisperApiKeyController.text = settings.whisperApiKey;
    _whisperBaseUrlController.text = settings.whisperBaseUrl;
    _updateManifestUrlController.text = settings.updateManifestUrl;
    _aiApprovalBaseUrlController.text = settings.aiApprovalBaseUrl;
    _aiApprovalApiKeyController.text = settings.aiApprovalApiKey;
    _aiApprovalModelController.text = settings.aiApprovalModel;
    _ttsProvider = settings.ttsProvider;
    _asrProvider = settings.asrProvider;
    _aiApprovalEnabled = settings.aiApprovalEnabled;
    _aiApprovalMaxRisk = settings.aiApprovalMaxRisk;
    _autoSpeakReplies = settings.autoSpeakReplies;
    _compressAssistantReplies = settings.compressAssistantReplies;
  }

  @override
  void dispose() {
    _bridgeUrlController.dispose();
    _bridgeTokenController.dispose();
    _clientIdController.dispose();
    _zhipuApiKeyController.dispose();
    _whisperApiKeyController.dispose();
    _whisperBaseUrlController.dispose();
    _updateManifestUrlController.dispose();
    _aiApprovalBaseUrlController.dispose();
    _aiApprovalApiKeyController.dispose();
    _aiApprovalModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? l10n.saving : l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(
            title: l10n.languageSection,
            child: DropdownButtonFormField<String>(
              initialValue: _appLanguage,
              decoration: InputDecoration(
                labelText: l10n.languageLabel,
                filled: true,
                fillColor: const Color(0xFF111827),
              ),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
                DropdownMenuItem(value: 'zh', child: Text(l10n.languageChinese)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _appLanguage = value;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: l10n.bridgeSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bridgeUrlLabel),
                const SizedBox(height: 8),
                TextField(
                  controller: _bridgeUrlController,
                  decoration: const InputDecoration(
                    hintText: 'http://127.0.0.1:8787',
                    filled: true,
                    fillColor: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bridgeTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Bridge Token',
                    filled: true,
                    fillColor: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientIdController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    suffixIcon: IconButton(
                      onPressed: _regenerateClientId,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.bridgeHelp,
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: l10n.appUpdateSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _updateManifestUrlController,
                  decoration: InputDecoration(
                    labelText: l10n.updateManifestUrlLabel,
                    hintText: 'https://example.com/omni-code-update.json',
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _saving || _checkingUpdate ? null : _checkAppUpdate,
                    icon: _checkingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt),
                    label: Text(
                      _checkingUpdate
                          ? l10n.checkingUpdate
                          : l10n.checkAppUpdate,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.updateHelp,
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: l10n.speechSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<TtsProvider>(
                  initialValue: _ttsProvider,
                  decoration: InputDecoration(
                    labelText: l10n.ttsProviderLabel,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: TtsProvider.bridge,
                      child: Text(l10n.bridgeCloudProxy),
                    ),
                    DropdownMenuItem(
                      value: TtsProvider.zhipu,
                      child: Text('Zhipu'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _ttsProvider = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AsrProvider>(
                  initialValue: _asrProvider,
                  decoration: InputDecoration(
                    labelText: l10n.asrProviderLabel,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: AsrProvider.bridge,
                      child: Text(l10n.bridgeCloudProxy),
                    ),
                    DropdownMenuItem(
                      value: AsrProvider.zhipu,
                      child: Text('Zhipu'),
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Zhipu',
            child: TextField(
              controller: _zhipuApiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                filled: true,
                fillColor: const Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Whisper',
            child: Column(
              children: [
                TextField(
                  controller: _whisperApiKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.apiKey,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _whisperBaseUrlController,
                  decoration: InputDecoration(
                    labelText: l10n.baseUrl,
                    hintText: 'https://api.openai.com/v1',
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: l10n.aiApprovalSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: _aiApprovalEnabled,
                  onChanged: (value) {
                    setState(() {
                      _aiApprovalEnabled = value;
                    });
                  },
                  title: Text(l10n.enableAiApproval),
                  subtitle: Text(l10n.enableAiApprovalSubtitle),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiApprovalBaseUrlController,
                  decoration: InputDecoration(
                    labelText: l10n.baseUrl,
                    hintText: 'https://api.openai.com/v1',
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aiApprovalApiKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.apiKey,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aiApprovalModelController,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'gpt-4.1-mini',
                    filled: true,
                    fillColor: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _aiApprovalMaxRisk,
                  decoration: InputDecoration(
                    labelText: l10n.aiApprovalMaxRisk,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                  ),
                  items: [
                    DropdownMenuItem(value: 'low', child: Text(l10n.riskLow)),
                    DropdownMenuItem(
                      value: 'medium',
                      child: Text(l10n.riskMedium),
                    ),
                    DropdownMenuItem(value: 'high', child: Text(l10n.riskHigh)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _aiApprovalMaxRisk = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.aiApprovalHelp,
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _autoSpeakReplies,
            onChanged: _saving
                ? null
                : (value) => _saveLocalToggle(
                      applyLocalState: () {
                        _autoSpeakReplies = value;
                      },
                      buildNextSettings: (settings) => settings.copyWith(
                        autoSpeakReplies: value,
                      ),
                    ),
            title: Text(l10n.autoSpeakReplies),
            subtitle: Text(l10n.autoSpeakRepliesSubtitle),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _compressAssistantReplies,
            onChanged: _saving
                ? null
                : (value) => _saveLocalToggle(
                      applyLocalState: () {
                        _compressAssistantReplies = value;
                      },
                      buildNextSettings: (settings) => settings.copyWith(
                        compressAssistantReplies: value,
                      ),
                    ),
            title: Text(l10n.compressReplies),
            subtitle: Text(l10n.compressRepliesSubtitle),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final next = appSettingsController.settings.copyWith(
        bridgeUrl: _bridgeUrlController.text.trim(),
        bridgeToken: _bridgeTokenController.text.trim(),
        clientId: _clientIdController.text.trim(),
        appLanguage: _appLanguage,
        ttsProvider: _ttsProvider,
        asrProvider: _asrProvider,
        zhipuApiKey: _zhipuApiKeyController.text.trim(),
        whisperApiKey: _whisperApiKeyController.text.trim(),
        whisperBaseUrl: _whisperBaseUrlController.text.trim(),
        updateManifestUrl: _updateManifestUrlController.text.trim(),
        aiApprovalEnabled: _aiApprovalEnabled,
        aiApprovalBaseUrl: _aiApprovalBaseUrlController.text.trim(),
        aiApprovalApiKey: _aiApprovalApiKeyController.text.trim(),
        aiApprovalModel: _aiApprovalModelController.text.trim(),
        aiApprovalMaxRisk: _aiApprovalMaxRisk,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsSaveFailed('$error'))),
      );
    }
  }

  void _regenerateClientId() {
    final next = AppSettings.defaults().clientId;
    setState(() {
      _clientIdController.text = next;
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

  String _resolvedUpdateManifestUrl() {
    final configured = _updateManifestUrlController.text.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    final bridgeUri = Uri.tryParse(_bridgeUrlController.text.trim());
    if (bridgeUri == null) {
      return '';
    }
    return bridgeUri.resolve('/app-update/manifest').toString();
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
                const SizedBox(height: 8),
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
                      const SizedBox(height: 12),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
