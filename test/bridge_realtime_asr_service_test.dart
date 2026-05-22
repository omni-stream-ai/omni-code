import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/services/bridge_realtime_asr_service.dart';

void main() {
  test('bridge realtime service emits final transcript from websocket events',
      () async {
    final socket = _FakeBridgeRealtimeSocket();
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/speech/realtime') {
          return http.Response(
            jsonEncode({
              'data': {
                'websocket_path': '/speech/realtime/ws',
                'session_defaults': {
                  'ready': true,
                  'missing_requirements': [],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );
    final service = BridgeRealtimeAsrService(
      client: client,
      connector: (uri, {headers}) async => socket,
    );
    final utterances = <BridgeRealtimeAsrUtterance>[];
    final wakeWords = <String>[];
    var speechStartedCalls = 0;
    final audioController = StreamController<Uint8List>();

    final startFuture = service.start(
      audioStream: audioController.stream,
      onUtterance: utterances.add,
      onSpeechStarted: () {
        speechStartedCalls += 1;
      },
      onWakeWordDetected: wakeWords.add,
      config: const BridgeRealtimeAsrConfig(
        endpointTrailingSilenceMs: 1500,
        vadMinSilenceMs: 900,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    socket.emitText(jsonEncode({
      'type': 'session.created',
      'session': {'ready': true},
    }));
    await Future<void>.delayed(Duration.zero);
    expect(socket.sentMessages.whereType<Uint8List>(), isEmpty);

    socket.emitText(jsonEncode({
      'type': 'session.updated',
      'session': {
        'ready': true,
        'enable_wake_word': false,
        'wake_word_detector': 'local_kws',
      },
    }));
    await startFuture;
    audioController.add(Uint8List.fromList([1, 2, 3]));
    await audioController.close();

    socket.emitText(jsonEncode({
      'type': 'input_audio_buffer.speech_started',
    }));
    socket.emitText(jsonEncode({
      'type': 'input_audio_buffer.wake_word_detected',
      'keyword': '你好小欧',
    }));
    socket.emitText(jsonEncode({
      'type': 'response.audio_transcript.delta',
      'text': 'partial',
      'speaker_filter': {
        'active': true,
        'verified': false,
        'matched': null,
      },
      'wake_word': {
        'active': true,
        'verified': false,
        'matched': null,
      },
    }));
    socket.emitText(jsonEncode({
      'type': 'response.audio_transcript.completed',
      'text': 'final result',
      'speaker_filter': {
        'active': true,
        'verified': true,
        'matched': true,
      },
      'wake_word': {
        'active': true,
        'verified': true,
        'matched': true,
      },
    }));

    await Future<void>.delayed(Duration.zero);

    expect(utterances, hasLength(2));
    expect(speechStartedCalls, 1);
    expect(wakeWords, ['你好小欧']);
    expect(utterances.first.text, 'partial');
    expect(utterances.first.isFinal, isFalse);
    expect(utterances.first.speakerFilterActive, isTrue);
    expect(utterances.first.speakerVerified, isFalse);
    expect(utterances.first.speakerMatched, isNull);
    expect(utterances.first.wakeWordActive, isTrue);
    expect(utterances.first.wakeWordVerified, isFalse);
    expect(utterances.first.wakeWordMatched, isNull);
    expect(utterances.last.text, 'final result');
    expect(utterances.last.isFinal, isTrue);
    expect(utterances.last.speakerFilterActive, isTrue);
    expect(utterances.last.speakerVerified, isTrue);
    expect(utterances.last.speakerMatched, isTrue);
    expect(utterances.last.wakeWordActive, isTrue);
    expect(utterances.last.wakeWordVerified, isTrue);
    expect(utterances.last.wakeWordMatched, isTrue);
    expect(
      socket.sentMessages.whereType<String>(),
      contains(jsonEncode({'type': 'input_audio_buffer.commit'})),
    );
    expect(
      socket.sentMessages.whereType<String>(),
      contains(
        jsonEncode({
          'type': 'session.update',
          'session': {
            'sample_rate_hz': 16000,
            'channels': 1,
            'enable_vad': true,
            'enable_wake_word': false,
            'strip_wake_word': true,
            'endpoint_trailing_silence_ms': 1500,
            'vad_min_silence_ms': 900,
          },
        }),
      ),
    );
  });

  test('bridge realtime config can request local KWS wake word detector',
      () async {
    const config = BridgeRealtimeAsrConfig(
      enableWakeWord: true,
      wakeWordDetector: 'local_kws',
      wakeWords: ['小欧', '欧米'],
    );

    expect(config.toSessionUpdateJson(), {
      'type': 'session.update',
      'session': {
        'sample_rate_hz': 16000,
        'channels': 1,
        'enable_vad': true,
        'enable_wake_word': true,
        'wake_word_detector': 'local_kws',
        'wake_words': ['小欧', '欧米'],
        'strip_wake_word': true,
      },
    });
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

class _FakeBridgeRealtimeSocket implements BridgeRealtimeSocket {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentMessages = <dynamic>[];

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  void add(dynamic data) {
    sentMessages.add(data);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emitText(String message) {
    _controller.add(message);
  }
}
