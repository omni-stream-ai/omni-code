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
        bridgeLocalTtsVoice: '1',
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
    expect(find.text('Bridge URL'), findsOneWidget);
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

  testWidgets('localizes bridge speech grouping in Chinese', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        appLanguage: 'zh',
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
        bridgeLocalTtsVoice: '1',
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
    expect(find.text('模型目录'), findsOneWidget);
    expect(find.text('TTS 音色'), findsOneWidget);
    expect(find.text('zf_xiaobei · 中文'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Select'));
    await tester.pump();

    expect(find.text('Alternate TTS'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    updateCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Alternate TTS'), findsNothing);
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

    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.textContaining('Bridge error (404)'), findsNothing);
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
