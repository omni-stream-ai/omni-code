import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/local_vad_service.dart';

void main() {
  test('local VAD service converts PCM16 chunks and emits activity callbacks',
      () async {
    final backend = _FakeLocalVadBackend()
      ..detectedValue = true
      ..segments.add(
        LocalVadSpeechSegment(
          start: 160,
          samples: Float32List.fromList([0.25, -0.25]),
        ),
      );
    final service = LocalVadService(backendFactory: () async => backend);
    final audio = StreamController<Uint8List>();
    var speechStartedCalls = 0;
    final endedSegments = <LocalVadSpeechSegment>[];

    await service.start(
      audioStream: audio.stream,
      onSpeechStarted: () {
        speechStartedCalls += 1;
      },
      onSpeechEnded: endedSegments.add,
    );
    audio.add(Uint8List.fromList([0, 0, 0, 64, 0, 192]));
    await Future<void>.delayed(Duration.zero);

    expect(service.isListening, isTrue);
    expect(speechStartedCalls, 1);
    expect(backend.acceptedChunks, hasLength(1));
    expect(backend.acceptedChunks.single[0], 0);
    expect(backend.acceptedChunks.single[1], closeTo(0.5, 0.0001));
    expect(backend.acceptedChunks.single[2], closeTo(-0.5, 0.0001));
    expect(endedSegments, hasLength(1));
    expect(endedSegments.single.start, 160);

    await service.cancel();

    expect(service.isListening, isFalse);
    expect(backend.disposed, isTrue);
  });
}

class _FakeLocalVadBackend implements LocalVadBackend {
  bool detectedValue = false;
  bool disposed = false;
  final List<Float32List> acceptedChunks = <Float32List>[];
  final List<LocalVadSpeechSegment> segments = <LocalVadSpeechSegment>[];

  @override
  bool get detected => detectedValue;

  @override
  void acceptWaveform(Float32List samples) {
    acceptedChunks.add(samples);
  }

  @override
  List<LocalVadSpeechSegment> drainSegments() {
    final drained = List<LocalVadSpeechSegment>.of(segments);
    segments.clear();
    return drained;
  }

  @override
  void reset() {}

  @override
  void dispose() {
    disposed = true;
  }
}
