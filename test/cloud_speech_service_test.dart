import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/plugins/speech_plugin_models.dart';
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

  test('OpenAI-compatible TTS plugin sends its configured voice', () async {
    late Map<String, dynamic> body;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': openAiCompatibleSpeechManifest.toJson(),
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.tts': 'openai-compatible-speech',
        },
        speechPluginApiKeysByPluginId: const {
          'openai-compatible-speech': 'test-key',
        },
        speechPluginSettingsByPluginId: const {
          'openai-compatible-speech': {
            'resource_id': 'nova',
            'tts_model': 'custom-tts-model',
          },
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        expect(
            request.url.toString(), 'https://api.openai.com/v1/audio/speech');
        expect(request.headers['authorization'], 'Bearer test-key');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );

    await service.synthesizeSpeech('Hello');

    expect(body, {
      'model': 'custom-tts-model',
      'input': 'Hello',
      'voice': 'nova',
      'response_format': 'wav',
    });
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

  test('speech plugin batch asr uses configured resource ID in async requests',
      () async {
    final file =
        File('${Directory.systemTemp.path}/cloud-speech-service-test.wav');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    late Map<String, dynamic> body;
    late Map<String, String> headers;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'volcengine-async-batch-asr',
              'name': 'Volcengine Async Batch ASR',
              'version': '0.1.0',
              'capabilities': ['speech.batch_asr'],
              'capability_configs': {
                'speech.batch_asr': {
                  'base_url': 'https://openspeech.bytedance.com',
                  'model': 'vc.async.default',
                  'path': '/api/v3/submit',
                  'request_content_type': 'application/json',
                  'extra_headers': {
                    'X-Api-Resource-Id': r'${resource_id}',
                  },
                  'request_body': {
                    'resource_id': r'${resource_id}',
                    'model': r'${model}',
                    'audio': r'${audio_data_uri}',
                  },
                },
              },
              'setting_fields': [
                {
                  'key': 'resource_id',
                  'label': 'Resource ID',
                  'required': true,
                  'capabilities': ['speech.batch_asr'],
                },
              ],
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.batch_asr': 'volcengine-async-batch-asr',
        },
        speechPluginApiKeysByPluginId: const {
          'volcengine-async-batch-asr': 'test-key',
        },
        speechPluginSettingsByPluginId: const {
          'volcengine-async-batch-asr': {
            'resource_id': 'vc.async.authorized',
          },
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        headers = request.headers;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'text': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.transcribeAudio(file);

    expect(result, 'ok');
    expect(headers['x-api-resource-id'], 'vc.async.authorized');
    expect(body['resource_id'], 'vc.async.authorized');
    expect(body['model'], 'vc.async.default');
  });

  test('legacy Volcengine batch ASR submits with documented authorization',
      () async {
    final file =
        File('${Directory.systemTemp.path}/cloud-speech-service-test.wav');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    late http.Request request;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'doubao-batch-asr',
              'name': 'Doubao Batch ASR',
              'version': '0.3.0',
              'capabilities': ['speech.batch_asr'],
              'setting_fields': [
                {
                  'key': 'model',
                  'label': 'APPID',
                  'required': true,
                  'capabilities': ['speech.batch_asr'],
                },
              ],
              'capability_configs': {
                'speech.batch_asr': {
                  'base_url': 'https://openspeech.bytedance.com',
                  'auth_header': 'Authorization',
                  'auth_scheme': 'Bearer;',
                  'path':
                      r'/api/v1/vc/submit?appid=${model}&language=${language}',
                  'request_content_type': 'audio/wav',
                },
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.batch_asr': 'doubao-batch-asr',
        },
        speechPluginApiKeysByPluginId: const {
          'doubao-batch-asr': 'test-access-token',
        },
        speechPluginSettingsByPluginId: const {
          'doubao-batch-asr': {
            'model': '4701558018',
            'resource_id': 'zh-CN',
          },
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((nextRequest) async {
        request = nextRequest;
        return http.Response('denied', 403);
      }),
    );

    await expectLater(
      service.transcribeAudio(file),
      throwsA(isA<Exception>()),
    );

    expect(
      request.url.toString(),
      'https://openspeech.bytedance.com/api/v1/vc/submit?appid=4701558018&language=zh-CN',
    );
    expect(request.headers['authorization'], 'Bearer; test-access-token');
    expect(request.headers['content-type'], 'audio/wav');
  });

  test('legacy Volcengine batch ASR reads wrapped utterances from polling',
      () async {
    final file =
        File('${Directory.systemTemp.path}/cloud-speech-service-test.wav');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    var requestCount = 0;
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'doubao-batch-asr',
              'name': 'Doubao Batch ASR',
              'version': '0.3.0',
              'capabilities': ['speech.batch_asr'],
              'capability_configs': {
                'speech.batch_asr': {
                  'base_url': 'https://openspeech.bytedance.com',
                  'auth_header': 'Authorization',
                  'auth_scheme': 'Bearer;',
                  'path':
                      r'/api/v1/vc/submit?appid=${model}&language=${language}',
                  'poll_path': r'/api/v1/vc/query?appid=${model}&id=${task_id}',
                  'request_content_type': 'audio/wav',
                  'response_text_path': 'utterances.0.text',
                },
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'speech.batch_asr': 'doubao-batch-asr',
        },
        speechPluginApiKeysByPluginId: const {
          'doubao-batch-asr': 'test-access-token',
        },
        speechPluginSettingsByPluginId: const {
          'doubao-batch-asr': {
            'model': '4701558018',
          },
        },
      ),
    );

    final service = CloudSpeechService(
      httpClient: _FakeHttpClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(jsonEncode({'id': 'task-id'}), 200);
        }
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'utterances': [
                {'text': 'recognized text'},
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
        service.transcribeAudio(file), completion('recognized text'));
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
