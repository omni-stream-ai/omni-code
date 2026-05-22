import 'dart:convert';

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
