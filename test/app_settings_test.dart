import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/settings/app_settings.dart';

void main() {
  test('autoSpeakReplies defaults to false', () {
    expect(AppSettings.defaults().autoSpeakReplies, isFalse);
  });

  test('missing auto_speak_replies falls back to false', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.autoSpeakReplies, isFalse);
  });

  test('speech playback prompt defaults to true', () {
    expect(AppSettings.defaults().speechPlaybackPromptEnabled, isTrue);
  });

  test('missing speech_playback_prompt_enabled falls back to true', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.speechPlaybackPromptEnabled, isTrue);
  });

  test('notificationMaxChars defaults to 150', () {
    expect(AppSettings.defaults().notificationMaxChars, 150);
  });

  test('missing notification_max_chars uses fixed default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.notificationMaxChars, 150);
  });

  test('legacy notification_max_chars is ignored', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'notification_max_chars': 240,
    });
    expect(settings.notificationMaxChars, 150);
  });

  test('notificationMaxChars is not persisted as a configurable setting', () {
    expect(
      AppSettings.defaults().toJson().containsKey('notification_max_chars'),
      isFalse,
    );
  });

  test('compressAssistantReplyMaxChars defaults to 50', () {
    expect(
      AppSettings.defaults().compressAssistantReplyMaxChars,
      defaultCompressAssistantReplyMaxChars,
    );
  });

  test('invalid compress_assistant_reply_max_chars falls back to default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'compress_assistant_reply_max_chars': 0,
    });
    expect(
      settings.compressAssistantReplyMaxChars,
      defaultCompressAssistantReplyMaxChars,
    );
  });

  test('bridge local speech providers round-trip through json', () {
    final settings = AppSettings.defaults().copyWith(
      asrProvider: AsrProvider.bridgeLocal,
      ttsProvider: TtsProvider.bridgeLocal,
      bridgeLocalTtsVoice: '2',
      bridgeLocalTtsStreaming: true,
      speechPlaybackPromptEnabled: false,
      compressAssistantReplyMaxChars: 80,
      callModeAllowInterruptions: false,
      callModeSpeechPauseMillis: 1800,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.asrProvider, AsrProvider.bridgeLocal);
    expect(restored.ttsProvider, TtsProvider.bridgeLocal);
    expect(restored.bridgeLocalTtsVoice, '2');
    expect(restored.bridgeLocalTtsStreaming, isTrue);
    expect(restored.speechPlaybackPromptEnabled, isFalse);
    expect(restored.compressAssistantReplyMaxChars, 80);
    expect(restored.callModeAllowInterruptions, isFalse);
    expect(restored.callModeSpeechPauseMillis, 1800);
  });

  test('legacy bridge provider value migrates to bridge local', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'asr_provider': 'bridge',
      'tts_provider': 'bridge',
    });

    expect(settings.asrProvider, AsrProvider.bridgeLocal);
    expect(settings.ttsProvider, TtsProvider.bridgeLocal);
  });

  test('removed speech provider values migrate to system', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'asr_provider': 'tencentCloudStreaming',
      'tts_provider': 'zhipu',
    });

    expect(settings.asrProvider, AsrProvider.system);
    expect(settings.ttsProvider, TtsProvider.system);
  });

  test('legacy whisper asr provider migrates to system', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'asr_provider': 'whisper',
      'whisper_api_key': 'legacy-key',
      'whisper_base_url': 'https://example.com/v1',
    });

    expect(settings.asrProvider, AsrProvider.system);
    expect(settings.whisperApiKey, 'legacy-key');
    expect(settings.whisperBaseUrl, 'https://example.com/v1');
  });

  test('updateTargetVersion defaults to empty string', () {
    expect(AppSettings.defaults().updateTargetVersion, isEmpty);
  });

  test('call mode interruption defaults to true', () {
    expect(AppSettings.defaults().callModeAllowInterruptions, isTrue);
  });

  test('call mode wake words default to English local KWS phrase', () {
    expect(AppSettings.defaults().callModeWakeWords, 'hey omni');
  });

  test('invalid call mode speech pause falls back to default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'call_mode_speech_pause_millis': 100,
    });
    expect(
      settings.callModeSpeechPauseMillis,
      defaultCallModeSpeechPauseMillis,
    );
  });

  test('reads and trims update_target_version', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'update_target_version': '  v0.2.1  ',
    });
    expect(settings.updateTargetVersion, 'v0.2.1');
  });

  test('lastSelectedAgent defaults to empty', () {
    expect(AppSettings.defaults().lastSelectedAgent, '');
  });

  test('missing last_selected_agent falls back to empty', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.lastSelectedAgent, '');
  });

  test('lastSelectedAgent round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      lastSelectedAgent: 'claude_code',
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.lastSelectedAgent, 'claude_code');
  });

  test('cachedAgents round-trip through json', () {
    final settings = AppSettings.defaults().copyWith(
      cachedAgents: const [
        AgentSummary(
          descriptor: AgentDescriptor(
            id: 'codex',
            label: 'Codex',
            aliases: ['codex'],
            defaultSelected: true,
            compatibleFormats: [ApiFormat.codex],
          ),
          installed: true,
          installHint: 'manual',
          installedPath: '/usr/local/bin/codex',
        ),
        AgentSummary(
          descriptor: AgentDescriptor(
            id: 'claude_code',
            label: 'Claude Code',
            aliases: ['claude_code'],
            selectable: false,
            compatibleFormats: [ApiFormat.anthropicMessages],
          ),
          installed: false,
          installHint: 'brew install claude-code',
        ),
      ],
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.cachedAgents, hasLength(2));
    expect(restored.cachedAgents.first.id, 'codex');
    expect(restored.cachedAgents.first.defaultSelected, isTrue);
    expect(restored.cachedAgents.first.installed, isTrue);
    expect(
      restored.cachedAgents.first.compatibleFormats,
      equals(const [ApiFormat.codex]),
    );
    expect(restored.cachedAgents.last.id, 'claude_code');
    expect(restored.cachedAgents.last.selectable, isFalse);
    expect(restored.cachedAgents.last.installed, isFalse);
    expect(
      restored.cachedAgents.last.compatibleFormats,
      equals(const [ApiFormat.anthropicMessages]),
    );
  });

  test('null cached_agents falls back to empty list', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'cached_agents': null,
    });
    expect(settings.cachedAgents, isEmpty);
  });

  test('lastSelectedProviderByProject round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      lastSelectedProviderByProject: const {
        'project-1': 'AUTO',
        'project-2': 'provider-2',
        'project-3': null,
      },
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.lastSelectedProviderByProject, {
      'project-1': 'AUTO',
      'project-2': 'provider-2',
      'project-3': null,
    });
  });

  test('null last_selected_provider_by_project falls back to empty map', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'last_selected_provider_by_project': null,
    });
    expect(settings.lastSelectedProviderByProject, isEmpty);
  });

  test('voiceComposerMode defaults to false', () {
    expect(AppSettings.defaults().voiceComposerMode, isFalse);
  });

  test('missing voice_composer_mode falls back to false', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.voiceComposerMode, isFalse);
  });

  test('voiceComposerMode round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      voiceComposerMode: true,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.voiceComposerMode, isTrue);
  });

  test('desktop session rail defaults to collapsed', () {
    expect(AppSettings.defaults().desktopSessionRailCollapsed, isTrue);
  });

  test('desktop home rail defaults to collapsed', () {
    expect(AppSettings.defaults().desktopHomeRailCollapsed, isTrue);
  });

  test('desktop home rail collapsed state round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      desktopHomeRailCollapsed: false,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.desktopHomeRailCollapsed, isFalse);
  });

  test('desktop session rail collapsed state round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      desktopSessionRailCollapsed: false,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.desktopSessionRailCollapsed, isFalse);
  });

  test('plugin settings round-trip through generic json keys', () {
    final settings = AppSettings.defaults().copyWith(
      pluginSources: const [
        {
          'id': 'official',
          'name': 'Official',
          'index_url': 'https://example.com/community-plugins.json',
          'enabled': true,
        },
        {
          'id': 'custom-1',
          'name': 'Custom',
          'index_url': 'https://example.com/custom.json',
          'enabled': true,
        },
      ],
      installedPlugins: const [
        {
          'installed_at': '2026-01-01T00:00:00.000Z',
          'manifest': {
            'id': 'plugin-1',
            'name': 'Plugin 1',
            'vendor': 'Vendor',
            'version': '1.0.0',
            'capabilities': ['speech.tts'],
            'transport': 'openai_compatible',
            'base_url': 'https://example.com/v1',
          },
        },
      ],
      selectedPluginByCapability: const {
        'speech.tts': 'plugin-1',
        'speech.batch_asr': 'plugin-2',
      },
      pluginSecretsByPluginId: const {
        'plugin-1': {
          'api_key': 'secret-1',
        },
      },
      pluginSettingsByPluginId: const {
        'plugin-1': {
          'model': 'ep-123',
          'start_command': 'bun run plugin:start',
          'stop_command': 'bun run plugin:stop',
        },
      },
    );

    final json = settings.toJson();
    final restored = AppSettings.fromJson(json);

    expect(json.containsKey('speech_plugin_sources'), isFalse);
    expect(json.containsKey('installed_speech_plugins'), isFalse);
    expect(json.containsKey('selected_speech_plugin_by_capability'), isFalse);
    expect(json.containsKey('speech_plugin_api_keys_by_plugin_id'), isFalse);
    expect(json.containsKey('speech_plugin_settings_by_plugin_id'), isFalse);
    expect(
      restored.pluginSources,
      hasLength(2),
    );
    expect(restored.installedPlugins, hasLength(1));
    expect(restored.selectedPluginByCapability, {
      'speech.tts': 'plugin-1',
      'speech.batch_asr': 'plugin-2',
    });
    expect(restored.pluginSecretsByPluginId, {
      'plugin-1': {
        'api_key': 'secret-1',
      },
    });
    expect(restored.pluginSettingsByPluginId, {
      'plugin-1': {
        'model': 'ep-123',
        'start_command': 'bun run plugin:start',
        'stop_command': 'bun run plugin:stop',
      },
    });
  });

  test('legacy speech plugin settings migrate to generic plugin settings', () {
    final restored = AppSettings.fromJson(<String, dynamic>{
      'speech_plugin_sources': [
        {
          'id': 'official',
          'name': 'Official',
          'index_url': 'https://example.com/community-plugins.json',
          'enabled': true,
        },
      ],
      'installed_speech_plugins': [
        {
          'installed_at': '2026-01-01T00:00:00.000Z',
          'manifest': {
            'id': 'plugin-1',
            'name': 'Plugin 1',
            'version': '1.0.0',
            'capabilities': ['speech.tts'],
          },
        },
      ],
      'selected_speech_plugin_by_capability': {
        'tts': 'plugin-1',
      },
      'speech_plugin_api_keys_by_plugin_id': {
        'plugin-1': 'secret-1',
      },
      'speech_plugin_settings_by_plugin_id': {
        'plugin-1': {
          'model': 'ep-123',
        },
      },
    });

    expect(restored.pluginSources, hasLength(1));
    expect(restored.installedPlugins, hasLength(1));
    expect(restored.selectedPluginByCapability, {'speech.tts': 'plugin-1'});
    expect(restored.pluginSecretsByPluginId, {
      'plugin-1': {'api_key': 'secret-1'},
    });
    expect(restored.pluginSettingsByPluginId, {
      'plugin-1': {'model': 'ep-123'},
    });
  });
}
