import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/plugins/speech_plugin_registry.dart';
import 'package:omni_code/src/screens/speech_settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('shows Linux system speech availability hints', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(
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
      findsWidgets,
    );
    expect(
      find.text(
        'System ASR is not available on Linux yet. Choose a cloud provider to enable voice input.',
      ),
      findsWidgets,
    );
  });

  testWidgets('speech settings use system defaults without route pickers',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('System default'), findsWidgets);
    expect(find.text('Route'), findsNothing);
    expect(find.text('Find plugins'), findsNothing);
    expect(find.text('Available'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));

    await tester.tap(find.text('Realtime ASR').first);
    await tester.pumpAndSettle();

    expect(find.text('Catalog Realtime ASR'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('does not show bridge local model settings', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOCAL BRIDGE MODELS'), findsNothing);
    expect(find.text('TTS VOICE'), findsNothing);
  });

  testWidgets('shows plugin lifecycle fields in capability flow',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'doubao-tts',
              'name': 'Doubao TTS',
              'vendor': 'doubao',
              'version': '0.1.0',
              'registration_url': 'https://example.com/doubao-signup',
              'setting_fields': [
                {
                  'key': 'model',
                  'label': 'Ark endpoint ID',
                  'required': true,
                  'capabilities': ['tts'],
                },
              ],
              'capabilities': ['tts'],
              'transport': 'openai_compatible',
              'capability_configs': {
                'tts': {
                  'transport': 'openai_compatible',
                  'base_url': 'https://ark.cn-beijing.volces.com/api/v3',
                  'model': 'ep-test',
                  'path': '/audio/speech',
                },
              },
            },
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('TTS').first);
    await tester.tap(find.text('TTS').first);
    await tester.pumpAndSettle();

    expect(find.text('Doubao TTS'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);
    expect(find.text('Installed'), findsNothing);
  });

  testWidgets(
      'opens capability page and sorts installed plugins before install',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'installed-tts',
              'name': 'Installed TTS',
              'vendor': 'local',
              'version': '0.1.0',
              'description': 'already ready',
              'capabilities': ['tts'],
              'transport': 'openai_compatible',
            },
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('TTS').first);
    await tester.tap(find.text('TTS').first);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Choose system default or pick a plugin for this capability.'),
        findsOneWidget);
    expect(find.text('Installed TTS'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('disables capability test when current selection is unsupported',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        selectedSpeechPluginByCapability: const {
          'tts': 'metadata-tts',
        },
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'metadata-tts',
              'name': 'Metadata TTS',
              'vendor': 'local',
              'version': '0.1.0',
              'capabilities': ['tts'],
              'transport': 'metadata_only',
              'capability_configs': {
                'tts': {
                  'transport': 'metadata_only',
                },
              },
            },
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('TTS').first);
    await tester.tap(find.text('TTS').first);
    await tester.pumpAndSettle();

    expect(find.text('Metadata TTS'), findsOneWidget);
  });

  testWidgets('plugin settings support dropdown options and inline test',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'doubao-realtime-asr',
              'name': 'Doubao Realtime ASR',
              'vendor': 'volcengine',
              'version': '0.3.0',
              'capabilities': ['realtime_asr'],
              'transport': 'realtime_websocket',
              'realtime_websocket_url':
                  'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async',
              'setting_fields': [
                {
                  'key': 'resource_id',
                  'label': 'Resource ID',
                  'required': true,
                  'capabilities': ['realtime_asr'],
                  'options': [
                    {
                      'value': 'volc.bigasr.sauc.duration',
                      'label': '流式语音识别模型 2.0 - 小时版',
                      'help': 'Resource ID: volc.bigasr.sauc.duration',
                    },
                    {
                      'value': 'volc.bigasr.sauc.concurrent',
                      'label': '流式语音识别模型 2.0 - 并发版',
                      'help': 'Resource ID: volc.bigasr.sauc.concurrent',
                    },
                  ],
                },
              ],
              'capability_configs': {
                'realtime_asr': {
                  'transport': 'realtime_websocket',
                  'websocket_url':
                      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async',
                },
              },
            },
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Realtime ASR').first);
    await tester.tap(find.text('Realtime ASR').first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.text('Doubao Realtime ASR · API Key'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'API Key'),
      'secret-key',
    );
    await tester.pumpAndSettle();

    expect(find.text('Resource ID *'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('流式语音识别模型 2.0 - 小时版'), findsWidgets);
    expect(find.text('Resource ID: volc.bigasr.sauc.duration'), findsOneWidget);
    expect(find.text('流式语音识别模型 2.0 - 并发版'), findsOneWidget);

    await tester.tap(find.text('流式语音识别模型 2.0 - 小时版').last);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets(
      'use expands config instead of selecting when plugin info missing',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'doubao-tts',
              'name': 'Doubao TTS',
              'vendor': 'doubao',
              'version': '0.1.0',
              'setting_fields': [
                {
                  'key': 'model',
                  'label': 'Ark endpoint ID',
                  'required': true,
                  'capabilities': ['tts'],
                },
              ],
              'capabilities': ['tts'],
              'transport': 'openai_compatible',
            },
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('TTS').first);
    await tester.tap(find.text('TTS').first);
    await tester.pumpAndSettle();

    expect(find.text('Additional plugin settings'), findsNothing);
    expect(find.text('Start command'), findsNothing);

    await tester.tap(find.text('Use').first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1700));

    expect(find.text('Doubao TTS · API Key'), findsOneWidget);
    expect(find.text('Additional plugin settings'), findsOneWidget);
    expect(find.text('Start command'), findsNothing);
    expect(
      appSettingsController.settings.selectedSpeechPluginByCapability,
      isEmpty,
    );
  });

  testWidgets('does not show wake word settings', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        callModeWakeWordEnabled: true,
        callModeWakeWords: 'legacy wake word',
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        home: _speechSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Require wake word'), findsNothing);
    expect(find.widgetWithText(TextField, 'Wake words'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(appSettingsController.settings.callModeWakeWordEnabled, isFalse);
    expect(appSettingsController.settings.callModeWakeWords, 'hey omni');
  });
}

SpeechSettingsScreen _speechSettingsScreen({
  TargetPlatform? debugPlatformOverride,
  bool? debugIsWebOverride,
}) {
  return SpeechSettingsScreen(
    speechPluginRegistry: _testSpeechPluginRegistry(),
    debugPlatformOverride: debugPlatformOverride,
    debugIsWebOverride: debugIsWebOverride,
  );
}

SpeechPluginRegistry _testSpeechPluginRegistry() {
  return SpeechPluginRegistry(
    httpClient: _FakeHttpClient((request) async {
      return http.Response(
        jsonEncode([
          {
            'id': 'catalog-realtime-asr',
            'name': 'Catalog Realtime ASR',
            'author': 'Catalog',
            'description': 'Realtime ASR from catalog',
            'manifest_url': 'https://example.com/catalog-realtime-asr.json',
            'capabilities': ['realtime_asr'],
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  Map<String, Object?> _json = <String, Object?>{};

  @override
  Future<String?> read() async {
    if (_json.isEmpty) {
      return null;
    }
    return jsonEncode(_json);
  }

  @override
  Future<void> write(String value) async {
    _json = Map<String, Object?>.from(jsonDecode(value) as Map);
  }
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

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
  });

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      home: home,
    );
  }
}
