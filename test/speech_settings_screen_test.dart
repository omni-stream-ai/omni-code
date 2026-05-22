import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/speech_settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('shows Linux system speech availability hints', (tester) async {
    await tester.pumpWidget(
      const _TestApp(
        home: SpeechSettingsScreen(
          debugPlatformOverride: TargetPlatform.linux,
          debugIsWebOverride: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'System TTS is not available on Linux yet. Choose a cloud provider to enable playback.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'System ASR is not available on Linux yet. Choose a cloud provider to enable voice input.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'uses the same value text style for speech dropdowns and text fields',
    (tester) async {
      await tester.pumpWidget(
        const _TestApp(
          home: SpeechSettingsScreen(),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      final dropdown = tester.widget<DropdownButton<TtsProvider>>(
        find
            .byWidgetPredicate(
              (widget) => widget is DropdownButton<TtsProvider>,
            )
            .first,
      );

      expect(textField.style, isNotNull);
      expect(dropdown.style, equals(textField.style));
    },
  );

  testWidgets('speech provider pickers omit removed cloud providers',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('System').last);
    await tester.pumpAndSettle();

    expect(find.text('Whisper / OpenAI Compatible'), findsOneWidget);
    expect(find.text('Tencent Cloud Streaming'), findsNothing);
    expect(find.text('Zhipu'), findsNothing);
    expect(find.widgetWithText(TextField, 'App ID'), findsNothing);
    expect(find.widgetWithText(TextField, 'Secret ID'), findsNothing);
    expect(find.widgetWithText(TextField, 'Secret Key'), findsNothing);
  });

  testWidgets('shows Omni Bridge Local model, voice, and call mode cards',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('LOCAL BRIDGE MODELS'), findsOneWidget);
    expect(find.text('Batch ASR'), findsWidgets);
    expect(find.text('Realtime ASR'), findsWidgets);
    expect(find.text('TTS'), findsWidgets);
    expect(find.text('VAD'), findsWidgets);
    expect(find.text('Bridge details'), findsOneWidget);
    expect(find.text('streaming-paraformer-zh-en · 220 MB'), findsOneWidget);
    expect(find.text('vits-melo-tts-zh-en · 320 MB'), findsWidgets);
    expect(find.text('sensevoice-small-int8 · 180 MB'), findsOneWidget);
    expect(find.text('silero-vad · 12 MB'), findsOneWidget);
    expect(find.text('Omni Bridge Local'), findsWidgets);
    expect(find.text('TTS VOICE'), findsOneWidget);
    expect(
      find.text('zf_xiaobei · Chinese'),
      findsOneWidget,
    );
    expect(find.text('Allow speaking over replies'), findsOneWidget);
    expect(find.text('Pause 1.2s'), findsOneWidget);

    await tester.ensureVisible(find.text('zf_xiaobei · Chinese'));
    await tester.tap(find.text('zf_xiaobei · Chinese'));
    await tester.pumpAndSettle();

    expect(
      find.text('MeloTTS Chinese-English Female · Chinese + English (Default)'),
      findsOneWidget,
    );
    expect(find.text('Female · ID 0'), findsOneWidget);
    expect(find.text('Female · ID 1'), findsOneWidget);
  });

  testWidgets('saving TTS voice updates bridge per-model voice',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.text('zf_xiaobei · Chinese'));
    await tester.tap(find.text('zf_xiaobei · Chinese'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female · ID 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(appSettingsController.settings.bridgeLocalTtsVoice, isEmpty);
  });

  testWidgets('deletes enrolled speaker from speech settings', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    var deleted = false;
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeakerDeletion(
            onDeleted: () => deleted = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.text('Jun'));
    expect(find.text('Jun'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-speaker-speaker-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(deleted, isTrue);
    expect(find.text('Jun'), findsNothing);
  });

  testWidgets('localizes bridge speech grouping in Chinese', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        appLanguage: 'zh',
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('zh'),
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('本地 BRIDGE 模型'), findsOneWidget);
    expect(find.text('批量 ASR'), findsWidgets);
    expect(find.text('实时 ASR'), findsWidgets);
    expect(find.text('通话模式'), findsOneWidget);
    expect(find.text('允许说话打断回复'), findsOneWidget);
    expect(find.text('Bridge 详情'), findsOneWidget);
    expect(find.text('TTS 音色'), findsOneWidget);
    expect(find.text('zf_xiaobei · 中文'), findsOneWidget);
  });

  testWidgets('rejects unsupported local wake words before saving',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(callModeWakeWordEnabled: true),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(TextField, 'Wake words'));
    await tester.enterText(find.widgetWithText(TextField, 'Wake words'), '小欧');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      find.text(
        '"小欧" is not supported by the local wake-word model. Use an English phrase or numbered pinyin, such as "hey omni / xiao3 ou1".',
      ),
      findsOneWidget,
    );
    expect(appSettingsController.settings.callModeWakeWords, 'hey omni');
  });

  testWidgets('shows unsupported local wake word error while typing',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(callModeWakeWordEnabled: true),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForSpeechSettings(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(TextField, 'Wake words'));
    await tester.enterText(find.widgetWithText(TextField, 'Wake words'), '小欧');
    await tester.pump();

    expect(
      find.text(
        '"小欧" is not supported by the local wake-word model. Use an English phrase or numbered pinyin, such as "hey omni / xiao3 ou1".',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens model picker sheet from local bridge model card',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForInlineDownloadFailure(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change').first);
    await tester.pumpAndSettle();

    expect(find.text('VITS Melo TTS'), findsWidgets);
    expect(find.text('Kokoro INT8 Multi-Lang v1.1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
  });

  testWidgets('keeps model picker open and shows download progress',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForModelDownloadProgress(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Kokoro INT8 Multi-Lang v1.1'), findsOneWidget);
    expect(find.text('Downloading...'), findsWidgets);
    expect(find.text('Downloading · 50% complete'), findsWidgets);
  });

  testWidgets('download button switches to loading immediately',
      (tester) async {
    final downloadCompleter = Completer<void>();
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForPendingModelDownload(downloadCompleter),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();

    expect(find.text('Downloading...'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    downloadCompleter.complete();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('installed unselected local model can be deleted',
      (tester) async {
    var deleted = false;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForInstalledModelDeletion(
            onDeleted: () => deleted = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.text('Installed models'));
    await tester.tap(find.text('Installed models'));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const ValueKey('delete-installed-model-alternate-tts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(deleted, isTrue);
  });

  testWidgets('installed unmanaged local model can be deleted from model panel',
      (tester) async {
    var deleted = false;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForInstalledModelDeletion(
            onDeleted: () => deleted = true,
            unmanagedModel: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Installed models'), findsOneWidget);
    await tester.ensureVisible(find.text('Installed models'));
    await tester.tap(find.text('Installed models'));
    await tester.pumpAndSettle();

    expect(find.text('Unused Speaker Model'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('delete-installed-model-unused-speaker-model')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(deleted, isTrue);
  });

  testWidgets('shows loading state while selecting a local bridge model',
      (tester) async {
    final updateCompleter = Completer<void>();
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForPendingProfileSelection(updateCompleter),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pump();

    expect(find.text('Alternate TTS'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    updateCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Select'), findsNothing);
  });

  testWidgets('download failure is shown inline on the model card',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForInlineDownloadFailure(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Bridge error (404)'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pumpAndSettle();

    expect(find.text('DOWNLOAD TASKS'), findsNothing);
    expect(find.textContaining('Bridge error (404)'), findsOneWidget);

    Navigator.of(tester.element(find.byType(SpeechSettingsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('Bridge error (404)'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bridge error (404)'), findsNothing);
  });

  testWidgets('download task failure is shown inline on the model card',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SpeechSettingsScreen(
          client: _bridgeClientForFailedDownloadTask(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('download checksum mismatch'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Download'), findsWidgets);
  });
}

BridgeClient _bridgeClientForPendingProfileSelection(
  Completer<void> updateCompleter,
) {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'PUT' &&
          request.url.path == '/speech/profiles/tts.default/model') {
        await updateCompleter.future;
        return http.Response(
          jsonEncode({
            'data': {'tts_default': 'alternate-tts'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return http.Response(
          jsonEncode({
            'data': {
              'root_dir': '/tmp/omni-code-bridge/speech',
              'profiles': {
                'tts_default': 'vits-melo-tts-zh-en',
              },
              'voices': {
                'tts_by_model': {},
              },
              'models': [
                {
                  'id': 'vits-melo-tts-zh-en',
                  'kind': 'tts',
                  'display_name': 'VITS Melo TTS',
                  'description': 'Local bilingual TTS model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': true,
                    'vad': false,
                    'endpointing': false,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['female-voice'],
                  'supports_profiles': ['tts_default'],
                  'recommended_profiles': ['tts_default'],
                  'download_url': 'https://example.com/vits-melo-tts',
                  'download_size_mb': 320,
                  'default_voice': '0',
                  'installed': true,
                  'selected_by': ['tts_default'],
                  'voices': ['0'],
                },
                {
                  'id': 'alternate-tts',
                  'kind': 'tts',
                  'display_name': 'Alternate TTS',
                  'description': 'Second local TTS model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': true,
                    'vad': false,
                    'endpointing': false,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['multi-speaker'],
                  'supports_profiles': ['tts_default'],
                  'recommended_profiles': ['tts_default'],
                  'download_url': 'https://example.com/alternate-tts',
                  'download_size_mb': 215,
                  'default_voice': '0',
                  'installed': true,
                  'selected_by': [],
                  'voices': ['0'],
                },
              ],
              'downloads': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForModelDownloadProgress() {
  var downloadStarted = false;
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/speech/models/downloads') {
        downloadStarted = true;
        return http.Response(
          jsonEncode({
            'data': {
              'task_id': 'task-kokoro',
              'model_id': 'kokoro-int8-multi-lang-v1_1',
              'status': 'downloading',
              'progress_bytes': 50,
              'total_bytes': 100,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return _speechStatusResponse(
          models: [
            _ttsModelJson(
              id: 'vits-melo-tts-zh-en',
              displayName: 'VITS Melo TTS',
              installed: true,
              selected: true,
            ),
            _ttsModelJson(
              id: 'kokoro-int8-multi-lang-v1_1',
              displayName: 'Kokoro INT8 Multi-Lang v1.1',
              installed: false,
              selected: false,
            ),
          ],
          downloads: downloadStarted
              ? [
                  {
                    'task_id': 'task-kokoro',
                    'model_id': 'kokoro-int8-multi-lang-v1_1',
                    'status': 'downloading',
                    'progress_bytes': 50,
                    'total_bytes': 100,
                  },
                ]
              : [],
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForPendingModelDownload(Completer<void> completer) {
  var downloadStarted = false;
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/speech/models/downloads') {
        downloadStarted = true;
        await completer.future;
        return http.Response(
          jsonEncode({
            'data': {
              'task_id': 'task-kokoro',
              'model_id': 'kokoro-int8-multi-lang-v1_1',
              'status': 'downloading',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return _speechStatusResponse(
          models: [
            _ttsModelJson(
              id: 'vits-melo-tts-zh-en',
              displayName: 'VITS Melo TTS',
              installed: true,
              selected: true,
            ),
            _ttsModelJson(
              id: 'kokoro-int8-multi-lang-v1_1',
              displayName: 'Kokoro INT8 Multi-Lang v1.1',
              installed: false,
              selected: false,
            ),
          ],
          downloads: downloadStarted
              ? [
                  {
                    'task_id': 'task-kokoro',
                    'model_id': 'kokoro-int8-multi-lang-v1_1',
                    'status': 'downloading',
                  },
                ]
              : [],
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForFailedDownloadTask() {
  var downloadStarted = false;
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/speech/models/downloads') {
        downloadStarted = true;
        return http.Response(
          jsonEncode({
            'data': {
              'task_id': 'task-kokoro',
              'model_id': 'kokoro-int8-multi-lang-v1_1',
              'status': 'failed',
              'error': 'download checksum mismatch',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return _speechStatusResponse(
          models: [
            _ttsModelJson(
              id: 'vits-melo-tts-zh-en',
              displayName: 'VITS Melo TTS',
              installed: true,
              selected: true,
            ),
            _ttsModelJson(
              id: 'kokoro-int8-multi-lang-v1_1',
              displayName: 'Kokoro INT8 Multi-Lang v1.1',
              installed: false,
              selected: false,
            ),
          ],
          downloads: downloadStarted
              ? [
                  {
                    'task_id': 'task-kokoro',
                    'model_id': 'kokoro-int8-multi-lang-v1_1',
                    'status': 'failed',
                    'error': 'download checksum mismatch',
                  },
                ]
              : [],
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForInstalledModelDeletion({
  required VoidCallback onDeleted,
  bool unmanagedModel = false,
}) {
  var deleted = false;
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      final deletedModelId =
          unmanagedModel ? 'unused-speaker-model' : 'alternate-tts';
      if (request.method == 'DELETE' &&
          request.url.path == '/speech/models/$deletedModelId') {
        deleted = true;
        onDeleted();
        return http.Response('', 204);
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return _speechStatusResponse(
          models: [
            _ttsModelJson(
              id: 'vits-melo-tts-zh-en',
              displayName: 'VITS Melo TTS',
              installed: true,
              selected: true,
            ),
            _ttsModelJson(
              id: 'alternate-tts',
              displayName: 'Alternate TTS',
              installed: !deleted,
              selected: false,
            ),
            if (unmanagedModel)
              _speakerModelJson(
                id: 'unused-speaker-model',
                displayName: 'Unused Speaker Model',
                installed: !deleted,
              ),
          ],
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

Map<String, Object?> _speakerModelJson({
  required String id,
  required String displayName,
  required bool installed,
}) {
  return {
    'id': id,
    'kind': 'speaker',
    'display_name': displayName,
    'description': 'Speaker embedding model',
    'languages': ['multilingual'],
    'runtime': 'offline',
    'backend': 'onnx',
    'capabilities': {
      'streaming': false,
      'realtime_asr': false,
      'batch_asr': false,
      'speech_synthesis': false,
      'vad': false,
      'endpointing': false,
      'punctuation': false,
      'inverse_text_normalization': false,
      'multilingual': true,
      'speaker_embedding': true,
    },
    'features': ['speaker-embedding'],
    'supports_profiles': [],
    'recommended_profiles': [],
    'download_url': 'https://example.com/$id',
    'download_size_mb': 90,
    'installed': installed,
    'selected_by': [],
    'voices': [],
  };
}

http.Response _speechStatusResponse({
  required List<Map<String, Object?>> models,
  List<Map<String, Object?>> downloads = const [],
}) {
  return http.Response(
    jsonEncode({
      'data': {
        'root_dir': '/tmp/omni-code-bridge/speech',
        'profiles': {
          'tts_default': 'vits-melo-tts-zh-en',
        },
        'voices': {
          'tts_by_model': {},
        },
        'models': models,
        'downloads': downloads,
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> _ttsModelJson({
  required String id,
  required String displayName,
  required bool installed,
  required bool selected,
}) {
  return {
    'id': id,
    'kind': 'tts',
    'display_name': displayName,
    'description': 'Local TTS model',
    'languages': ['zh', 'en'],
    'runtime': 'offline',
    'backend': 'onnx',
    'capabilities': {
      'streaming': false,
      'realtime_asr': false,
      'batch_asr': false,
      'speech_synthesis': true,
      'vad': false,
      'endpointing': false,
      'punctuation': false,
      'inverse_text_normalization': false,
      'multilingual': true,
    },
    'features': ['multi-speaker'],
    'supports_profiles': ['tts_default'],
    'recommended_profiles': ['tts_default'],
    'download_url': 'https://example.com/$id',
    'download_size_mb': 215,
    'default_voice': '0',
    'installed': installed,
    'selected_by': selected ? ['tts_default'] : [],
    'voices': ['0'],
  };
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
    this.locale,
  });

  final Widget home;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: home,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

BridgeClient _bridgeClientForSpeechSettings() {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'PUT' &&
          request.url.path == '/speech/models/vits-melo-tts-zh-en/voice') {
        return http.Response(
          jsonEncode({
            'data': {
              'tts_by_model': {
                'vits-melo-tts-zh-en': '0',
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/speech') {
        return http.Response(
          jsonEncode({
            'data': {
              'root_dir': '/tmp/omni-code-bridge/speech',
              'profiles': {
                'asr_batch': 'sensevoice-small-int8',
                'asr_realtime': 'streaming-paraformer-zh-en',
                'tts_default': 'vits-melo-tts-zh-en',
                'vad_default': 'silero-vad',
              },
              'voices': {
                'tts_by_model': {
                  'vits-melo-tts-zh-en': '1',
                },
              },
              'models': [
                {
                  'id': 'sensevoice-small-int8',
                  'kind': 'asr',
                  'display_name': 'SenseVoice Small',
                  'description': 'Local batch ASR model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': true,
                    'speech_synthesis': false,
                    'vad': false,
                    'endpointing': true,
                    'punctuation': true,
                    'inverse_text_normalization': true,
                    'multilingual': true,
                  },
                  'features': ['punctuation'],
                  'supports_profiles': ['asr_batch'],
                  'recommended_profiles': ['asr_batch'],
                  'download_url': 'https://example.com/sensevoice',
                  'download_size_mb': 180,
                  'installed': true,
                  'selected_by': ['asr_batch'],
                  'voices': [],
                },
                {
                  'id': 'streaming-paraformer-zh-en',
                  'kind': 'asr',
                  'display_name': 'Streaming Paraformer',
                  'description': 'Local realtime ASR model',
                  'languages': ['zh', 'en'],
                  'runtime': 'streaming',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': true,
                    'realtime_asr': true,
                    'batch_asr': false,
                    'speech_synthesis': false,
                    'vad': false,
                    'endpointing': true,
                    'punctuation': true,
                    'inverse_text_normalization': true,
                    'multilingual': true,
                  },
                  'features': ['streaming'],
                  'supports_profiles': ['asr_realtime'],
                  'recommended_profiles': ['asr_realtime'],
                  'download_url': 'https://example.com/streaming-paraformer',
                  'download_size_mb': 220,
                  'installed': true,
                  'selected_by': ['asr_realtime'],
                  'voices': [],
                },
                {
                  'id': 'vits-melo-tts-zh-en',
                  'kind': 'tts',
                  'display_name': 'VITS Melo TTS',
                  'description': 'Local bilingual TTS model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': true,
                    'vad': false,
                    'endpointing': false,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['female-voice'],
                  'supports_profiles': ['tts_default'],
                  'recommended_profiles': ['tts_default'],
                  'download_url': 'https://example.com/vits-melo-tts',
                  'download_size_mb': 320,
                  'default_voice': '0',
                  'installed': true,
                  'selected_by': ['tts_default'],
                  'voices': ['0', '1'],
                  'voice_details': [
                    {
                      'id': '0',
                      'name': 'MeloTTS Chinese-English Female',
                      'language': 'zh/en',
                      'accent': 'Chinese + English',
                      'gender': 'female',
                    },
                    {
                      'id': '1',
                      'name': 'zf_xiaobei',
                      'language': 'zh',
                      'accent': 'Chinese',
                      'gender': 'female',
                    },
                  ],
                },
                {
                  'id': 'silero-vad',
                  'kind': 'vad',
                  'display_name': 'Silero VAD',
                  'description': 'Realtime speech activity detection',
                  'languages': ['multilingual'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': false,
                    'vad': true,
                    'endpointing': true,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['endpointing'],
                  'supports_profiles': ['vad_default'],
                  'recommended_profiles': ['vad_default'],
                  'download_url': 'https://example.com/silero-vad',
                  'download_size_mb': 12,
                  'installed': true,
                  'selected_by': ['vad_default'],
                  'voices': [],
                },
              ],
              'downloads': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForSpeakerDeletion({
  required VoidCallback onDeleted,
}) {
  var deleted = false;
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'DELETE' &&
          request.url.path == '/speech/speakers/speaker-1') {
        deleted = true;
        onDeleted();
        return http.Response('', 204);
      }
      if (request.method == 'GET' && request.url.path == '/speech/speakers') {
        return http.Response(
          jsonEncode({
            'data': deleted
                ? <Object?>[]
                : [
                    {
                      'id': 'speaker-1',
                      'name': 'Jun',
                      'embedding_model_id': '3dspeaker-speech-eres2net-base',
                      'embedding_count': 2,
                      'created_at': '2026-05-09T10:00:00.000Z',
                      'updated_at': '2026-05-09T10:00:00.000Z',
                    },
                  ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/speech/speaker-filter') {
        return http.Response(
          jsonEncode({
            'data': {
              'enabled': !deleted,
              'speaker_id': deleted ? null : 'speaker-1',
              'threshold': 0.65,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/speech') {
        return _speechStatusResponse(
          models: [
            _speakerModelJson(
              id: '3dspeaker-speech-eres2net-base',
              displayName: '3D Speaker',
              installed: true,
            ),
          ],
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _bridgeClientForInlineDownloadFailure() {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/speech/models/downloads') {
        return http.Response('download request failed with 404', 404);
      }

      if (request.method == 'GET' && request.url.path == '/speech') {
        return http.Response(
          jsonEncode({
            'data': {
              'root_dir': '/tmp/omni-code-bridge/speech',
              'profiles': {
                'asr_batch': 'sensevoice-small-int8',
                'asr_realtime': 'streaming-paraformer-zh-en',
                'tts_default': 'vits-melo-tts-zh-en',
                'vad_default': 'silero-vad',
              },
              'voices': {
                'tts_by_model': {
                  'vits-melo-tts-zh-en': '1',
                },
              },
              'models': [
                {
                  'id': 'sensevoice-small-int8',
                  'kind': 'asr',
                  'display_name': 'SenseVoice Small',
                  'description': 'Local batch ASR model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': true,
                    'speech_synthesis': false,
                    'vad': false,
                    'endpointing': true,
                    'punctuation': true,
                    'inverse_text_normalization': true,
                    'multilingual': true,
                  },
                  'features': ['punctuation'],
                  'supports_profiles': ['asr_batch'],
                  'recommended_profiles': ['asr_batch'],
                  'download_url': 'https://example.com/sensevoice',
                  'download_size_mb': 180,
                  'installed': true,
                  'selected_by': ['asr_batch'],
                  'voices': [],
                },
                {
                  'id': 'streaming-paraformer-zh-en',
                  'kind': 'asr',
                  'display_name': 'Streaming Paraformer',
                  'description': 'Local realtime ASR model',
                  'languages': ['zh', 'en'],
                  'runtime': 'streaming',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': true,
                    'realtime_asr': true,
                    'batch_asr': false,
                    'speech_synthesis': false,
                    'vad': false,
                    'endpointing': true,
                    'punctuation': true,
                    'inverse_text_normalization': true,
                    'multilingual': true,
                  },
                  'features': ['streaming'],
                  'supports_profiles': ['asr_realtime'],
                  'recommended_profiles': ['asr_realtime'],
                  'download_url': 'https://example.com/streaming-paraformer',
                  'download_size_mb': 220,
                  'installed': true,
                  'selected_by': ['asr_realtime'],
                  'voices': [],
                },
                {
                  'id': 'vits-melo-tts-zh-en',
                  'kind': 'tts',
                  'display_name': 'VITS Melo TTS',
                  'description': 'Local bilingual TTS model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': true,
                    'vad': false,
                    'endpointing': false,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['female-voice'],
                  'supports_profiles': ['tts_default'],
                  'recommended_profiles': ['tts_default'],
                  'download_url': 'https://example.com/vits-melo-tts',
                  'download_size_mb': 320,
                  'default_voice': '0',
                  'installed': true,
                  'selected_by': ['tts_default'],
                  'voices': ['0', '1'],
                  'voice_details': [
                    {
                      'id': '0',
                      'name': 'MeloTTS Chinese-English Female',
                      'language': 'zh/en',
                      'accent': 'Chinese + English',
                      'gender': 'female',
                    },
                    {
                      'id': '1',
                      'name': 'zf_xiaobei',
                      'language': 'zh',
                      'accent': 'Chinese',
                      'gender': 'female',
                    },
                  ],
                },
                {
                  'id': 'kokoro-int8-multi-lang-v1_1',
                  'kind': 'tts',
                  'display_name': 'Kokoro INT8 Multi-Lang v1.1',
                  'description': 'Local bilingual multi-speaker TTS model',
                  'languages': ['zh', 'en'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': true,
                    'vad': false,
                    'endpointing': false,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['multi-speaker'],
                  'supports_profiles': ['tts_default'],
                  'recommended_profiles': ['tts_default'],
                  'download_url': 'https://example.com/kokoro',
                  'download_size_mb': 215,
                  'default_voice': '0',
                  'installed': false,
                  'selected_by': [],
                  'voices': [],
                },
                {
                  'id': 'silero-vad',
                  'kind': 'vad',
                  'display_name': 'Silero VAD',
                  'description': 'Realtime speech activity detection',
                  'languages': ['multilingual'],
                  'runtime': 'offline',
                  'backend': 'onnx',
                  'capabilities': {
                    'streaming': false,
                    'realtime_asr': false,
                    'batch_asr': false,
                    'speech_synthesis': false,
                    'vad': true,
                    'endpointing': true,
                    'punctuation': false,
                    'inverse_text_normalization': false,
                    'multilingual': true,
                  },
                  'features': ['endpointing'],
                  'supports_profiles': ['vad_default'],
                  'recommended_profiles': ['vad_default'],
                  'download_url': 'https://example.com/silero-vad',
                  'download_size_mb': 12,
                  'installed': true,
                  'selected_by': ['vad_default'],
                  'voices': [],
                },
              ],
              'downloads': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      nextRequest.body = request.body;
      nextRequest.encoding = request.encoding;
    }
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
