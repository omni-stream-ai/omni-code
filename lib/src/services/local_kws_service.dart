import 'dart:ffi';
import 'dart:convert';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'kws_wake_word_normalizer.dart';
import 'sherpa_onnx_bindings.dart' as sherpa;

class LocalKwsService {
  LocalKwsService();

  Pointer<Void>? _spotter;
  Pointer<Void>? _stream;
  bool _initialized = false;
  bool _listening = false;
  void Function(String keyword)? _onWakeWordDetected;

  bool get isListening => _listening;
  bool get isInitialized => _initialized;

  Future<void> initialize({
    required String modelDir,
    required List<String> wakeWords,
  }) async {
    if (_initialized) return;

    try {
      final encoderPath =
          '$modelDir/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx';
      final decoderPath =
          '$modelDir/decoder-epoch-13-avg-2-chunk-16-left-64.onnx';
      final joinerPath =
          '$modelDir/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx';
      final tokensPath = '$modelDir/tokens.txt';

      if (!await File(encoderPath).exists()) {
        debugPrint('[local-kws] encoder not found: $encoderPath');
        return;
      }
      if (!await File(decoderPath).exists()) {
        debugPrint('[local-kws] decoder not found: $decoderPath');
        return;
      }
      if (!await File(joinerPath).exists()) {
        debugPrint('[local-kws] joiner not found: $joinerPath');
        return;
      }
      if (!await File(tokensPath).exists()) {
        debugPrint('[local-kws] tokens not found: $tokensPath');
        return;
      }

      final normalizer = KwsWakeWordNormalizer(
        modelTokens: await _readModelTokens(tokensPath),
      );
      final normalizedWakeWords = normalizer.normalizeAll(wakeWords);
      final unsupportedTokens = normalizedWakeWords
          .expand((word) => word.unsupportedTokens)
          .toSet()
          .toList(growable: false);
      if (unsupportedTokens.isNotEmpty) {
        debugPrint(
          '[local-kws] unsupported wake word token(s): '
          '${unsupportedTokens.join(', ')}',
        );
        return;
      }
      final keywords = normalizedWakeWords
          .map((word) => word.normalized)
          .where((word) => word.isNotEmpty)
          .join('\n');
      final config = sherpa.createKeywordSpotterConfig(
        encoderPath: encoderPath,
        decoderPath: decoderPath,
        joinerPath: joinerPath,
        tokensPath: tokensPath,
        keywords: keywords,
        numThreads: 2,
        keywordsScore: 1.0,
        keywordsThreshold: 0.15,
      );

      _spotter = sherpa.createKeywordSpotter(config);
      sherpa.freeKeywordSpotterConfig(config);

      if (_spotter == nullptr) {
        debugPrint('[local-kws] failed to create keyword spotter');
        return;
      }

      _stream = sherpa.createKeywordStream(_spotter!);
      if (_stream == nullptr) {
        debugPrint('[local-kws] failed to create keyword stream');
        sherpa.destroyKeywordSpotter(_spotter!);
        _spotter = null;
        return;
      }

      _initialized = true;
      debugPrint('[local-kws] initialized with wake words: $wakeWords');
    } catch (e) {
      debugPrint('[local-kws] initialization error: $e');
    }
  }

  Future<Set<String>> _readModelTokens(String tokensPath) async {
    final tokens = <String>{};
    final lines = await File(tokensPath).readAsLines();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final separator = trimmed.lastIndexOf(' ');
      if (separator <= 0) {
        continue;
      }
      tokens.add(trimmed.substring(0, separator));
    }
    return tokens;
  }

  Future<void> start({
    required List<String> wakeWords,
    required void Function(String keyword) onWakeWordDetected,
  }) async {
    if (!_initialized) {
      final modelPath = await _getModelPath();
      if (modelPath == null) {
        debugPrint('[local-kws] model not downloaded');
        return;
      }
      await initialize(modelDir: modelPath, wakeWords: wakeWords);
    }
    if (!_initialized) return;

    _onWakeWordDetected = onWakeWordDetected;
    _listening = true;
    debugPrint('[local-kws] started listening');
  }

  void processAudioChunk(Float32List samples) {
    if (!_initialized || !_listening || _spotter == null || _stream == null) {
      return;
    }

    try {
      final ptr = calloc<Float>(samples.length);
      try {
        ptr.asTypedList(samples.length).setAll(0, samples);

        sherpa.acceptWaveform(_stream!, 16000, ptr, samples.length);
      } finally {
        calloc.free(ptr);
      }

      while (sherpa.isStreamReady(_spotter!, _stream!) != 0) {
        sherpa.decodeKeywordStream(_spotter!, _stream!);
      }

      final resultJsonPtr = sherpa.getKeywordResultJson(_spotter!, _stream!);
      if (resultJsonPtr == nullptr) {
        return;
      }

      late final String resultJson;
      try {
        resultJson = _nativeUtf8ToDartString(resultJsonPtr);
      } finally {
        sherpa.freeKeywordResultJson(resultJsonPtr);
      }

      final keyword = _keywordFromResultJson(resultJson);
      if (keyword.isNotEmpty) {
        debugPrint('[local-kws] detected keyword: $keyword');
        _onWakeWordDetected?.call(keyword);
        sherpa.resetStream(_spotter!, _stream!);
      }
    } catch (error) {
      debugPrint('[local-kws] audio processing error: $error');
    }
  }

  String _nativeUtf8ToDartString(Pointer<Utf8> pointer) {
    final bytes = pointer.cast<Uint8>();
    var length = 0;
    while (bytes[length] != 0) {
      length += 1;
    }
    return const Utf8Decoder(allowMalformed: true).convert(
      bytes.asTypedList(length),
    );
  }

  String _keywordFromResultJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded['keyword']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<void> stop() async {
    _listening = false;
    debugPrint('[local-kws] stopped');
  }

  Future<void> cancel() async {
    _listening = false;
    if (_stream != null) {
      sherpa.destroyOnlineStream(_stream!);
      _stream = null;
    }
    if (_spotter != null) {
      sherpa.destroyKeywordSpotter(_spotter!);
      _spotter = null;
    }
    _initialized = false;
    debugPrint('[local-kws] cancelled');
  }

  Future<String?> _getModelPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = '${dir.path}/sherpa-onnx-kws-zipformer-zh-en-3M';
      if (await Directory(modelDir).exists()) {
        return modelDir;
      }
    } catch (e) {
      debugPrint('[local-kws] error getting model path: $e');
    }
    return null;
  }
}
