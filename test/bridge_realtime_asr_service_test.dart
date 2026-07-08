import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/services/bridge_realtime_asr_service.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    BridgeRealtimeAsrService.clearCache();
  });

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
            'endpoint_trailing_silence_ms': 1500,
            'vad_min_silence_ms': 900,
          },
        }),
      ),
    );
  });

  test('bridge realtime config does not serialize wake word settings',
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
      },
    });
  });

  test('bridge-compatible realtime plugin overrides websocket endpoint',
      () async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'realtime-1',
              'name': 'Realtime 1',
              'vendor': 'Vendor',
              'version': '1.0.0',
              'capabilities': ['realtime_asr'],
              'transport': 'bridge_openai_compatible',
              'base_url': 'https://speech.example.com',
              'realtime_asr_path': '/vendor/realtime',
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'realtime_asr': 'realtime-1',
        },
        speechPluginSettingsByPluginId: const {
          'realtime-1': {
            'base_url': 'https://override.example.com',
            'path': '/override/realtime',
          },
        },
      ),
    );

    final socket = _FakeBridgeRealtimeSocket();
    Uri? connectedUri;
    final service = BridgeRealtimeAsrService(
      client: BridgeClient(httpClient: _FakeHttpClient((request) async {
        return http.Response('not used', 404);
      })),
      connector: (uri, {headers}) async {
        connectedUri = uri;
        return socket;
      },
    );

    final audioController = StreamController<Uint8List>();
    final startFuture = service.start(
      audioStream: audioController.stream,
      onUtterance: (_) {},
      config: const BridgeRealtimeAsrConfig(),
    );
    await Future<void>.delayed(Duration.zero);

    socket.emitText(jsonEncode({
      'type': 'session.created',
      'session': {'ready': true},
    }));
    socket.emitText(jsonEncode({
      'type': 'session.updated',
      'session': {'ready': true},
    }));
    await startFuture;
    await audioController.close();

    expect(
      connectedUri.toString(),
      'wss://override.example.com/override/realtime/ws',
    );
  });

  test('custom realtime websocket plugin maps provider events', () async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        installedSpeechPlugins: const [
          {
            'installed_at': '2026-01-01T00:00:00.000Z',
            'manifest': {
              'id': 'custom-realtime',
              'name': 'Custom Realtime',
              'vendor': 'Vendor',
              'version': '1.0.0',
              'capabilities': ['realtime_asr'],
              'transport': 'realtime_websocket',
              'realtime_websocket_url': 'wss://rt.example.com/listen',
              'realtime_auth_header': 'Authorization',
              'realtime_auth_scheme': 'Token',
              'realtime_event_map': {
                'field': 'event',
                'speech_started': 'speech_started',
                'partial': 'transcript.partial',
                'final': 'transcript.final',
              },
              'realtime_text_field_map': {
                'text': 'transcript',
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'realtime_asr': 'custom-realtime',
        },
        speechPluginApiKeysByPluginId: const {
          'custom-realtime': 'secret',
        },
        speechPluginSettingsByPluginId: const {
          'custom-realtime': {
            'websocket_url': 'wss://override.example.com/live',
            'auth_header': 'X-Api-Key',
            'auth_scheme': '',
          },
        },
      ),
    );

    final socket = _FakeBridgeRealtimeSocket();
    Uri? connectedUri;
    Map<String, dynamic>? capturedHeaders;
    final utterances = <BridgeRealtimeAsrUtterance>[];
    var speechStarted = 0;
    final service = BridgeRealtimeAsrService(
      client: BridgeClient(httpClient: _FakeHttpClient((request) async {
        return http.Response('not used', 404);
      })),
      connector: (uri, {headers}) async {
        connectedUri = uri;
        capturedHeaders = headers;
        return socket;
      },
    );

    final audioController = StreamController<Uint8List>();
    final startFuture = service.start(
      audioStream: audioController.stream,
      onUtterance: utterances.add,
      onSpeechStarted: () => speechStarted += 1,
      config: const BridgeRealtimeAsrConfig(),
    );
    await startFuture;

    socket.emitText(jsonEncode({
      'event': 'speech_started',
    }));
    socket.emitText(jsonEncode({
      'event': 'transcript.partial',
      'transcript': 'hello',
    }));
    socket.emitText(jsonEncode({
      'event': 'transcript.final',
      'transcript': 'hello world',
    }));
    await Future<void>.delayed(Duration.zero);
    await audioController.close();

    expect(connectedUri.toString(), 'wss://override.example.com/live');
    expect(capturedHeaders?['X-Api-Key'], 'secret');
    expect(capturedHeaders?.containsKey('Authorization'), isFalse);
    expect(capturedHeaders?.containsKey('X-Omni-Code-Client-Id'), isFalse);
    expect(speechStarted, 1);
    expect(utterances, hasLength(2));
    expect(utterances.first.text, 'hello');
    expect(utterances.first.isFinal, isFalse);
    expect(utterances.last.text, 'hello world');
    expect(utterances.last.isFinal, isTrue);
  });

  test('volcengine realtime plugin uses SAUC binary websocket protocol',
      () async {
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
              'realtime_event_map': {
                'protocol': 'volcengine_sauc',
              },
            },
          },
        ],
        selectedSpeechPluginByCapability: const {
          'realtime_asr': 'doubao-realtime-asr',
        },
        speechPluginApiKeysByPluginId: const {
          'doubao-realtime-asr': 'secret-key',
        },
        speechPluginSettingsByPluginId: const {
          'doubao-realtime-asr': {
            'resource_id': 'volc.seedasr.sauc.concurrent',
          },
        },
      ),
    );

    final socket = _FakeBridgeRealtimeSocket();
    Uri? connectedUri;
    Map<String, dynamic>? capturedHeaders;
    final utterances = <BridgeRealtimeAsrUtterance>[];
    final service = BridgeRealtimeAsrService(
      client: BridgeClient(httpClient: _FakeHttpClient((request) async {
        return http.Response('not used', 404);
      })),
      connector: (uri, {headers}) async {
        connectedUri = uri;
        capturedHeaders = headers;
        return socket;
      },
    );

    final audioController = StreamController<Uint8List>();
    await service.start(
      audioStream: audioController.stream,
      onUtterance: utterances.add,
      config: const BridgeRealtimeAsrConfig(),
    );

    expect(
      connectedUri.toString(),
      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async',
    );
    expect(capturedHeaders?['X-Api-Key'], 'secret-key');
    expect(capturedHeaders?.containsKey('X-Omni-Code-Client-Id'), isFalse);
    expect(capturedHeaders?.containsKey('X-Api-App-Key'), isFalse);
    expect(capturedHeaders?.containsKey('X-Api-Access-Key'), isFalse);
    expect(
      capturedHeaders?['X-Api-Resource-Id'],
      'volc.seedasr.sauc.concurrent',
    );
    expect(capturedHeaders?['X-Api-Sequence'], '-1');
    expect(capturedHeaders?['X-Api-Connect-Id'], isNotEmpty);
    expect(capturedHeaders?['X-Api-Request-Id'], isNotEmpty);

    expect(socket.sentMessages, hasLength(1));
    final fullRequest = _decodeVolcengineClientFrame(
      socket.sentMessages.single as Uint8List,
    );
    expect(fullRequest.messageType, 0x1);
    expect(fullRequest.serialization, 0x1);
    expect(fullRequest.compression, 0x1);
    expect(fullRequest.payload['request']['model_name'], 'bigmodel');
    expect(fullRequest.payload['audio']['format'], 'pcm');

    audioController.add(Uint8List.fromList([1, 2, 3, 4]));
    await Future<void>.delayed(Duration.zero);
    final audioFrame = socket.sentMessages.last as Uint8List;
    expect(audioFrame[1] >> 4, 0x2);

    socket.emitBytes(_buildVolcengineServerFrame({
      'result': {
        'text': '你好，世界',
        'utterances': [
          {
            'text': '你好，世界',
            'definite': true,
          },
        ],
      },
    }));
    await Future<void>.delayed(Duration.zero);

    expect(utterances, hasLength(1));
    expect(utterances.single.text, '你好，世界');
    expect(utterances.single.isFinal, isTrue);

    await audioController.close();
    await Future<void>.delayed(Duration.zero);
    final finalFrame = socket.sentMessages.last as Uint8List;
    expect(finalFrame[1] >> 4, 0x2);
    expect(finalFrame[1] & 0x0f, 0x2);
  });
}

({int messageType, int serialization, int compression, dynamic payload})
    _decodeVolcengineClientFrame(Uint8List frame) {
  final headerSize = (frame[0] & 0x0f) * 4;
  final messageType = frame[1] >> 4;
  final serialization = frame[2] >> 4;
  final compression = frame[2] & 0x0f;
  final payloadSize =
      ByteData.sublistView(frame, headerSize, headerSize + 4).getUint32(0);
  final compressedPayload =
      frame.sublist(headerSize + 4, headerSize + 4 + payloadSize);
  final payloadBytes =
      compression == 0x1 ? gzip.decode(compressedPayload) : compressedPayload;
  final payload = serialization == 0x1
      ? jsonDecode(utf8.decode(payloadBytes))
      : Uint8List.fromList(payloadBytes);
  return (
    messageType: messageType,
    serialization: serialization,
    compression: compression,
    payload: payload,
  );
}

Uint8List _buildVolcengineServerFrame(Map<String, dynamic> payload) {
  final compressed = gzip.encode(utf8.encode(jsonEncode(payload)));
  final builder = BytesBuilder(copy: false)
    ..add([0x11, 0x91, 0x11, 0x00])
    ..add(_uint32Bytes(1))
    ..add(_uint32Bytes(compressed.length))
    ..add(compressed);
  return builder.toBytes();
}

Uint8List _uint32Bytes(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
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

  void emitBytes(Uint8List message) {
    _controller.add(message);
  }
}
