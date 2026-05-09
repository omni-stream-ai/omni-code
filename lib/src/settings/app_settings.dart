import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'app_settings_store.dart';

const _defaultUpdateManifestUrl =
    'https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json';
const _defaultNotificationMaxChars = 160;

enum TtsProvider { system, zhipu }

enum AsrProvider { system, zhipu, whisper }

enum AppThemeModeSetting { system, light, dark }

@immutable
class AppSettings {
  const AppSettings({
    required this.bridgeUrl,
    required this.bridgeToken,
    required this.clientId,
    required this.pendingClientAuthRequestId,
    required this.appLanguage,
    required this.themeMode,
    required this.ttsProvider,
    required this.asrProvider,
    required this.zhipuApiKey,
    required this.whisperApiKey,
    required this.whisperBaseUrl,
    required this.updateManifestUrl,
    required this.aiApprovalEnabled,
    required this.aiApprovalBaseUrl,
    required this.aiApprovalApiKey,
    required this.aiApprovalModel,
    required this.aiApprovalMaxRisk,
    required this.notificationMaxChars,
    required this.autoSpeakReplies,
    required this.compressAssistantReplies,
  });

  final String bridgeUrl;
  final String bridgeToken;
  final String clientId;
  final String pendingClientAuthRequestId;
  final String appLanguage;
  final AppThemeModeSetting themeMode;
  final TtsProvider ttsProvider;
  final AsrProvider asrProvider;
  final String zhipuApiKey;
  final String whisperApiKey;
  final String whisperBaseUrl;
  final String updateManifestUrl;
  final bool aiApprovalEnabled;
  final String aiApprovalBaseUrl;
  final String aiApprovalApiKey;
  final String aiApprovalModel;
  final String aiApprovalMaxRisk;
  final int notificationMaxChars;
  final bool autoSpeakReplies;
  final bool compressAssistantReplies;

  factory AppSettings.defaults() {
    const configuredUrl = String.fromEnvironment('ECHO_MATE_BRIDGE_URL');
    const updateManifestUrl = String.fromEnvironment(
      'ECHO_MATE_UPDATE_MANIFEST_URL',
      defaultValue: _defaultUpdateManifestUrl,
    );
    return AppSettings(
      bridgeUrl:
          configuredUrl.isNotEmpty ? configuredUrl : 'http://127.0.0.1:8787',
      bridgeToken: '',
      clientId: _generateClientId(),
      pendingClientAuthRequestId: '',
      appLanguage: 'system',
      themeMode: AppThemeModeSetting.system,
      ttsProvider: TtsProvider.system,
      asrProvider: AsrProvider.system,
      zhipuApiKey: '',
      whisperApiKey: '',
      whisperBaseUrl: 'https://api.openai.com/v1',
      updateManifestUrl: updateManifestUrl.trim().isNotEmpty
          ? updateManifestUrl.trim()
          : _defaultUpdateManifestUrl,
      aiApprovalEnabled: false,
      aiApprovalBaseUrl: 'https://api.openai.com/v1',
      aiApprovalApiKey: '',
      aiApprovalModel: 'gpt-4.1-mini',
      aiApprovalMaxRisk: 'low',
      notificationMaxChars: _defaultNotificationMaxChars,
      autoSpeakReplies: false,
      compressAssistantReplies: false,
    );
  }

  AppSettings copyWith({
    String? bridgeUrl,
    String? bridgeToken,
    String? clientId,
    String? pendingClientAuthRequestId,
    String? appLanguage,
    AppThemeModeSetting? themeMode,
    TtsProvider? ttsProvider,
    AsrProvider? asrProvider,
    String? zhipuApiKey,
    String? whisperApiKey,
    String? whisperBaseUrl,
    String? updateManifestUrl,
    bool? aiApprovalEnabled,
    String? aiApprovalBaseUrl,
    String? aiApprovalApiKey,
    String? aiApprovalModel,
    String? aiApprovalMaxRisk,
    int? notificationMaxChars,
    bool? autoSpeakReplies,
    bool? compressAssistantReplies,
  }) {
    return AppSettings(
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      bridgeToken: bridgeToken ?? this.bridgeToken,
      clientId: clientId ?? this.clientId,
      pendingClientAuthRequestId:
          pendingClientAuthRequestId ?? this.pendingClientAuthRequestId,
      appLanguage: _normalizeLanguage(appLanguage ?? this.appLanguage),
      themeMode: themeMode ?? this.themeMode,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      asrProvider: asrProvider ?? this.asrProvider,
      zhipuApiKey: zhipuApiKey ?? this.zhipuApiKey,
      whisperApiKey: whisperApiKey ?? this.whisperApiKey,
      whisperBaseUrl: whisperBaseUrl ?? this.whisperBaseUrl,
      updateManifestUrl: updateManifestUrl ?? this.updateManifestUrl,
      aiApprovalEnabled: aiApprovalEnabled ?? this.aiApprovalEnabled,
      aiApprovalBaseUrl: aiApprovalBaseUrl ?? this.aiApprovalBaseUrl,
      aiApprovalApiKey: aiApprovalApiKey ?? this.aiApprovalApiKey,
      aiApprovalModel: aiApprovalModel ?? this.aiApprovalModel,
      aiApprovalMaxRisk: aiApprovalMaxRisk ?? this.aiApprovalMaxRisk,
      notificationMaxChars: notificationMaxChars ?? this.notificationMaxChars,
      autoSpeakReplies: autoSpeakReplies ?? this.autoSpeakReplies,
      compressAssistantReplies:
          compressAssistantReplies ?? this.compressAssistantReplies,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bridge_url': bridgeUrl,
      'bridge_token': bridgeToken,
      'client_id': clientId,
      'pending_client_auth_request_id': pendingClientAuthRequestId,
      'app_language': appLanguage,
      'theme_mode': themeMode.name,
      'tts_provider': ttsProvider.name,
      'asr_provider': asrProvider.name,
      'zhipu_api_key': zhipuApiKey,
      'whisper_api_key': whisperApiKey,
      'whisper_base_url': whisperBaseUrl,
      'update_manifest_url': updateManifestUrl,
      'ai_approval_enabled': aiApprovalEnabled,
      'ai_approval_base_url': aiApprovalBaseUrl,
      'ai_approval_api_key': aiApprovalApiKey,
      'ai_approval_model': aiApprovalModel,
      'ai_approval_max_risk': aiApprovalMaxRisk,
      'notification_max_chars': notificationMaxChars,
      'auto_speak_replies': autoSpeakReplies,
      'compress_assistant_replies': compressAssistantReplies,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      bridgeUrl: _readString(json, 'bridge_url').trim().isNotEmpty
          ? _readString(json, 'bridge_url').trim()
          : defaults.bridgeUrl,
      bridgeToken: _readString(json, 'bridge_token'),
      clientId: _readString(json, 'client_id').trim().isNotEmpty
          ? _readString(json, 'client_id').trim()
          : _generateClientId(),
      pendingClientAuthRequestId:
          _readString(json, 'pending_client_auth_request_id').trim(),
      appLanguage: _normalizeLanguage(
        _readString(json, 'app_language', defaults.appLanguage),
      ),
      themeMode: _parseThemeMode(
        _readNullableString(json, 'theme_mode'),
        defaults.themeMode,
      ),
      ttsProvider: _parseTtsProvider(
          _readNullableString(json, 'tts_provider'), defaults.ttsProvider),
      asrProvider: _parseAsrProvider(
          _readNullableString(json, 'asr_provider'), defaults.asrProvider),
      zhipuApiKey: _readString(json, 'zhipu_api_key'),
      whisperApiKey: _readString(json, 'whisper_api_key'),
      whisperBaseUrl:
          _readString(json, 'whisper_base_url', defaults.whisperBaseUrl),
      updateManifestUrl:
          _readString(json, 'update_manifest_url').trim().isNotEmpty
              ? _readString(json, 'update_manifest_url').trim()
              : defaults.updateManifestUrl,
      aiApprovalEnabled:
          _readBool(json, 'ai_approval_enabled', defaults.aiApprovalEnabled),
      aiApprovalBaseUrl: _readString(
        json,
        'ai_approval_base_url',
        defaults.aiApprovalBaseUrl,
      ),
      aiApprovalApiKey: _readString(json, 'ai_approval_api_key'),
      aiApprovalModel:
          _readString(json, 'ai_approval_model', defaults.aiApprovalModel),
      aiApprovalMaxRisk: _normalizeRisk(
        _readString(json, 'ai_approval_max_risk', defaults.aiApprovalMaxRisk),
        defaults.aiApprovalMaxRisk,
      ),
      notificationMaxChars: _normalizeNotificationMaxChars(
        _readInt(
          json,
          'notification_max_chars',
          defaults.notificationMaxChars,
        ),
        defaults.notificationMaxChars,
      ),
      autoSpeakReplies:
          _readBool(json, 'auto_speak_replies', defaults.autoSpeakReplies),
      compressAssistantReplies: _readBool(
        json,
        'compress_assistant_replies',
        defaults.compressAssistantReplies,
      ),
    );
  }

  static String _readString(
    Map<String, dynamic> json,
    String key, [
    String fallback = '',
  ]) {
    final value = json[key];
    return value is String ? value : fallback;
  }

  static String? _readNullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  static int _readInt(
    Map<String, dynamic> json,
    String key, [
    int fallback = 0,
  ]) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  static bool _readBool(Map<String, dynamic> json, String key, bool fallback) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case '1':
        case 'true':
        case 'yes':
        case 'on':
          return true;
        case '0':
        case 'false':
        case 'no':
        case 'off':
          return false;
      }
    }
    return fallback;
  }

  static String _normalizeRisk(String value, String fallback) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'low' || 'medium' || 'high' => normalized,
      _ => fallback,
    };
  }

  static int _normalizeNotificationMaxChars(int value, int fallback) {
    return value > 0 ? value : fallback;
  }

  static String _normalizeLanguage(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'system' || 'en' || 'zh' => normalized,
      _ => 'system',
    };
  }

  static TtsProvider _parseTtsProvider(String? raw, TtsProvider fallback) {
    if (raw == 'bridge') {
      return fallback;
    }
    for (final item in TtsProvider.values) {
      if (item.name == raw) {
        return item;
      }
    }
    return fallback;
  }

  static AsrProvider _parseAsrProvider(String? raw, AsrProvider fallback) {
    if (raw == 'bridge') {
      return fallback;
    }
    for (final item in AsrProvider.values) {
      if (item.name == raw) {
        return item;
      }
    }
    return fallback;
  }

  static AppThemeModeSetting _parseThemeMode(
    String? raw,
    AppThemeModeSetting fallback,
  ) {
    for (final item in AppThemeModeSetting.values) {
      if (item.name == raw) {
        return item;
      }
    }
    return fallback;
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults();
  AppSettingsStore _store = createAppSettingsStore();

  AppSettings get settings => _settings;

  @visibleForTesting
  void debugReplaceSettings(AppSettings next) {
    _settings = next;
    notifyListeners();
  }

  @visibleForTesting
  void debugReplaceStore(AppSettingsStore store) {
    _store = store;
  }

  Future<void> load() async {
    var shouldPersist = false;
    try {
      final body = await _store.read();
      if (body == null) {
        _settings = AppSettings.defaults();
        shouldPersist = true;
      } else {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if ((json['client_id'] as String?)?.trim().isEmpty ?? true) {
          shouldPersist = true;
        }
        if (json['bridge_token'] == null) {
          shouldPersist = true;
        }
        if (json['pending_client_auth_request_id'] == null) {
          shouldPersist = true;
        }
        if (json['app_language'] == null) {
          shouldPersist = true;
        }
        if (json['theme_mode'] == null) {
          shouldPersist = true;
        }
        if (json['compress_assistant_replies'] == null) {
          shouldPersist = true;
        }
        if (json['tts_provider'] == 'bridge') {
          shouldPersist = true;
        }
        if (json['asr_provider'] == 'bridge') {
          shouldPersist = true;
        }
        final updateManifestUrl =
            (json['update_manifest_url'] as String?)?.trim() ?? '';
        if (json['update_manifest_url'] == null || updateManifestUrl.isEmpty) {
          shouldPersist = true;
        }
        if (json['ai_approval_enabled'] == null) {
          shouldPersist = true;
        }
        if (json['notification_max_chars'] == null) {
          shouldPersist = true;
        }
        _settings = AppSettings.fromJson(json);
      }
    } catch (error) {
      debugPrint(
          'Failed to load app settings, keeping current settings: $error');
      shouldPersist = false;
    }
    if (shouldPersist) {
      try {
        await _store.write(
          const JsonEncoder.withIndent('  ').convert(_settings.toJson()),
        );
      } catch (_) {
        // Best effort migration for local settings file.
      }
    }
    notifyListeners();
  }

  Future<void> save(AppSettings next) async {
    await _store
        .write(const JsonEncoder.withIndent('  ').convert(next.toJson()));
    _settings = next;
    notifyListeners();
  }
}

final appSettingsController = AppSettingsController();

String _generateClientId() {
  final random = Random.secure();
  final segments = List.generate(
    4,
    (_) => random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0'),
  );
  return 'omni-code-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${segments.join()}';
}
