import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/services/cloud_speech_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  test('bridge local synthesizeSpeech uses bridge model voice binding',
      () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/audio/speech');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );

    await service.synthesizeSpeech('Reply for call mode');

    expect(body['input'], 'Reply for call mode');
    expect(body.containsKey('voice'), isFalse);
    expect(body.containsKey('stream'), isFalse);
  });

  test('bridge local synthesizeSpeech forwards streaming preference', () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
        bridgeLocalTtsStreaming: true,
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/audio/speech');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'stream_url': '/v1/audio/speech/streams/test-token',
              'content_type': 'audio/wav',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final speech = await service.synthesizeSpeech('Reply for call mode');

    expect(body['stream'], isTrue);
    expect(speech.streamUrl,
        'http://127.0.0.1:8787/v1/audio/speech/streams/test-token');
  });

  test('bridge local synthesizeSpeech strips emoji unsupported by lexicon',
      () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(ttsProvider: TtsProvider.bridgeLocal),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );

    await service.synthesizeSpeech('Why ❓ now');

    expect(body['input'], 'Why now');
  });

  test('speech plugin tts uses configured model field', () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'volcengine-ark-tts',
              'name': 'Volcengine Ark TTS',
              'vendor': 'volcengine',
              'version': '0.1.0',
              'capabilities': ['speech.tts'],
              'transport': 'openai_compatible',
              'capability_configs': {
                'speech.tts': {
                  'transport': 'openai_compatible',
                  'base_url': 'https://ark.cn-beijing.volces.com/api/v3',
                  'model': 'doubao-tts-test',
                  'path': '/audio/speech',
                },
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.tts': 'volcengine-ark-tts',
        },
        speechPluginApiKeysByPluginId: const {
          'volcengine-ark-tts': 'test-key',
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(),
            'https://ark.cn-beijing.volces.com/api/v3/audio/speech');
        expect(request.headers['authorization'], 'Bearer test-key');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );

    await service.synthesizeSpeech('hello');

    expect(body['model'], 'doubao-tts-test');
  });

  test('speech plugin tts allows app setting model override', () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'volcengine-ark-tts',
              'name': 'Volcengine Ark TTS',
              'vendor': 'volcengine',
              'version': '0.1.0',
              'setting_fields': [
                {
                  'key': 'model',
                  'label': 'Ark endpoint ID',
                  'required': true,
                  'capabilities': ['speech.tts'],
                },
              ],
              'capabilities': ['speech.tts'],
              'transport': 'openai_compatible',
              'capability_configs': {
                'speech.tts': {
                  'transport': 'openai_compatible',
                  'base_url': 'https://ark.cn-beijing.volces.com/api/v3',
                  'model': 'placeholder-model',
                  'path': '/audio/speech',
                },
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.tts': 'volcengine-ark-tts',
        },
        speechPluginApiKeysByPluginId: const {
          'volcengine-ark-tts': 'test-key',
        },
        speechPluginSettingsByPluginId: const {
          'volcengine-ark-tts': {
            'model': 'ep-production-tts',
          },
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );

    await service.synthesizeSpeech('hello');

    expect(body['model'], 'ep-production-tts');
  });

  test('speech plugin batch asr uses configured model field', () async {
    final file =
        File('${Directory.systemTemp.path}/cloud-speech-service-test.wav');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    late Uri requestUri;
    late String authorization;
    late List<int> requestBytes;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'volcengine-ark-batch-asr',
              'name': 'Volcengine Ark Batch ASR',
              'vendor': 'volcengine',
              'version': '0.1.0',
              'capabilities': ['speech.batch_asr'],
              'transport': 'openai_compatible',
              'capability_configs': {
                'speech.batch_asr': {
                  'transport': 'openai_compatible',
                  'base_url': 'https://ark.cn-beijing.volces.com/api/v3',
                  'model': 'doubao-asr-test',
                  'path': '/audio/transcriptions',
                },
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.batch_asr': 'volcengine-ark-batch-asr',
        },
        speechPluginApiKeysByPluginId: const {
          'volcengine-ark-batch-asr': 'test-key',
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        requestUri = request.url;
        authorization = request.headers['authorization'] ?? '';
        requestBytes = request.bodyBytes;
        return http.Response(
          jsonEncode({'text': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.transcribeAudio(file);

    expect(result, 'ok');
    expect(
      requestUri.toString(),
      'https://ark.cn-beijing.volces.com/api/v3/audio/transcriptions',
    );
    expect(authorization, 'Bearer test-key');
    expect(utf8.decode(requestBytes), contains('name="model"'));
    expect(utf8.decode(requestBytes), contains('doubao-asr-test'));
  });
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
    } else {
      nextRequest.bodyBytes = await request.finalize().toBytes();
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
