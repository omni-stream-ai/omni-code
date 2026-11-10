import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'sherpa_onnx_bindings.dart' as sherpa;
import 'local_vad_types.dart';

class SherpaLocalVadBackend implements LocalVadBackend {
  SherpaLocalVadBackend._(this._vad);

  static const _bundledModelAsset = 'assets/speech/silero_vad.onnx';
  static const _modelFileName = 'silero_vad.onnx';

  final Pointer<Void> _vad;
  bool _disposed = false;

  static Future<SherpaLocalVadBackend?> create({
    String? modelPath,
    int sampleRate = 16000,
    double minSilenceDuration = 0.5,
    double minSpeechDuration = 0.25,
  }) async {
    final resolvedModelPath = modelPath ?? await _defaultModelPath();
    if (resolvedModelPath == null) {
      debugPrint('[local-vad] silero VAD model not found');
      return null;
    }
    final config = sherpa.createSileroVadModelConfig(
      modelPath: resolvedModelPath,
      sampleRate: sampleRate,
      minSilenceDuration: minSilenceDuration,
      minSpeechDuration: minSpeechDuration,
    );
    try {
      final vad = sherpa.createVoiceActivityDetector(config, 30.0);
      if (vad == nullptr) {
        debugPrint('[local-vad] failed to create VAD');
        return null;
      }
      return SherpaLocalVadBackend._(vad);
    } finally {
      sherpa.freeVadModelConfig(config);
    }
  }

  static Future<String?> _defaultModelPath() async {
    final bundledModelPath = await _ensureBundledModel();
    if (bundledModelPath != null) {
      return bundledModelPath;
    }

    final candidates = <String>[];
    try {
      final dir = await getApplicationDocumentsDirectory();
      candidates.add('${dir.path}/$_modelFileName');
      candidates.add('${dir.path}/sherpa-onnx-vad/$_modelFileName');
    } catch (_) {}
    candidates.addAll(const [
      _bundledModelAsset,
      'models/silero_vad.onnx',
    ]);
    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  static Future<String?> _ensureBundledModel() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final modelDirectory = Directory('${directory.path}/speech');
      await modelDirectory.create(recursive: true);
      final modelFile = File('${modelDirectory.path}/$_modelFileName');
      if (await modelFile.exists() && await modelFile.length() > 0) {
        return modelFile.path;
      }

      final assetBytes = await rootBundle.load(_bundledModelAsset);
      final bytes = assetBytes.buffer.asUint8List(
        assetBytes.offsetInBytes,
        assetBytes.lengthInBytes,
      );
      await modelFile.writeAsBytes(bytes, flush: true);
      return modelFile.path;
    } catch (error) {
      debugPrint('[local-vad] failed to install bundled VAD model: $error');
      return null;
    }
  }

  @override
  bool get detected {
    if (_disposed) {
      return false;
    }
    return sherpa.voiceActivityDetectorDetected(_vad) != 0;
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_disposed || samples.isEmpty) {
      return;
    }
    final ptr = calloc<Float>(samples.length);
    try {
      ptr.asTypedList(samples.length).setAll(0, samples);
      sherpa.voiceActivityDetectorAcceptWaveform(_vad, ptr, samples.length);
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  List<LocalVadSpeechSegment> drainSegments() {
    if (_disposed) {
      return const [];
    }
    final segments = <LocalVadSpeechSegment>[];
    while (sherpa.voiceActivityDetectorEmpty(_vad) == 0) {
      final segment = sherpa.voiceActivityDetectorFront(_vad);
      if (segment == nullptr) {
        break;
      }
      try {
        final count = segment.ref.n;
        segments.add(
          LocalVadSpeechSegment(
            start: segment.ref.start,
            samples: Float32List.fromList(
              segment.ref.samples.asTypedList(count),
            ),
          ),
        );
      } finally {
        sherpa.destroySpeechSegment(segment);
        sherpa.voiceActivityDetectorPop(_vad);
      }
    }
    return segments;
  }

  @override
  void reset() {
    if (!_disposed) {
      sherpa.voiceActivityDetectorReset(_vad);
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    sherpa.destroyVoiceActivityDetector(_vad);
  }
}
