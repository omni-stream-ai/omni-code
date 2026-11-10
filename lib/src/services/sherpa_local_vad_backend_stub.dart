import 'dart:typed_data';
import 'local_vad_types.dart';

/// Browsers use ASR/server speech events; the native Silero FFI backend cannot
/// be loaded there. LocalVadService already handles an unavailable backend.
class SherpaLocalVadBackend implements LocalVadBackend {
  static Future<SherpaLocalVadBackend?> create(
          {String? modelPath,
          int sampleRate = 16000,
          double minSilenceDuration = 0.5,
          double minSpeechDuration = 0.25}) async =>
      null;
  @override
  bool get detected => false;
  @override
  void acceptWaveform(Float32List samples) {}
  @override
  List<LocalVadSpeechSegment> drainSegments() => const [];
  @override
  void reset() {}
  @override
  void dispose() {}
}
