import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../l10n/current_l10n.dart';
import '../settings/app_settings.dart';

class StreamingAsrUtterance {
  const StreamingAsrUtterance({
    required this.text,
    required this.isFinal,
  });

  final String text;
  final bool isFinal;
}

class VolcengineStreamingAsrService {
  VolcengineStreamingAsrService({
    WebSocketConnector? connector,
  }) : _connector = connector ?? _defaultConnector;

  static const _endpoint = 'wss://openspeech.bytedance.com/api/v2/asr';
  static const _sampleRate = 16000;
  static const _bitsPerSample = 16;
  static const _channels = 1;
  static const _bytesPer200Ms = 6400;

  final WebSocketConnector _connector;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Uint8List _pendingAudio = Uint8List(0);
  bool _sentFinalPacket = false;
  bool _running = false;
  Completer<void>? _startCompleter;

  bool get isRunning => _running;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required String languageTag,
    required void Function(StreamingAsrUtterance utterance) onUtterance,
    void Function(String error)? onError,
  }) async {
    if (_running) {
      throw StateError('Volcengine streaming ASR is already running.');
    }

    final settings = appSettingsController.settings;
    final appId = settings.volcengineAppId.trim();
    final accessToken = settings.volcengineAccessToken.trim();
    final cluster = settings.volcengineCluster.trim();
    if (appId.isEmpty) {
      throw Exception(currentL10n().volcengineAppIdRequired);
    }
    if (accessToken.isEmpty) {
      throw Exception(currentL10n().volcengineAccessTokenRequired);
    }
    if (cluster.isEmpty) {
      throw Exception(currentL10n().volcengineClusterRequired);
    }

    _running = true;
    _sentFinalPacket = false;
    _pendingAudio = Uint8List(0);
    _startCompleter = Completer<void>();

    try {
      final socket = await _connector(
        Uri.parse(_endpoint),
        headers: <String, dynamic>{
          'Authorization': 'Bearer; $accessToken',
        },
      );
      _socket = socket;
      _socketSubscription = socket.listen(
        (message) {
          if (message is List<int>) {
            _handleSocketMessage(
              Uint8List.fromList(message),
              onUtterance: onUtterance,
              onError: onError,
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          onError?.call('$error');
        },
        onDone: () {
          _running = false;
        },
        cancelOnError: true,
      );

      final requestPayload = _buildFullRequestPayload(
        appId: appId,
        accessToken: accessToken,
        cluster: cluster,
        languageTag: languageTag,
      );
      socket.add(_buildFullRequestFrame(requestPayload));

      _audioSubscription = audioStream.listen(
        _queueAudio,
        onError: (Object error, StackTrace stackTrace) async {
          onError?.call('$error');
          await cancel();
        },
        onDone: () async {
          await finish();
        },
        cancelOnError: true,
      );

      await _startCompleter!.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  Future<void> finish() async {
    if (!_running || _sentFinalPacket) {
      return;
    }
    _sentFinalPacket = true;
    final remaining = _drainPendingAudio();
    final frame = _buildAudioFrame(
      remaining,
      isFinal: true,
    );
    _socket?.add(frame);
  }

  Future<void> cancel() async {
    _running = false;
    _sentFinalPacket = true;
    _pendingAudio = Uint8List(0);
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
  }

  Map<String, dynamic> _buildFullRequestPayload({
    required String appId,
    required String accessToken,
    required String cluster,
    required String languageTag,
  }) {
    return <String, dynamic>{
      'app': <String, dynamic>{
        'appid': appId,
        'token': accessToken,
        'cluster': cluster,
      },
      'user': <String, dynamic>{
        'uid': appSettingsController.settings.clientId.trim(),
      },
      'audio': <String, dynamic>{
        'format': 'raw',
        'codec': 'raw',
        'rate': _sampleRate,
        'bits': _bitsPerSample,
        'channel': _channels,
        'language': languageTag,
      },
      'request': <String, dynamic>{
        'reqid': _generateRequestId(),
        'sequence': 1,
        'nbest': 1,
        'workflow':
            'audio_in,resample,partition,vad,fe,decode,itn,nlu_punctuate',
        'show_utterances': true,
        'result_type': 'single',
        'vad_signal': true,
        'start_silence_time': '5000',
        'vad_silence_time': '800',
      },
    };
  }

  Uint8List _buildFullRequestFrame(Map<String, dynamic> payload) {
    final payloadBytes = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(payload))),
    );
    return Uint8List.fromList(<int>[
      ..._buildHeader(
        messageType: _MessageType.clientFullRequest,
        messageTypeSpecificFlags: _MessageTypeFlag.none,
      ),
      ..._uint32Bytes(payloadBytes.length),
      ...payloadBytes,
    ]);
  }

  Uint8List _buildAudioFrame(
    Uint8List audioChunk, {
    required bool isFinal,
  }) {
    final payloadBytes = Uint8List.fromList(gzip.encode(audioChunk));
    return Uint8List.fromList(<int>[
      ..._buildHeader(
        messageType: _MessageType.clientAudioOnlyRequest,
        messageTypeSpecificFlags:
            isFinal ? _MessageTypeFlag.negativeSequence : _MessageTypeFlag.none,
      ),
      ..._uint32Bytes(payloadBytes.length),
      ...payloadBytes,
    ]);
  }

  Uint8List _buildHeader({
    required int messageType,
    required int messageTypeSpecificFlags,
  }) {
    return Uint8List.fromList(<int>[
      (_Protocol.version << 4) | _Protocol.defaultHeaderSize,
      (messageType << 4) | messageTypeSpecificFlags,
      (_Serialization.json << 4) | _Compression.gzip,
      0x00,
    ]);
  }

  void _queueAudio(Uint8List bytes) {
    if (!_running || _sentFinalPacket) {
      return;
    }

    final buffer = Uint8List(_pendingAudio.length + bytes.length)
      ..setRange(0, _pendingAudio.length, _pendingAudio)
      ..setRange(_pendingAudio.length, _pendingAudio.length + bytes.length,
          bytes);
    var offset = 0;
    while (buffer.length - offset >= _bytesPer200Ms) {
      final chunk = Uint8List.sublistView(buffer, offset, offset + _bytesPer200Ms);
      _socket?.add(_buildAudioFrame(chunk, isFinal: false));
      offset += _bytesPer200Ms;
    }

    if (offset < buffer.length) {
      _pendingAudio = Uint8List.sublistView(buffer, offset);
    } else {
      _pendingAudio = Uint8List(0);
    }
  }

  Uint8List _drainPendingAudio() {
    final bytes = _pendingAudio;
    _pendingAudio = Uint8List(0);
    return bytes;
  }

  void _handleSocketMessage(
    Uint8List bytes, {
    required void Function(StreamingAsrUtterance utterance) onUtterance,
    void Function(String error)? onError,
  }) {
    final response = _parseResponse(bytes);
    final payload = response.payload;
    if (payload == null) {
      return;
    }

    final code = payload['code'];
    if (code is int && code != 1000) {
      onError?.call(payload['message']?.toString() ?? 'ASR request failed.');
      return;
    }

    _startCompleter?.complete();
    _startCompleter = null;

    final result = payload['result'];
    if (result is! List || result.isEmpty) {
      return;
    }

    for (final item in result) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final utterances = item['utterances'];
      if (utterances is List && utterances.isNotEmpty) {
        for (final utterance in utterances) {
          if (utterance is! Map<String, dynamic>) {
            continue;
          }
          final text = utterance['text']?.toString().trim() ?? '';
          if (text.isEmpty) {
            continue;
          }
          onUtterance(
            StreamingAsrUtterance(
              text: text,
              isFinal: utterance['definite'] == true,
            ),
          );
        }
        continue;
      }

      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        continue;
      }
      onUtterance(
        StreamingAsrUtterance(
          text: text,
          isFinal: (payload['sequence'] as int?)?.isNegative ?? false,
        ),
      );
    }
  }

  _ParsedVolcengineResponse _parseResponse(Uint8List bytes) {
    if (bytes.length < 8) {
      return const _ParsedVolcengineResponse(payload: null);
    }

    final headerSize = bytes[0] & 0x0f;
    final messageType = bytes[1] >> 4;
    final compression = bytes[2] & 0x0f;
    final payloadStart = headerSize * 4;
    if (payloadStart > bytes.length) {
      return const _ParsedVolcengineResponse(payload: null);
    }

    final payloadBytes = bytes.sublist(payloadStart);
    int? sequence;
    Uint8List contentBytes = Uint8List(0);

    switch (messageType) {
      case _MessageType.serverFullResponse:
        if (payloadBytes.length >= 4) {
          final size = _uint32FromBytes(payloadBytes, 0);
          final end = 4 + size;
          if (end <= payloadBytes.length) {
            contentBytes = Uint8List.sublistView(payloadBytes, 4, end);
          }
        }
        break;
      case _MessageType.serverAck:
        if (payloadBytes.length >= 4) {
          sequence = _int32FromBytes(payloadBytes, 0);
        }
        if (payloadBytes.length >= 8) {
          final size = _uint32FromBytes(payloadBytes, 4);
          final end = 8 + size;
          if (end <= payloadBytes.length) {
            contentBytes = Uint8List.sublistView(payloadBytes, 8, end);
          }
        }
        break;
      case _MessageType.serverErrorResponse:
        if (payloadBytes.length >= 8) {
          final size = _uint32FromBytes(payloadBytes, 4);
          final end = 8 + size;
          if (end <= payloadBytes.length) {
            contentBytes = Uint8List.sublistView(payloadBytes, 8, end);
          }
        }
        break;
    }

    if (contentBytes.isEmpty) {
      return _ParsedVolcengineResponse(
        payload: null,
        sequence: sequence,
      );
    }

    final decodedBytes = compression == _Compression.gzip
        ? Uint8List.fromList(gzip.decode(contentBytes))
        : contentBytes;
    final payload = jsonDecode(utf8.decode(decodedBytes));
    return _ParsedVolcengineResponse(
      payload: payload is Map<String, dynamic> ? payload : null,
      sequence: sequence,
    );
  }

  String _generateRequestId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = (DateTime.now().hashCode & 0xffffffff).toRadixString(16);
    return '$timestamp-$random';
  }

  List<int> _uint32Bytes(int value) {
    return <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  int _uint32FromBytes(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  int _int32FromBytes(Uint8List bytes, int offset) {
    final value = _uint32FromBytes(bytes, offset);
    return value & 0x80000000 != 0 ? value - 0x100000000 : value;
  }

  static Future<WebSocket> _defaultConnector(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) {
    return WebSocket.connect(
      uri.toString(),
      headers: headers,
    );
  }
}

class _ParsedVolcengineResponse {
  const _ParsedVolcengineResponse({
    required this.payload,
    this.sequence,
  });

  final Map<String, dynamic>? payload;
  final int? sequence;
}

typedef WebSocketConnector = Future<WebSocket> Function(
  Uri uri, {
  Map<String, dynamic>? headers,
});

abstract final class _Protocol {
  static const version = 0x1;
  static const defaultHeaderSize = 0x1;
}

abstract final class _MessageType {
  static const clientFullRequest = 0x1;
  static const clientAudioOnlyRequest = 0x2;
  static const serverFullResponse = 0x9;
  static const serverAck = 0xb;
  static const serverErrorResponse = 0xf;
}

abstract final class _MessageTypeFlag {
  static const none = 0x0;
  static const negativeSequence = 0x2;
}

abstract final class _Serialization {
  static const json = 0x1;
}

abstract final class _Compression {
  static const gzip = 0x1;
}
