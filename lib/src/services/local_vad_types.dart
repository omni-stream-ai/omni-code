import 'dart:typed_data';

class LocalVadSpeechSegment {
  const LocalVadSpeechSegment({
    required this.start,
    required this.samples,
  });

  final int start;
  final Float32List samples;
}

abstract interface class LocalVadBackend {
  bool get detected;

  void acceptWaveform(Float32List samples);

  List<LocalVadSpeechSegment> drainSegments();

  void reset();

  void dispose();
}
