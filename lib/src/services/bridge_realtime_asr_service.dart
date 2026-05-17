import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../bridge_client.dart';
import '../settings/app_settings.dart';

class BridgeRealtimeAsrUtterance {
  const BridgeRealtimeAsrUtterance({
    required this.text,
    required this.isFinal,
  });

  final String text;
  final bool isFinal;
}

class BridgeRealtimeAsrConfig {
  const BridgeRealtimeAsrConfig({
    this.asrModel,
    this.vadModel,
    this.sampleRateHz = 16000,
    this.channels = 1,
    this.enableVad = true,
    this.endpointTrailingSilenceMs,
    this.vadMinSilenceMs,
  });

  final String? asrModel;
  final String? vadModel;
  final int sampleRateHz;
  final int channels;
  final bool enableVad;
  final int? endpointTrailingSilenceMs;
  final int? vadMinSilenceMs;

  Map<String, dynamic> toSessionUpdateJson() {
    return <String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        if (asrModel != null) 'asr_model': asrModel,
        if (vadModel != null) 'vad_model': vadModel,
        'sample_rate_hz': sampleRateHz,
        'channels': channels,
        'enable_vad': enableVad,
        if (endpointTrailingSilenceMs != null)
          'endpoint_trailing_silence_ms': endpointTrailingSilenceMs,
        if (vadMinSilenceMs != null) 'vad_min_silence_ms': vadMinSilenceMs,
      },
    };
  }
}

class BridgeRealtimeAsrService {
  BridgeRealtimeAsrService({
    BridgeClient? client,
    BridgeRealtimeWebSocketConnector? connector,
  })  : _client = client ?? bridgeClient,
        _connector = connector ?? _defaultConnector;

  final BridgeClient _client;
  final BridgeRealtimeWebSocketConnector _connector;

  BridgeRealtimeSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _startCompleter;
  bool _running = false;
  bool _connected = false;

  bool get isRunning => _running;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String error)? onError,
    BridgeRealtimeAsrConfig? config,
  }) async {
    if (_running) {
      throw StateError('Bridge realtime ASR is already running.');
    }

    _running = true;
    _connected = false;
    _startCompleter = Completer<void>();

    try {
      final descriptor = await _client.getSpeechRealtimeDescriptor();
      final sessionDefaults =
          descriptor['session_defaults'] as Map<String, dynamic>? ??
              const <String, dynamic>{};
      final ready = sessionDefaults['ready'] as bool? ?? false;
      if (!ready) {
        final missing =
            (sessionDefaults['missing_requirements'] as List<dynamic>? ??
                    const <dynamic>[])
                .map((item) => item.toString())
                .where((item) => item.trim().isNotEmpty)
                .join(', ');
        throw Exception(
          missing.isEmpty
              ? 'Bridge realtime speech is not ready.'
              : 'Bridge realtime speech is not ready: $missing',
        );
      }

      final websocketPath =
          descriptor['websocket_path'] as String? ?? '/speech/realtime/ws';
      final socket = await _connector(
        _webSocketUri(websocketPath),
        headers: _headers(),
      );

      _socket = socket;
      _socketSubscription = socket.messages.listen(
        (message) {
          if (message is! String) {
            return;
          }
          _handleSocketMessage(
            message,
            onUtterance: onUtterance,
            onSpeechStarted: onSpeechStarted,
            onError: onError,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[bridge-realtime-asr] websocket error: $error');
          if (!_startCompleterCompleted) {
            _startCompleter?.completeError(error, stackTrace);
          }
          onError?.call('$error');
        },
        onDone: () {
          debugPrint('[bridge-realtime-asr] websocket closed');
          _running = false;
          _connected = false;
        },
        cancelOnError: true,
      );

      _audioSubscription = audioStream.listen(
        (bytes) {
          if (!_running || !_connected) {
            return;
          }
          _socket?.add(bytes);
        },
        onError: (Object error, StackTrace stackTrace) async {
          debugPrint('[bridge-realtime-asr] audio stream error: $error');
          onError?.call('$error');
          await cancel();
        },
        onDone: () async {
          await finish();
        },
        cancelOnError: true,
      );

      await _startCompleter!.future.timeout(const Duration(seconds: 6));
      if (config != null) {
        _socket?.add(jsonEncode(config.toSessionUpdateJson()));
      }
    } catch (_) {
      _running = false;
      _connected = false;
      rethrow;
    }
  }

  Future<void> finish() async {
    if (!_running || !_connected) {
      return;
    }
    _socket?.add(jsonEncode(<String, dynamic>{
      'type': 'input_audio_buffer.commit',
    }));
  }

  Future<void> cancel() async {
    _running = false;
    _connected = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
  }

  void _handleSocketMessage(
    String message, {
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String error)? onError,
  }) {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final type = decoded['type'] as String? ?? '';
    if (type == 'session.created' || type == 'session.updated') {
      final session = decoded['session'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final ready = session['ready'] as bool? ?? false;
      final lastError = session['last_error']?.toString();
      if (ready) {
        _connected = true;
        if (!_startCompleterCompleted) {
          _startCompleter?.complete();
        }
        return;
      }
      final errorMessage = (lastError?.trim().isNotEmpty == true)
          ? lastError!
          : 'Bridge realtime speech session is not ready.';
      if (!_startCompleterCompleted) {
        _startCompleter?.completeError(Exception(errorMessage));
      }
      onError?.call(errorMessage);
      return;
    }

    if (type == 'error') {
      final payload = decoded['error'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final errorMessage =
          payload['message']?.toString() ?? 'Bridge realtime ASR error.';
      if (!_startCompleterCompleted) {
        _startCompleter?.completeError(Exception(errorMessage));
      }
      onError?.call(errorMessage);
      return;
    }

    if (type == 'input_audio_buffer.speech_started') {
      onSpeechStarted?.call();
      return;
    }

    if (type == 'response.audio_transcript.delta') {
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        return;
      }
      onUtterance(
        BridgeRealtimeAsrUtterance(
          text: text,
          isFinal: false,
        ),
      );
      return;
    }

    if (type == 'response.audio_transcript.completed') {
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        return;
      }
      onUtterance(
        BridgeRealtimeAsrUtterance(
          text: text,
          isFinal: true,
        ),
      );
    }
  }

  bool get _startCompleterCompleted {
    final completer = _startCompleter;
    return completer == null || completer.isCompleted;
  }

  Uri _webSocketUri(String websocketPath) {
    final baseUri = Uri.parse(_client.baseUrl);
    return baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: websocketPath,
    );
  }

  Map<String, dynamic> _headers() {
    final settings = appSettingsController.settings;
    final headers = <String, dynamic>{
      'X-Omni-Code-Client-Id': settings.clientId,
    };
    if (settings.bridgeToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.bridgeToken.trim()}';
    }
    return headers;
  }

  static Future<BridgeRealtimeSocket> _defaultConnector(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) {
    return WebSocket.connect(
      uri.toString(),
      headers: headers,
    ).then(_IoBridgeRealtimeSocket.new);
  }
}

abstract class BridgeRealtimeSocket {
  Stream<dynamic> get messages;

  void add(dynamic data);

  Future<void> close();
}

class _IoBridgeRealtimeSocket implements BridgeRealtimeSocket {
  _IoBridgeRealtimeSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;

  @override
  void add(dynamic data) {
    _socket.add(data);
  }

  @override
  Future<void> close() => _socket.close();
}

typedef BridgeRealtimeWebSocketConnector = Future<BridgeRealtimeSocket>
    Function(
  Uri uri, {
  Map<String, dynamic>? headers,
});
