import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../bridge_client.dart';
import '../plugins/speech_plugin_models.dart';
import '../plugins/speech_plugin_registry.dart';
import '../settings/app_settings.dart';

class BridgeRealtimeAsrUtterance {
  const BridgeRealtimeAsrUtterance({
    required this.text,
    required this.isFinal,
    this.speakerFilterActive = false,
    this.speakerVerified = false,
    this.speakerMatched,
    this.wakeWordActive = false,
    this.wakeWordVerified = false,
    this.wakeWordMatched,
  });

  final String text;
  final bool isFinal;
  final bool speakerFilterActive;
  final bool speakerVerified;
  final bool? speakerMatched;
  final bool wakeWordActive;
  final bool wakeWordVerified;
  final bool? wakeWordMatched;

  bool get speakerAccepted => !speakerFilterActive || speakerMatched == true;
  bool get wakeWordAccepted => !wakeWordActive || wakeWordMatched == true;
  bool get accepted => speakerAccepted && wakeWordAccepted;
  bool get pendingVerification =>
      (speakerFilterActive && !speakerVerified) ||
      (wakeWordActive && !wakeWordVerified);
  bool get rejected =>
      (speakerFilterActive && speakerVerified && speakerMatched == false) ||
      (wakeWordActive && wakeWordVerified && wakeWordMatched == false);
}

class BridgeRealtimeAsrConfig {
  const BridgeRealtimeAsrConfig({
    this.asrModel,
    this.vadModel,
    this.sampleRateHz = 16000,
    this.channels = 1,
    this.enableVad = true,
    this.enableWakeWord = false,
    this.wakeWordDetector,
    this.wakeWords = const <String>[],
    this.stripWakeWord = true,
    this.endpointTrailingSilenceMs,
    this.vadMinSilenceMs,
  });

  final String? asrModel;
  final String? vadModel;
  final int sampleRateHz;
  final int channels;
  final bool enableVad;
  final bool enableWakeWord;
  final String? wakeWordDetector;
  final List<String> wakeWords;
  final bool stripWakeWord;
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
  bool _awaitingConfiguredSession = false;
  bool _running = false;
  bool _connected = false;
  SpeechPluginManifest? _activeRealtimePluginManifest;
  SpeechPluginCapabilityConfig? _activeRealtimePluginConfig;

  /// Cached websocket path from a previous successful descriptor fetch.
  /// Allows skipping the HTTP readiness check on subsequent starts.
  static String? _cachedWebsocketPath;

  static const _defaultWebsocketPath = '/speech/realtime/ws';
  static const _defaultDescriptorPath = '/speech/realtime';

  /// Clears the cached websocket path, e.g. when the bridge server address
  /// changes. The next [start] will perform a full readiness check.
  static void clearCache() {
    _cachedWebsocketPath = null;
  }

  bool get isRunning => _running;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
    void Function(String error)? onError,
    BridgeRealtimeAsrConfig? config,
  }) async {
    if (_running) {
      throw StateError('Bridge realtime ASR is already running.');
    }

    _running = true;
    _connected = false;
    _awaitingConfiguredSession = config != null;
    _startCompleter = Completer<void>();
    _activeRealtimePluginManifest = null;
    _activeRealtimePluginConfig = null;

    try {
      final selectedRealtimePlugin =
          speechPluginRegistry.selectedPluginForCapability(
        SpeechPluginCapability.realtimeAsr,
      );
      _activeRealtimePluginManifest = selectedRealtimePlugin?.manifest;
      _activeRealtimePluginConfig = selectedRealtimePlugin == null
          ? null
          : _resolvedRealtimePluginConfig(selectedRealtimePlugin.manifest);

      // Fast path: if we have a cached websocket path from a previous
      // successful start, try connecting directly without the HTTP
      // readiness check. On failure, fall through to the full flow.
      if (_cachedWebsocketPath != null && selectedRealtimePlugin == null) {
        debugPrint(
          '[bridge-realtime-asr] fast path: connecting with cached path '
          '$_cachedWebsocketPath',
        );
        try {
          await _connectWebSocket(
            _cachedWebsocketPath!,
            audioStream: audioStream,
            onUtterance: onUtterance,
            onSpeechStarted: onSpeechStarted,
            onWakeWordDetected: onWakeWordDetected,
            onError: onError,
            config: config,
          );
          return;
        } catch (error) {
          debugPrint(
            '[bridge-realtime-asr] fast path failed ($error), '
            'falling back to full check',
          );
          _cachedWebsocketPath = null;
          // Reset state for the fallback attempt.
          await _cleanupSocket();
          _startCompleter = Completer<void>();
          _connected = false;
          _awaitingConfiguredSession = config != null;
        }
      }

      // Full flow: HTTP readiness check + WebSocket connect.
      final descriptor = await _getRealtimeDescriptor();
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
          descriptor['websocket_path'] as String? ?? _defaultWebsocketPath;
      _cachedWebsocketPath = websocketPath;

      await _connectWebSocket(
        websocketPath,
        audioStream: audioStream,
        onUtterance: onUtterance,
        onSpeechStarted: onSpeechStarted,
        onWakeWordDetected: onWakeWordDetected,
        onError: onError,
        config: config,
      );
    } catch (_) {
      _running = false;
      _connected = false;
      _awaitingConfiguredSession = false;
      await _cleanupSocket();
      rethrow;
    }
  }

  /// Establishes a WebSocket connection, sets up listeners, sends config,
  /// and waits for the session to become ready.
  Future<void> _connectWebSocket(
    String websocketPath, {
    required Stream<Uint8List> audioStream,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
    void Function(String error)? onError,
    BridgeRealtimeAsrConfig? config,
  }) async {
    final socket = await _connector(
      _webSocketUri(websocketPath),
      headers: _headers(),
    );

    _socket = socket;
    _socketSubscription = socket.messages.listen(
      (message) {
        if (_usesVolcengineSaucProtocol) {
          _handleVolcengineSaucMessage(
            message,
            onUtterance: onUtterance,
            onError: onError,
          );
          return;
        }
        if (message is! String) {
          return;
        }
        _handleSocketMessage(
          message,
          onUtterance: onUtterance,
          onSpeechStarted: onSpeechStarted,
          onWakeWordDetected: onWakeWordDetected,
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
        if (_usesVolcengineSaucProtocol) {
          _socket?.add(_buildVolcengineSaucAudioRequest(bytes));
        } else {
          _socket?.add(bytes);
        }
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

    if (_usesVolcengineSaucProtocol) {
      _socket?.add(_buildVolcengineSaucFullClientRequest(config));
      _connected = true;
      if (!_startCompleterCompleted) {
        _startCompleter?.complete();
      }
    } else if (config != null &&
        _activeRealtimePluginManifest?.transport !=
            SpeechPluginTransport.realtimeWebsocket) {
      final update = jsonEncode(config.toSessionUpdateJson());
      debugPrint('[bridge-realtime-asr] sending session.update $update');
      _socket?.add(update);
    }
    if (_activeRealtimePluginManifest?.transport ==
            SpeechPluginTransport.realtimeWebsocket &&
        !_usesVolcengineSaucProtocol) {
      _connected = true;
      if (!_startCompleterCompleted) {
        _startCompleter?.complete();
      }
    }
    await _startCompleter!.future.timeout(const Duration(seconds: 6));
  }

  /// Tears down the current socket and audio subscriptions without
  /// modifying the running/connected flags.
  Future<void> _cleanupSocket() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> finish() async {
    if (!_running || !_connected) {
      return;
    }
    if (_usesVolcengineSaucProtocol) {
      _socket?.add(_buildVolcengineSaucAudioRequest(
        Uint8List(0),
        isLast: true,
      ));
      return;
    }
    _socket?.add(jsonEncode(<String, dynamic>{
      'type': 'input_audio_buffer.commit',
    }));
  }

  Future<void> cancel() async {
    _running = false;
    _connected = false;
    _awaitingConfiguredSession = false;
    _activeRealtimePluginManifest = null;
    _activeRealtimePluginConfig = null;
    await _cleanupSocket();
  }

  bool get _usesVolcengineSaucProtocol {
    final config = _activeRealtimePluginConfig;
    if (config == null) {
      return false;
    }
    final protocol = config.eventMap['protocol']?.trim().toLowerCase();
    return protocol == 'volcengine_sauc';
  }

  Uint8List _buildVolcengineSaucFullClientRequest(
    BridgeRealtimeAsrConfig? config,
  ) {
    final settings = appSettingsController.settings;
    final request = <String, dynamic>{
      'user': <String, dynamic>{
        'uid': settings.clientId,
        'platform': 'omni-code',
      },
      'audio': <String, dynamic>{
        'format': 'pcm',
        'codec': 'raw',
        'rate': config?.sampleRateHz ?? 16000,
        'bits': 16,
        'channel': config?.channels ?? 1,
      },
      'request': <String, dynamic>{
        'model_name': _volcengineSaucModelName(),
        'enable_itn': true,
        'enable_punc': true,
        'show_utterances': true,
        'result_type': 'full',
      },
    };
    return _buildVolcengineSaucFrame(
      messageType: 0x1,
      flags: 0x0,
      serialization: 0x1,
      compression: 0x1,
      payload: gzip.encode(utf8.encode(jsonEncode(request))),
    );
  }

  Uint8List _buildVolcengineSaucAudioRequest(
    Uint8List audioBytes, {
    bool isLast = false,
  }) {
    return _buildVolcengineSaucFrame(
      messageType: 0x2,
      flags: isLast ? 0x2 : 0x0,
      serialization: 0x0,
      compression: 0x1,
      payload: gzip.encode(audioBytes),
    );
  }

  Uint8List _buildVolcengineSaucFrame({
    required int messageType,
    required int flags,
    required int serialization,
    required int compression,
    required List<int> payload,
  }) {
    final frame = BytesBuilder(copy: false)
      ..add([
        0x11,
        ((messageType & 0x0f) << 4) | (flags & 0x0f),
        ((serialization & 0x0f) << 4) | (compression & 0x0f),
        0x00,
      ])
      ..add(_uint32Bytes(payload.length))
      ..add(payload);
    return frame.toBytes();
  }

  void _handleVolcengineSaucMessage(
    dynamic message, {
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function(String error)? onError,
  }) {
    if (message is! List<int>) {
      return;
    }
    final bytes = Uint8List.fromList(message);
    if (bytes.length < 8) {
      return;
    }
    final headerSize = (bytes[0] & 0x0f) * 4;
    if (headerSize < 4 || bytes.length < headerSize + 4) {
      return;
    }
    final messageType = (bytes[1] & 0xf0) >> 4;
    final flags = bytes[1] & 0x0f;
    final serialization = (bytes[2] & 0xf0) >> 4;
    final compression = bytes[2] & 0x0f;
    var offset = headerSize;

    if (messageType == 0xf) {
      if (bytes.length < offset + 8) {
        return;
      }
      final code = _readUint32(bytes, offset);
      offset += 4;
      final size = _readUint32(bytes, offset);
      offset += 4;
      if (bytes.length < offset + size) {
        return;
      }
      final errorPayload = utf8.decode(bytes.sublist(offset, offset + size));
      final message = 'Volcengine realtime ASR error $code: $errorPayload';
      if (!_startCompleterCompleted) {
        _startCompleter?.completeError(Exception(message));
      }
      onError?.call(message);
      return;
    }

    if (messageType != 0x9) {
      return;
    }
    if (flags == 0x1 || flags == 0x3) {
      if (bytes.length < offset + 4) {
        return;
      }
      offset += 4;
    }
    if (bytes.length < offset + 4) {
      return;
    }
    final payloadSize = _readUint32(bytes, offset);
    offset += 4;
    if (bytes.length < offset + payloadSize) {
      return;
    }
    var payload = bytes.sublist(offset, offset + payloadSize);
    if (compression == 0x1) {
      payload = Uint8List.fromList(gzip.decode(payload));
    }
    if (serialization != 0x1) {
      return;
    }
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    _handleVolcengineSaucResponse(
      decoded,
      isLastFrame: flags == 0x3,
      onUtterance: onUtterance,
    );
  }

  void _handleVolcengineSaucResponse(
    Map<String, dynamic> decoded, {
    required bool isLastFrame,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
  }) {
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      return;
    }
    final utterances = result['utterances'];
    if (utterances is List && utterances.isNotEmpty) {
      for (final item in utterances) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final text = item['text']?.toString().trim() ?? '';
        if (text.isEmpty) {
          continue;
        }
        onUtterance(
          BridgeRealtimeAsrUtterance(
            text: text,
            isFinal: item['definite'] as bool? ?? isLastFrame,
          ),
        );
      }
      return;
    }
    final text = result['text']?.toString().trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    onUtterance(
      BridgeRealtimeAsrUtterance(
        text: text,
        isFinal: isLastFrame,
      ),
    );
  }

  Uint8List _uint32Bytes(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  int _readUint32(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4).getUint32(
      0,
      Endian.big,
    );
  }

  void _handleSocketMessage(
    String message, {
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
    void Function(String error)? onError,
  }) {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final pluginManifest = _activeRealtimePluginManifest;
    if (pluginManifest?.transport == SpeechPluginTransport.realtimeWebsocket) {
      _handleCustomRealtimePluginMessage(
        decoded,
        manifest: pluginManifest!,
        onUtterance: onUtterance,
        onSpeechStarted: onSpeechStarted,
        onWakeWordDetected: onWakeWordDetected,
      );
      return;
    }

    final type = decoded['type'] as String? ?? '';
    if (type == 'session.created' || type == 'session.updated') {
      final session = decoded['session'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final ready = session['ready'] as bool? ?? false;
      final lastError = session['last_error']?.toString();
      debugPrint(
        '[bridge-realtime-asr] received $type ready=$ready '
        'enableWakeWord=${session['enable_wake_word']} '
        'wakeWordDetector=${session['wake_word_detector']} '
        'wakeWords=${session['wake_words']} lastError=$lastError',
      );
      if (ready) {
        if (_awaitingConfiguredSession && type != 'session.updated') {
          return;
        }
        _awaitingConfiguredSession = false;
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

    if (type == 'input_audio_buffer.wake_word_detected') {
      final keyword = decoded['keyword']?.toString().trim() ?? '';
      onWakeWordDetected?.call(keyword);
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
          speakerFilterActive: _speakerFilterActive(decoded),
          speakerVerified: _speakerFilterVerified(decoded),
          speakerMatched: _speakerFilterMatched(decoded),
          wakeWordActive: _wakeWordActive(decoded),
          wakeWordVerified: _wakeWordVerified(decoded),
          wakeWordMatched: _wakeWordMatched(decoded),
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
          speakerFilterActive: _speakerFilterActive(decoded),
          speakerVerified: _speakerFilterVerified(decoded),
          speakerMatched: _speakerFilterMatched(decoded),
          wakeWordActive: _wakeWordActive(decoded),
          wakeWordVerified: _wakeWordVerified(decoded),
          wakeWordMatched: _wakeWordMatched(decoded),
        ),
      );
    }
  }

  bool _speakerFilterActive(Map<String, dynamic> event) {
    final status = event['speaker_filter'];
    if (status is! Map<String, dynamic>) {
      return false;
    }
    return status['active'] as bool? ?? false;
  }

  bool _speakerFilterVerified(Map<String, dynamic> event) {
    final status = event['speaker_filter'];
    if (status is! Map<String, dynamic>) {
      return false;
    }
    return status['verified'] as bool? ?? false;
  }

  bool? _speakerFilterMatched(Map<String, dynamic> event) {
    final status = event['speaker_filter'];
    if (status is! Map<String, dynamic>) {
      return null;
    }
    return status['matched'] as bool?;
  }

  bool _wakeWordActive(Map<String, dynamic> event) {
    final status = event['wake_word'];
    if (status is! Map<String, dynamic>) {
      return false;
    }
    return status['active'] as bool? ?? false;
  }

  bool _wakeWordVerified(Map<String, dynamic> event) {
    final status = event['wake_word'];
    if (status is! Map<String, dynamic>) {
      return false;
    }
    return status['verified'] as bool? ?? false;
  }

  bool? _wakeWordMatched(Map<String, dynamic> event) {
    final status = event['wake_word'];
    if (status is! Map<String, dynamic>) {
      return null;
    }
    return status['matched'] as bool?;
  }

  bool get _startCompleterCompleted {
    final completer = _startCompleter;
    return completer == null || completer.isCompleted;
  }

  Future<Map<String, dynamic>> _getRealtimeDescriptor() async {
    final plugin = speechPluginRegistry.selectedPluginForCapability(
      SpeechPluginCapability.realtimeAsr,
    );
    if (plugin == null) {
      return _client.getSpeechRealtimeDescriptor();
    }
    final manifest = plugin.manifest;
    final config = _resolvedRealtimePluginConfig(manifest);
    if (config == null) {
      throw UnsupportedError(
        'Selected plugin does not support realtime ASR: ${manifest.id}',
      );
    }
    return switch (config.transport) {
      SpeechPluginTransport.bridgeOpenAiCompatible =>
        _buildBridgeCompatibleDescriptor(config),
      SpeechPluginTransport.realtimeWebsocket =>
        _buildCustomRealtimeDescriptor(config, manifest.id),
      SpeechPluginTransport.metadataOnly => throw UnsupportedError(
          'Realtime ASR plugin is installed but not executable yet: ${manifest.id}',
        ),
      SpeechPluginTransport.openAiCompatible => throw UnsupportedError(
          'OpenAI-compatible transport is not supported for realtime ASR: ${manifest.id}',
        ),
    };
  }

  Future<Map<String, dynamic>> _buildBridgeCompatibleDescriptor(
    SpeechPluginCapabilityConfig config,
  ) async {
    final path = _normalizeRealtimePath(config.path);
    final websocketPath = path.endsWith('/ws') ? path : '$path/ws';
    return <String, dynamic>{
      'websocket_path': websocketPath,
      'session_defaults': const <String, dynamic>{
        'ready': true,
        'missing_requirements': <dynamic>[],
      },
    };
  }

  Future<Map<String, dynamic>> _buildCustomRealtimeDescriptor(
    SpeechPluginCapabilityConfig config,
    String pluginId,
  ) async {
    final websocketUrl = (config.websocketUrl ?? '').trim();
    if (websocketUrl.isEmpty) {
      throw UnsupportedError(
        'Realtime websocket plugin is missing websocket_url / realtime_websocket_url: $pluginId',
      );
    }
    return <String, dynamic>{
      'websocket_path': Uri.parse(websocketUrl).path,
      'session_defaults': const <String, dynamic>{
        'ready': true,
        'missing_requirements': <dynamic>[],
      },
    };
  }

  String _normalizeRealtimePath(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _defaultDescriptorPath;
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  Uri _webSocketUri(String websocketPath) {
    final manifest = _activeRealtimePluginManifest;
    final plugin = manifest == null
        ? null
        : speechPluginRegistry.selectedPluginForCapability(
            SpeechPluginCapability.realtimeAsr,
          );
    final resolvedConfig =
        manifest == null ? null : _resolvedRealtimePluginConfig(manifest);
    if (resolvedConfig?.transport == SpeechPluginTransport.realtimeWebsocket) {
      final websocketUrl = (resolvedConfig?.websocketUrl ?? '').trim();
      if (websocketUrl.isNotEmpty) {
        return Uri.parse(websocketUrl);
      }
    }
    final baseUrl = switch (plugin?.manifest.transport) {
      SpeechPluginTransport.bridgeOpenAiCompatible =>
        resolvedConfig?.baseUrl.trim().isNotEmpty == true
            ? resolvedConfig!.baseUrl.trim()
            : _client.baseUrl,
      _ => _client.baseUrl,
    };
    final baseUri = Uri.parse(baseUrl);
    return baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: websocketPath,
    );
  }

  Map<String, dynamic> _headers() {
    final settings = appSettingsController.settings;
    final manifest = _activeRealtimePluginManifest;
    final realtimeConfig =
        manifest == null ? null : _resolvedRealtimePluginConfig(manifest);
    if (realtimeConfig?.transport == SpeechPluginTransport.realtimeWebsocket) {
      final headers = <String, dynamic>{};
      if (_usesVolcengineSaucProtocol && manifest != null) {
        final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(
          manifest,
        );
        if (apiKey.isNotEmpty) {
          headers['X-Api-Key'] = apiKey;
        }
        final resourceId = _volcengineSaucResourceId(manifest, realtimeConfig);
        if (resourceId.isNotEmpty) {
          headers['X-Api-Resource-Id'] = resourceId;
        }
        final requestId = _uuidV4();
        headers['X-Api-Connect-Id'] = requestId;
        headers['X-Api-Request-Id'] = requestId;
        headers['X-Api-Sequence'] = '-1';
        return headers;
      }
      final headerName = (realtimeConfig?.authHeader ?? '').trim();
      final apiKey = manifest == null
          ? ''
          : speechPluginRegistry.effectiveApiKeyForManifest(manifest);
      if (headerName.isNotEmpty && apiKey.isNotEmpty) {
        final scheme = (realtimeConfig?.authScheme ?? '').trim();
        headers[headerName] = scheme.isEmpty ? apiKey : '$scheme $apiKey';
      }
      return headers;
    }
    final headers = <String, dynamic>{
      'X-Omni-Code-Client-Id': settings.clientId,
    };
    if (settings.bridgeToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.bridgeToken.trim()}';
    }
    return headers;
  }

  String _volcengineSaucResourceId(
    SpeechPluginManifest manifest,
    SpeechPluginCapabilityConfig? config,
  ) {
    final overrides =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    return (overrides[SpeechPluginSettingFieldKey.resourceId.id] ??
            config?.eventMap[SpeechPluginSettingFieldKey.resourceId.id] ??
            '')
        .trim();
  }

  String _volcengineSaucModelName() {
    final manifest = _activeRealtimePluginManifest;
    if (manifest == null) {
      return 'bigmodel';
    }
    final overrides =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final configured = overrides[SpeechPluginSettingFieldKey.model.id]?.trim();
    return configured?.isNotEmpty == true ? configured! : 'bigmodel';
  }

  void _handleCustomRealtimePluginMessage(
    Map<String, dynamic> decoded, {
    required SpeechPluginManifest manifest,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
  }) {
    final config = _resolvedRealtimePluginConfig(manifest);
    if (config == null) {
      return;
    }
    final eventField = config.eventMap['field'] ?? 'type';
    final type = decoded[eventField]?.toString().trim() ?? '';
    if (type.isEmpty) {
      return;
    }

    final speechStartedType =
        config.eventMap['speech_started'] ?? 'speech_started';
    final partialType = config.eventMap['partial'] ?? 'partial';
    final finalType = config.eventMap['final'] ?? 'final';
    final wakeWordType = config.eventMap['wake_word'] ?? 'wake_word_detected';
    final textField = config.textFieldMap['text'] ?? 'text';
    final keywordField = config.textFieldMap['keyword'] ?? 'keyword';

    if (type == speechStartedType) {
      onSpeechStarted?.call();
      return;
    }
    if (type == wakeWordType) {
      final keyword = decoded[keywordField]?.toString().trim() ?? '';
      if (keyword.isNotEmpty) {
        onWakeWordDetected?.call(keyword);
      }
      return;
    }
    if (type == partialType || type == finalType) {
      final text = decoded[textField]?.toString().trim() ?? '';
      if (text.isEmpty) {
        return;
      }
      onUtterance(
        BridgeRealtimeAsrUtterance(
          text: text,
          isFinal: type == finalType,
        ),
      );
    }
  }

  SpeechPluginCapabilityConfig? _resolvedRealtimePluginConfig(
    SpeechPluginManifest manifest,
  ) {
    final base = manifest.configFor(SpeechPluginCapability.realtimeAsr);
    if (base == null) {
      return null;
    }
    final overrides =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final resolved = base.copyWith(
      model: overrides[SpeechPluginSettingFieldKey.model.id] ?? base.model,
      baseUrl:
          overrides[SpeechPluginSettingFieldKey.baseUrl.id] ?? base.baseUrl,
      path: overrides[SpeechPluginSettingFieldKey.path.id] ?? base.path,
      websocketUrl: overrides[SpeechPluginSettingFieldKey.websocketUrl.id] ??
          base.websocketUrl,
      authHeader: overrides[SpeechPluginSettingFieldKey.authHeader.id] ??
          base.authHeader,
      authScheme: overrides[SpeechPluginSettingFieldKey.authScheme.id] ??
          base.authScheme,
    );

    for (final field in manifest.settingFieldsForCapability(
      SpeechPluginCapability.realtimeAsr,
    )) {
      final value = switch (field.key) {
        SpeechPluginSettingFieldKey.model => resolved.model.trim(),
        SpeechPluginSettingFieldKey.baseUrl => resolved.baseUrl.trim(),
        SpeechPluginSettingFieldKey.path => resolved.path?.trim() ?? '',
        SpeechPluginSettingFieldKey.websocketUrl =>
          resolved.websocketUrl?.trim() ?? '',
        SpeechPluginSettingFieldKey.resourceId =>
          (overrides[field.key.id] ?? resolved.eventMap[field.key.id] ?? '')
              .trim(),
        SpeechPluginSettingFieldKey.authHeader =>
          resolved.authHeader?.trim() ?? '',
        SpeechPluginSettingFieldKey.authScheme =>
          resolved.authScheme?.trim() ?? '',
      };
      if (field.required && value.isEmpty) {
        throw Exception('Plugin setting required: ${field.label}');
      }
    }

    return resolved;
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

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
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
