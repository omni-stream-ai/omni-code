import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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

class TencentCloudStreamingAsrService {
  TencentCloudStreamingAsrService({
    WebSocketConnector? connector,
  }) : _connector = connector ?? _defaultConnector;

  static const _host = 'asr.cloud.tencent.com';
  static const _pathPrefix = '/asr/v2/';
  static const _bytesPer200Ms = 6400;
  static const _sendInterval = Duration(milliseconds: 200);

  final WebSocketConnector _connector;

  final List<int> _audioBuffer = <int>[];
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _audioFlushTimer;
  bool _sentEndSignal = false;
  bool _running = false;
  bool _socketReady = false;
  Completer<void>? _startCompleter;

  bool get isRunning => _running;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required String languageTag,
    required void Function(StreamingAsrUtterance utterance) onUtterance,
    void Function(String error)? onError,
  }) async {
    if (_running) {
      throw StateError('Tencent Cloud streaming ASR is already running.');
    }

    final settings = appSettingsController.settings;
    final appId = settings.tencentCloudAppId.trim();
    final secretId = settings.tencentCloudSecretId.trim();
    final secretKey = settings.tencentCloudSecretKey.trim();
    if (appId.isEmpty) {
      throw Exception(currentL10n().tencentCloudAppIdRequired);
    }
    if (secretId.isEmpty) {
      throw Exception(currentL10n().tencentCloudSecretIdRequired);
    }
    if (secretKey.isEmpty) {
      throw Exception(currentL10n().tencentCloudSecretKeyRequired);
    }

    final normalizedAppId = int.tryParse(appId);
    if (normalizedAppId == null) {
      throw Exception(currentL10n().tencentCloudAppIdInvalid);
    }

    _running = true;
    _socketReady = false;
    _sentEndSignal = false;
    _audioBuffer.clear();
    _startCompleter = Completer<void>();

    try {
      final uri = _buildSignedUri(
        appId: normalizedAppId.toString(),
        secretId: secretId,
        secretKey: secretKey,
        languageTag: languageTag,
      );
      debugPrint(
        '[tencent-asr] connecting appId=$normalizedAppId engine=${_engineModelTypeFor(languageTag)}',
      );
      final socket = await _connector(uri);
      debugPrint('[tencent-asr] websocket connected');
      _socket = socket;
      _socketSubscription = socket.listen(
        (message) {
          if (message is String) {
            debugPrint('[tencent-asr] text message: $message');
            _handleSocketMessage(
              message,
              onUtterance: onUtterance,
              onError: onError,
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[tencent-asr] websocket error: $error');
          onError?.call('$error');
        },
        onDone: () {
          debugPrint('[tencent-asr] websocket closed');
          _running = false;
        },
        cancelOnError: true,
      );

      _audioSubscription = audioStream.listen(
        (bytes) {
          if (!_running || _sentEndSignal) {
            return;
          }
          _audioBuffer.addAll(bytes);
        },
        onError: (Object error, StackTrace stackTrace) async {
          debugPrint('[tencent-asr] audio stream error: $error');
          onError?.call('$error');
          await cancel();
        },
        onDone: () async {
          debugPrint('[tencent-asr] audio stream completed');
          await finish();
        },
        cancelOnError: true,
      );

      _audioFlushTimer = Timer.periodic(_sendInterval, (_) {
        _flushAudioChunk();
      });

      await _startCompleter!.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  Future<void> finish() async {
    if (!_running || _sentEndSignal) {
      return;
    }
    _flushAudioChunk(forceAll: true);
    _sentEndSignal = true;
    debugPrint('[tencent-asr] sending end marker');
    _socket?.add(jsonEncode(<String, dynamic>{'type': 'end'}));
  }

  Future<void> cancel() async {
    _running = false;
    _socketReady = false;
    _sentEndSignal = true;
    _audioBuffer.clear();
    _audioFlushTimer?.cancel();
    _audioFlushTimer = null;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
  }

  Uri _buildSignedUri({
    required String appId,
    required String secretId,
    required String secretKey,
    required String languageTag,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expired = timestamp + 24 * 60 * 60;
    final nonce = Random.secure().nextInt(1 << 31);
    final voiceId = _generateVoiceId();
    final engineModelType = _engineModelTypeFor(languageTag);

    final query = <String, String>{
      'secretid': secretId,
      'timestamp': '$timestamp',
      'expired': '$expired',
      'nonce': '$nonce',
      'engine_model_type': engineModelType,
      'voice_format': '1',
      'voice_id': voiceId,
      'needvad': '1',
      'filter_dirty': '0',
      'filter_modal': '0',
      'filter_punc': '0',
      'convert_num_mode': '1',
    };

    final sortedKeys = query.keys.toList()..sort();
    final canonicalQuery = sortedKeys
        .map((key) => '$key=${Uri.encodeQueryComponent(query[key]!)}')
        .join('&');
    final signSource = 'asr.cloud.tencent.com$_pathPrefix$appId?$canonicalQuery';
    final signature = base64Encode(
      Hmac(sha1, utf8.encode(secretKey)).convert(utf8.encode(signSource)).bytes,
    );
    final signedQuery = <String, String>{
      ...query,
      'signature': signature,
    };

    return Uri.https(
      _host,
      '$_pathPrefix$appId',
      signedQuery,
    ).replace(scheme: 'wss');
  }

  String _engineModelTypeFor(String languageTag) {
    final normalized = languageTag.toLowerCase();
    if (normalized.startsWith('zh')) {
      return '16k_zh';
    }
    return '16k_en';
  }

  void _flushAudioChunk({bool forceAll = false}) {
    if (!_running || !_socketReady || _sentEndSignal || _audioBuffer.isEmpty) {
      return;
    }

    if (forceAll) {
      final chunk = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      if (chunk.isNotEmpty) {
        debugPrint('[tencent-asr] sending final audio chunk bytes=${chunk.length}');
        _socket?.add(chunk);
      }
      return;
    }

    if (_audioBuffer.length < _bytesPer200Ms) {
      return;
    }
    final chunk = Uint8List.fromList(_audioBuffer.sublist(0, _bytesPer200Ms));
    _audioBuffer.removeRange(0, _bytesPer200Ms);
    debugPrint('[tencent-asr] sending audio chunk bytes=${chunk.length}');
    _socket?.add(chunk);
  }

  void _handleSocketMessage(
    String message, {
    required void Function(StreamingAsrUtterance utterance) onUtterance,
    void Function(String error)? onError,
  }) {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final code = decoded['code'];
    if (code is int && code != 0) {
      onError?.call(decoded['message']?.toString() ?? 'ASR request failed.');
      return;
    }

    if (!_socketReady) {
      _socketReady = true;
      _startCompleter?.complete();
      _startCompleter = null;
    }

    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      return;
    }

    final resultText = result['voice_text_str']?.toString().trim() ?? '';
    if (resultText.isEmpty) {
      return;
    }

    final sliceType = result['slice_type'];
    final isFinal =
        sliceType == 2 || sliceType == '2' || decoded['final'] == 1;
    debugPrint(
      '[tencent-asr] utterance sliceType=$sliceType final=$isFinal text=$resultText',
    );
    onUtterance(
      StreamingAsrUtterance(
        text: resultText,
        isFinal: isFinal,
      ),
    );
  }

  String _generateVoiceId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return 'omni-$timestamp-$random';
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

typedef WebSocketConnector = Future<WebSocket> Function(
  Uri uri, {
  Map<String, dynamic>? headers,
});
