import 'package:flutter_test/flutter_test.dart';
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

  test('lastSelectedAgent defaults to codex', () {
    expect(AppSettings.defaults().lastSelectedAgent, 'codex');
  });

  test('missing last_selected_agent falls back to codex', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.lastSelectedAgent, 'codex');
  });

  test('lastSelectedAgent round-trips through json', () {
    final settings = AppSettings.defaults().copyWith(
      lastSelectedAgent: 'claude_code',
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.lastSelectedAgent, 'claude_code');
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
}
