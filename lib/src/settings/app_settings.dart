import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../plugins/speech_plugin_models.dart';
import '../plugins/speech_plugin_registry.dart';
import 'app_settings_store.dart';

const _defaultUpdateManifestUrl =
    'https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json';
const _defaultNotificationMaxChars = 150;
const int defaultCompressAssistantReplyMaxChars = 50;
const int defaultCallModeSpeechPauseMillis = 1200;
const int minCallModeSpeechPauseMillis = 600;
const int maxCallModeSpeechPauseMillis = 2400;
const String defaultCallModeWakeWords = 'hey omni';

enum TtsProvider { system, bridgeLocal }

enum AsrProvider {
  system,
  bridgeLocal,
  whisper,
}

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
    required this.bridgeLocalTtsVoice,
    required this.bridgeLocalTtsStreaming,
    required this.asrProvider,
    required this.whisperApiKey,
    required this.whisperBaseUrl,
    required this.updateManifestUrl,
    required this.updateTargetVersion,
    required this.aiApprovalEnabled,
    required this.aiApprovalBaseUrl,
    required this.aiApprovalApiKey,
    required this.aiApprovalModel,
    required this.aiApprovalMaxRisk,
    required this.notificationMaxChars,
    required this.autoSpeakReplies,
    required this.speechPlaybackPromptEnabled,
    required this.compressAssistantReplies,
    required this.compressAssistantReplyMaxChars,
    required this.callModeAllowInterruptions,
    required this.callModeSpeechPauseMillis,
    required this.callModeWakeWordEnabled,
    required this.callModeWakeWords,
    required this.lastSelectedAgent,
    required this.cachedAgents,
    required this.lastSelectedProviderByProject,
    required this.desktopNavigationCollapsed,
    required this.desktopHomeRailCollapsed,
    required this.desktopSessionRailCollapsed,
    required this.voiceComposerMode,
    required this.videoPreviewMuted,
    required this.pluginSources,
    required this.installedPlugins,
    required this.selectedPluginByCapability,
    required this.pluginSecretsByPluginId,
    required this.pluginSettingsByPluginId,
  });

  final String bridgeUrl;
  final String bridgeToken;
  final String clientId;
  final String pendingClientAuthRequestId;
  final String appLanguage;
  final AppThemeModeSetting themeMode;
  final TtsProvider ttsProvider;
  final String bridgeLocalTtsVoice;
  final bool bridgeLocalTtsStreaming;
  final AsrProvider asrProvider;
  final String whisperApiKey;
  final String whisperBaseUrl;
  final String updateManifestUrl;
  final String updateTargetVersion;
  final bool aiApprovalEnabled;
  final String aiApprovalBaseUrl;
  final String aiApprovalApiKey;
  final String aiApprovalModel;
  final String aiApprovalMaxRisk;
  final int notificationMaxChars;
  final bool autoSpeakReplies;
  final bool speechPlaybackPromptEnabled;
  final bool compressAssistantReplies;
  final int compressAssistantReplyMaxChars;
  final bool callModeAllowInterruptions;
  final int callModeSpeechPauseMillis;
  final bool callModeWakeWordEnabled;
  final String callModeWakeWords;
  final String lastSelectedAgent;
  final List<AgentSummary> cachedAgents;
  final Map<String, String?> lastSelectedProviderByProject;
  final bool desktopNavigationCollapsed;
  final bool desktopHomeRailCollapsed;
  final bool desktopSessionRailCollapsed;
  final bool voiceComposerMode;
  final bool videoPreviewMuted;
  final List<Map<String, dynamic>> pluginSources;
  final List<Map<String, dynamic>> installedPlugins;
  final Map<String, String?> selectedPluginByCapability;
  final Map<String, Map<String, String>> pluginSecretsByPluginId;
  final Map<String, Map<String, String>> pluginSettingsByPluginId;

  List<Map<String, dynamic>> get speechPluginSources => pluginSources;
  List<Map<String, dynamic>> get installedSpeechPlugins => installedPlugins;
  Map<String, String?> get selectedSpeechPluginByCapability =>
      selectedPluginByCapability;
  Map<String, Map<String, String>> get speechPluginSettingsByPluginId =>
      pluginSettingsByPluginId;
  Map<String, String> get speechPluginApiKeysByPluginId {
    final result = <String, String>{};
    for (final entry in pluginSecretsByPluginId.entries) {
      final apiKey = entry.value['api_key']?.trim() ?? '';
      if (apiKey.isNotEmpty) {
        result[entry.key] = apiKey;
      }
    }
    return Map<String, String>.unmodifiable(result);
  }

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
      bridgeLocalTtsVoice: '',
      bridgeLocalTtsStreaming: false,
      asrProvider: AsrProvider.system,
      whisperApiKey: '',
      whisperBaseUrl: 'https://api.openai.com/v1',
      updateManifestUrl: updateManifestUrl.trim().isNotEmpty
          ? updateManifestUrl.trim()
          : _defaultUpdateManifestUrl,
      updateTargetVersion: '',
      aiApprovalEnabled: false,
      aiApprovalBaseUrl: 'https://api.openai.com/v1',
      aiApprovalApiKey: '',
      aiApprovalModel: 'gpt-4.1-mini',
      aiApprovalMaxRisk: 'low',
      notificationMaxChars: _defaultNotificationMaxChars,
      autoSpeakReplies: false,
      speechPlaybackPromptEnabled: true,
      compressAssistantReplies: false,
      compressAssistantReplyMaxChars: defaultCompressAssistantReplyMaxChars,
      callModeAllowInterruptions: true,
      callModeSpeechPauseMillis: defaultCallModeSpeechPauseMillis,
      callModeWakeWordEnabled: false,
      callModeWakeWords: defaultCallModeWakeWords,
      lastSelectedAgent: '',
      cachedAgents: const [],
      lastSelectedProviderByProject: const {},
      desktopNavigationCollapsed: false,
      desktopHomeRailCollapsed: true,
      desktopSessionRailCollapsed: true,
      voiceComposerMode: false,
      videoPreviewMuted: true,
      pluginSources: const [
        {
          'id': defaultSpeechPluginRepositorySourceId,
          'name': defaultSpeechPluginRepositorySourceName,
          'index_url': defaultSpeechPluginRepositoryIndexUrl,
          'enabled': true,
        },
      ],
      installedPlugins: const [],
      selectedPluginByCapability: const {},
      pluginSecretsByPluginId: const {},
      pluginSettingsByPluginId: const {},
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
    String? bridgeLocalTtsVoice,
    bool? bridgeLocalTtsStreaming,
    AsrProvider? asrProvider,
    String? whisperApiKey,
    String? whisperBaseUrl,
    String? updateManifestUrl,
    String? updateTargetVersion,
    bool? aiApprovalEnabled,
    String? aiApprovalBaseUrl,
    String? aiApprovalApiKey,
    String? aiApprovalModel,
    String? aiApprovalMaxRisk,
    int? notificationMaxChars,
    bool? autoSpeakReplies,
    bool? speechPlaybackPromptEnabled,
    bool? compressAssistantReplies,
    int? compressAssistantReplyMaxChars,
    bool? callModeAllowInterruptions,
    int? callModeSpeechPauseMillis,
    bool? callModeWakeWordEnabled,
    String? callModeWakeWords,
    String? lastSelectedAgent,
    List<AgentSummary>? cachedAgents,
    Map<String, String?>? lastSelectedProviderByProject,
    bool? desktopNavigationCollapsed,
    bool? desktopHomeRailCollapsed,
    bool? desktopSessionRailCollapsed,
    bool? voiceComposerMode,
    bool? videoPreviewMuted,
    List<Map<String, dynamic>>? pluginSources,
    List<Map<String, dynamic>>? installedPlugins,
    Map<String, String?>? selectedPluginByCapability,
    Map<String, Map<String, String>>? pluginSecretsByPluginId,
    Map<String, Map<String, String>>? pluginSettingsByPluginId,
    List<Map<String, dynamic>>? speechPluginSources,
    List<Map<String, dynamic>>? installedSpeechPlugins,
    Map<String, String?>? selectedSpeechPluginByCapability,
    Map<String, String>? speechPluginApiKeysByPluginId,
    Map<String, Map<String, String>>? speechPluginSettingsByPluginId,
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
      bridgeLocalTtsVoice:
          (bridgeLocalTtsVoice ?? this.bridgeLocalTtsVoice).trim(),
      bridgeLocalTtsStreaming:
          bridgeLocalTtsStreaming ?? this.bridgeLocalTtsStreaming,
      asrProvider: asrProvider ?? this.asrProvider,
      whisperApiKey: whisperApiKey ?? this.whisperApiKey,
      whisperBaseUrl: whisperBaseUrl ?? this.whisperBaseUrl,
      updateManifestUrl: updateManifestUrl ?? this.updateManifestUrl,
      updateTargetVersion: updateTargetVersion ?? this.updateTargetVersion,
      aiApprovalEnabled: aiApprovalEnabled ?? this.aiApprovalEnabled,
      aiApprovalBaseUrl: aiApprovalBaseUrl ?? this.aiApprovalBaseUrl,
      aiApprovalApiKey: aiApprovalApiKey ?? this.aiApprovalApiKey,
      aiApprovalModel: aiApprovalModel ?? this.aiApprovalModel,
      aiApprovalMaxRisk: aiApprovalMaxRisk ?? this.aiApprovalMaxRisk,
      notificationMaxChars: notificationMaxChars ?? this.notificationMaxChars,
      autoSpeakReplies: autoSpeakReplies ?? this.autoSpeakReplies,
      speechPlaybackPromptEnabled:
          speechPlaybackPromptEnabled ?? this.speechPlaybackPromptEnabled,
      compressAssistantReplies:
          compressAssistantReplies ?? this.compressAssistantReplies,
      compressAssistantReplyMaxChars: _normalizePositiveInt(
        compressAssistantReplyMaxChars ?? this.compressAssistantReplyMaxChars,
        this.compressAssistantReplyMaxChars,
      ),
      callModeAllowInterruptions:
          callModeAllowInterruptions ?? this.callModeAllowInterruptions,
      callModeSpeechPauseMillis: _normalizeCallModeSpeechPauseMillis(
        callModeSpeechPauseMillis ?? this.callModeSpeechPauseMillis,
        this.callModeSpeechPauseMillis,
      ),
      callModeWakeWordEnabled:
          callModeWakeWordEnabled ?? this.callModeWakeWordEnabled,
      callModeWakeWords: _normalizeCallModeWakeWords(
          callModeWakeWords ?? this.callModeWakeWords),
      lastSelectedAgent: lastSelectedAgent ?? this.lastSelectedAgent,
      cachedAgents:
          List<AgentSummary>.unmodifiable(cachedAgents ?? this.cachedAgents),
      lastSelectedProviderByProject: Map<String, String?>.unmodifiable(
        lastSelectedProviderByProject ?? this.lastSelectedProviderByProject,
      ),
      desktopNavigationCollapsed:
          desktopNavigationCollapsed ?? this.desktopNavigationCollapsed,
      desktopHomeRailCollapsed:
          desktopHomeRailCollapsed ?? this.desktopHomeRailCollapsed,
      desktopSessionRailCollapsed:
          desktopSessionRailCollapsed ?? this.desktopSessionRailCollapsed,
      voiceComposerMode: voiceComposerMode ?? this.voiceComposerMode,
      videoPreviewMuted: videoPreviewMuted ?? this.videoPreviewMuted,
      pluginSources: List<Map<String, dynamic>>.unmodifiable(
        pluginSources ?? speechPluginSources ?? this.pluginSources,
      ),
      installedPlugins: List<Map<String, dynamic>>.unmodifiable(
        installedPlugins ?? installedSpeechPlugins ?? this.installedPlugins,
      ),
      selectedPluginByCapability: Map<String, String?>.unmodifiable(
        _normalizeSelectedPluginByCapability(
          selectedPluginByCapability ??
              selectedSpeechPluginByCapability ??
              this.selectedPluginByCapability,
        ),
      ),
      pluginSecretsByPluginId: _normalizeNestedStringMap(
        pluginSecretsByPluginId ??
            (speechPluginApiKeysByPluginId == null
                ? null
                : _mergeApiKeysIntoPluginSecrets(
                    this.pluginSecretsByPluginId,
                    speechPluginApiKeysByPluginId,
                  )) ??
            this.pluginSecretsByPluginId,
      ),
      pluginSettingsByPluginId: _normalizeNestedStringMap(
        pluginSettingsByPluginId ??
            speechPluginSettingsByPluginId ??
            this.pluginSettingsByPluginId,
      ),
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
      'bridge_local_tts_voice': bridgeLocalTtsVoice,
      'bridge_local_tts_streaming': bridgeLocalTtsStreaming,
      'asr_provider': asrProvider.name,
      'whisper_api_key': whisperApiKey,
      'whisper_base_url': whisperBaseUrl,
      'update_manifest_url': updateManifestUrl,
      'update_target_version': updateTargetVersion,
      'ai_approval_enabled': aiApprovalEnabled,
      'ai_approval_base_url': aiApprovalBaseUrl,
      'ai_approval_api_key': aiApprovalApiKey,
      'ai_approval_model': aiApprovalModel,
      'ai_approval_max_risk': aiApprovalMaxRisk,
      'auto_speak_replies': autoSpeakReplies,
      'speech_playback_prompt_enabled': speechPlaybackPromptEnabled,
      'compress_assistant_replies': compressAssistantReplies,
      'compress_assistant_reply_max_chars': compressAssistantReplyMaxChars,
      'call_mode_allow_interruptions': callModeAllowInterruptions,
      'call_mode_speech_pause_millis': callModeSpeechPauseMillis,
      'call_mode_wake_word_enabled': callModeWakeWordEnabled,
      'call_mode_wake_words': callModeWakeWords,
      'last_selected_agent': lastSelectedAgent,
      'cached_agents': [
        for (final agent in cachedAgents) agent.toJson(),
      ],
      'last_selected_provider_by_project': lastSelectedProviderByProject,
      'desktop_navigation_collapsed': desktopNavigationCollapsed,
      'desktop_home_rail_collapsed': desktopHomeRailCollapsed,
      'desktop_session_rail_collapsed': desktopSessionRailCollapsed,
      'voice_composer_mode': voiceComposerMode,
      'video_preview_muted': videoPreviewMuted,
      'plugin_sources': pluginSources,
      'installed_plugins': installedPlugins,
      'selected_plugin_by_capability': selectedPluginByCapability,
      'plugin_secrets_by_plugin_id': pluginSecretsByPluginId,
      'plugin_settings_by_plugin_id': pluginSettingsByPluginId,
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
      bridgeLocalTtsVoice: _readString(json, 'bridge_local_tts_voice').trim(),
      bridgeLocalTtsStreaming: _readBool(
        json,
        'bridge_local_tts_streaming',
        defaults.bridgeLocalTtsStreaming,
      ),
      asrProvider: _parseAsrProvider(
          _readNullableString(json, 'asr_provider'), defaults.asrProvider),
      whisperApiKey: _readString(json, 'whisper_api_key'),
      whisperBaseUrl:
          _readString(json, 'whisper_base_url', defaults.whisperBaseUrl),
      updateManifestUrl:
          _readString(json, 'update_manifest_url').trim().isNotEmpty
              ? _readString(json, 'update_manifest_url').trim()
              : defaults.updateManifestUrl,
      updateTargetVersion: _readString(json, 'update_target_version').trim(),
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
      notificationMaxChars: defaults.notificationMaxChars,
      autoSpeakReplies:
          _readBool(json, 'auto_speak_replies', defaults.autoSpeakReplies),
      speechPlaybackPromptEnabled: _readBool(
        json,
        'speech_playback_prompt_enabled',
        defaults.speechPlaybackPromptEnabled,
      ),
      compressAssistantReplies: _readBool(
        json,
        'compress_assistant_replies',
        defaults.compressAssistantReplies,
      ),
      compressAssistantReplyMaxChars: _normalizePositiveInt(
        _readInt(
          json,
          'compress_assistant_reply_max_chars',
          defaults.compressAssistantReplyMaxChars,
        ),
        defaults.compressAssistantReplyMaxChars,
      ),
      callModeAllowInterruptions: _readBool(
        json,
        'call_mode_allow_interruptions',
        defaults.callModeAllowInterruptions,
      ),
      callModeSpeechPauseMillis: _normalizeCallModeSpeechPauseMillis(
        _readInt(
          json,
          'call_mode_speech_pause_millis',
          defaults.callModeSpeechPauseMillis,
        ),
        defaults.callModeSpeechPauseMillis,
      ),
      callModeWakeWordEnabled: _readBool(
        json,
        'call_mode_wake_word_enabled',
        defaults.callModeWakeWordEnabled,
      ),
      callModeWakeWords: _normalizeCallModeWakeWords(
        _readString(
          json,
          'call_mode_wake_words',
          defaults.callModeWakeWords,
        ),
      ),
      lastSelectedAgent: _readString(
        json,
        'last_selected_agent',
        defaults.lastSelectedAgent,
      ),
      cachedAgents: List<AgentSummary>.unmodifiable(
        _readAgentSummaries(json, 'cached_agents'),
      ),
      lastSelectedProviderByProject: Map<String, String?>.unmodifiable(
        _readNullableStringMap(
          json,
          'last_selected_provider_by_project',
        ),
      ),
      desktopNavigationCollapsed: _readBool(
        json,
        'desktop_navigation_collapsed',
        defaults.desktopNavigationCollapsed,
      ),
      desktopHomeRailCollapsed: _readBool(
        json,
        'desktop_home_rail_collapsed',
        defaults.desktopHomeRailCollapsed,
      ),
      desktopSessionRailCollapsed: _readBool(
        json,
        'desktop_session_rail_collapsed',
        defaults.desktopSessionRailCollapsed,
      ),
      voiceComposerMode: _readBool(
        json,
        'voice_composer_mode',
        defaults.voiceComposerMode,
      ),
      videoPreviewMuted: _readBool(
        json,
        'video_preview_muted',
        defaults.videoPreviewMuted,
      ),
      pluginSources: List<Map<String, dynamic>>.unmodifiable(
        _readPluginSources(json, defaults.pluginSources),
      ),
      installedPlugins: List<Map<String, dynamic>>.unmodifiable(
        _readPluginList(json),
      ),
      selectedPluginByCapability: Map<String, String?>.unmodifiable(
        _readSelectedPluginByCapability(json),
      ),
      pluginSecretsByPluginId: _normalizeNestedStringMap(
        _readPluginSecretsByPluginId(json),
      ),
      pluginSettingsByPluginId: _normalizeNestedStringMap(
        _readPluginSettingsByPluginId(json),
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

  static Map<String, String?> _readNullableStringMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: switch (entry.value) {
            null => null,
            String stringValue => stringValue,
            _ => entry.value.toString(),
          },
    };
  }

  static List<AgentSummary> _readAgentSummaries(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => AgentSummary.fromJson(
            Map<String, dynamic>.from(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, String> _readStringMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) {
      return const {};
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        continue;
      }
      final nextValue = entry.value?.toString().trim() ?? '';
      if (nextValue.isEmpty) {
        continue;
      }
      result[entry.key as String] = nextValue;
    }
    return result;
  }

  static Map<String, Map<String, String>> _readNestedStringMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) {
      return const {};
    }
    final result = <String, Map<String, String>>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! Map) {
        continue;
      }
      final normalized = <String, String>{};
      for (final child in (entry.value as Map).entries) {
        if (child.key is! String) {
          continue;
        }
        final nextValue = child.value?.toString().trim() ?? '';
        if (nextValue.isEmpty) {
          continue;
        }
        normalized[child.key as String] = nextValue;
      }
      result[entry.key as String] = normalized;
    }
    return result;
  }

  static List<Map<String, dynamic>> _readJsonObjectList(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _readPluginSources(
    Map<String, dynamic> json,
    List<Map<String, dynamic>> fallback,
  ) {
    final sources = _readJsonObjectList(json, 'plugin_sources');
    if (sources.isNotEmpty) {
      return sources;
    }

    final legacySources = _readJsonObjectList(json, 'speech_plugin_sources');
    if (legacySources.isNotEmpty) {
      return legacySources;
    }

    final legacyUrl = _readString(json, 'speech_plugin_repository_url').trim();
    if (legacyUrl.isNotEmpty) {
      return [
        const SpeechPluginSource(
          id: defaultSpeechPluginRepositorySourceId,
          name: defaultSpeechPluginRepositorySourceName,
          indexUrl: defaultSpeechPluginRepositoryIndexUrl,
        ).toJson(),
        SpeechPluginSource(
          id: 'custom-1',
          name: 'Custom',
          indexUrl: legacyUrl,
        ).toJson(),
      ];
    }

    return fallback;
  }

  static List<Map<String, dynamic>> _readPluginList(
    Map<String, dynamic> json,
  ) {
    final plugins = _readJsonObjectList(json, 'installed_plugins');
    if (plugins.isNotEmpty) {
      return plugins;
    }
    return _readJsonObjectList(json, 'installed_speech_plugins');
  }

  static Map<String, String?> _readSelectedPluginByCapability(
    Map<String, dynamic> json,
  ) {
    final selected = _readNullableStringMap(
      json,
      'selected_plugin_by_capability',
    );
    if (selected.isNotEmpty) {
      return _normalizeSelectedPluginByCapability(selected);
    }
    return _normalizeSelectedPluginByCapability(
      _readNullableStringMap(
        json,
        'selected_speech_plugin_by_capability',
      ),
    );
  }

  static Map<String, String?> _normalizeSelectedPluginByCapability(
    Map<String, String?> selected,
  ) {
    final result = <String, String?>{};
    for (final entry in selected.entries) {
      final capabilityId = switch (entry.key) {
        'realtime_asr' => SpeechPluginCapability.realtimeAsr.id,
        'batch_asr' => SpeechPluginCapability.batchAsr.id,
        'tts' => SpeechPluginCapability.tts.id,
        _ => entry.key,
      };
      result[capabilityId] = entry.value;
    }
    return result;
  }

  static Map<String, Map<String, String>> _readPluginSecretsByPluginId(
    Map<String, dynamic> json,
  ) {
    final secrets = _readNestedStringMap(json, 'plugin_secrets_by_plugin_id');
    if (secrets.isNotEmpty) {
      return secrets;
    }
    return _apiKeysToPluginSecrets(
      _readStringMap(json, 'speech_plugin_api_keys_by_plugin_id'),
    );
  }

  static Map<String, Map<String, String>> _readPluginSettingsByPluginId(
    Map<String, dynamic> json,
  ) {
    final settings = _readNestedStringMap(json, 'plugin_settings_by_plugin_id');
    if (settings.isNotEmpty) {
      return settings;
    }
    return _readNestedStringMap(json, 'speech_plugin_settings_by_plugin_id');
  }

  static Map<String, Map<String, String>> _apiKeysToPluginSecrets(
    Map<String, String> apiKeysByPluginId,
  ) {
    return {
      for (final entry in apiKeysByPluginId.entries)
        if (entry.value.trim().isNotEmpty)
          entry.key: {'api_key': entry.value.trim()},
    };
  }

  static Map<String, Map<String, String>> _mergeApiKeysIntoPluginSecrets(
    Map<String, Map<String, String>> current,
    Map<String, String> apiKeysByPluginId,
  ) {
    final result = {
      for (final entry in current.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
    final activePluginIds = apiKeysByPluginId.keys.toSet();
    for (final pluginId in result.keys.toList()) {
      if (!activePluginIds.contains(pluginId)) {
        result.remove(pluginId);
      }
    }
    for (final entry in apiKeysByPluginId.entries) {
      final apiKey = entry.value.trim();
      if (apiKey.isEmpty) {
        result.remove(entry.key);
      } else {
        result[entry.key] = {
          ...(result[entry.key] ?? const <String, String>{}),
          'api_key': apiKey,
        };
      }
    }
    return result;
  }

  static Map<String, Map<String, String>> _normalizeNestedStringMap(
    Map<String, Map<String, String>> value,
  ) {
    return Map<String, Map<String, String>>.unmodifiable(
      value.map(
        (key, child) => MapEntry(
          key,
          Map<String, String>.unmodifiable(child),
        ),
      ),
    );
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

  static int _normalizePositiveInt(int value, int fallback) {
    return value > 0 ? value : fallback;
  }

  static int _normalizeCallModeSpeechPauseMillis(int value, int fallback) {
    if (value < minCallModeSpeechPauseMillis ||
        value > maxCallModeSpeechPauseMillis) {
      return fallback;
    }
    return value;
  }

  static String _normalizeCallModeWakeWords(String value) {
    final words = value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return defaultCallModeWakeWords;
    }
    return words.join(', ');
  }

  static String _normalizeLanguage(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'system' || 'en' || 'zh' => normalized,
      _ => 'system',
    };
  }

  static TtsProvider _parseTtsProvider(String? raw, TtsProvider fallback) {
    if (raw == 'zhipu') {
      return TtsProvider.system;
    }
    for (final item in TtsProvider.values) {
      if (item.name == raw) {
        return item;
      }
    }
    return fallback;
  }

  static AsrProvider _parseAsrProvider(String? raw, AsrProvider fallback) {
    if (raw == 'whisper' || raw == 'zhipu' || raw == 'tencentCloudStreaming') {
      return AsrProvider.system;
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
  AppSettings? _persistedSettingsOverrideBase;

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
        if (json['call_mode_allow_interruptions'] == null) {
          shouldPersist = true;
        }
        if (json['call_mode_speech_pause_millis'] == null) {
          shouldPersist = true;
        }
        if (json.containsKey('call_mode_vad_silence_millis')) {
          shouldPersist = true;
        }
        if (json['bridge_local_tts_streaming'] == null) {
          shouldPersist = true;
        }
        if (json['video_preview_muted'] == null) {
          shouldPersist = true;
        }
        if (json['tts_provider'] == 'bridge') {
          shouldPersist = true;
        }
        if (json['asr_provider'] == 'bridge') {
          shouldPersist = true;
        }
        if (json['tts_provider'] == 'zhipu' ||
            json['asr_provider'] == 'zhipu' ||
            json['asr_provider'] == 'tencentCloudStreaming' ||
            json.containsKey('zhipu_api_key') ||
            json.containsKey('tencent_cloud_app_id') ||
            json.containsKey('tencent_cloud_secret_id') ||
            json.containsKey('tencent_cloud_secret_key')) {
          shouldPersist = true;
        }
        final updateManifestUrl =
            (json['update_manifest_url'] as String?)?.trim() ?? '';
        if (json['update_manifest_url'] == null || updateManifestUrl.isEmpty) {
          shouldPersist = true;
        }
        if (json['update_target_version'] == null) {
          shouldPersist = true;
        }
        if (json['ai_approval_enabled'] == null) {
          shouldPersist = true;
        }
        if (json.containsKey('notification_max_chars')) {
          shouldPersist = true;
        }
        if (json['compress_assistant_reply_max_chars'] == null) {
          shouldPersist = true;
        }
        if (json['last_selected_agent'] == null) {
          shouldPersist = true;
        }
        if (json['cached_agents'] == null) {
          shouldPersist = true;
        }
        if (json['voice_composer_mode'] == null) {
          shouldPersist = true;
        }
        if (json['desktop_navigation_collapsed'] == null) {
          shouldPersist = true;
        }
        if (json['desktop_home_rail_collapsed'] == null) {
          shouldPersist = true;
        }
        if (json['desktop_session_rail_collapsed'] == null) {
          shouldPersist = true;
        }
        if (json['plugin_sources'] == null ||
            json.containsKey('speech_plugin_sources') ||
            json.containsKey('speech_plugin_repository_url')) {
          shouldPersist = true;
        }
        if (json['installed_plugins'] == null ||
            json.containsKey('installed_speech_plugins')) {
          shouldPersist = true;
        }
        if (json['selected_plugin_by_capability'] == null ||
            json.containsKey('selected_speech_plugin_by_capability')) {
          shouldPersist = true;
        }
        if (json['plugin_secrets_by_plugin_id'] == null ||
            json.containsKey('speech_plugin_api_keys_by_plugin_id')) {
          shouldPersist = true;
        }
        if (json['plugin_settings_by_plugin_id'] == null ||
            json.containsKey('speech_plugin_settings_by_plugin_id')) {
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
    _persistedSettingsOverrideBase = null;
    notifyListeners();
  }

  void pushEphemeralSettings(AppSettings next) {
    _persistedSettingsOverrideBase ??= _settings;
    _settings = next;
    notifyListeners();
  }

  void popEphemeralSettings() {
    final base = _persistedSettingsOverrideBase;
    if (base == null) {
      return;
    }
    _persistedSettingsOverrideBase = null;
    _settings = base;
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
