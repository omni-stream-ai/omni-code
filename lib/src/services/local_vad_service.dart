import 'dart:async';
import 'dart:typed_data';
import 'local_vad_types.dart';
import 'sherpa_local_vad_backend_io.dart'
    if (dart.library.html) 'sherpa_local_vad_backend_stub.dart';
export 'local_vad_types.dart';
export 'sherpa_local_vad_backend_io.dart'
    if (dart.library.html) 'sherpa_local_vad_backend_stub.dart';

class LocalVadService {
  LocalVadService({
    Future<LocalVadBackend?> Function()? backendFactory,
  }) : _backendFactory = backendFactory;

  final Future<LocalVadBackend?> Function()? _backendFactory;

  StreamSubscription<Uint8List>? _subscription;
  LocalVadBackend? _backend;
  bool _listening = false;
  bool _speechActive = false;
  int _startGeneration = 0;

  bool get isListening => _listening;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function() onSpeechStarted,
    double minSilenceDuration = 0.5,
    void Function(LocalVadSpeechSegment segment)? onSpeechEnded,
    void Function(String error)? onError,
  }) async {
    if (_listening) {
      return;
    }
    final startGeneration = ++_startGeneration;
    final backend = await (_backendFactory?.call() ??
        SherpaLocalVadBackend.create(
          minSilenceDuration: minSilenceDuration,
        ));
    if (backend == null || startGeneration != _startGeneration) {
      backend?.dispose();
      return;
    }
    _backend = backend;
    _listening = true;
    _speechActive = false;
    _subscription = audioStream.listen(
      (chunk) {
        if (!_listening) {
          return;
        }
        try {
          final samples = _pcm16LittleEndianToFloat32(chunk);
          backend.acceptWaveform(samples);
          final detected = backend.detected;
          if (detected && !_speechActive) {
            _speechActive = true;
            onSpeechStarted();
          }
          for (final segment in backend.drainSegments()) {
            _speechActive = backend.detected;
            onSpeechEnded?.call(segment);
          }
          if (!detected && _speechActive) {
            _speechActive = false;
          }
        } catch (error) {
          onError?.call('$error');
        }
      },
      onDone: () {
        _listening = false;
      },
      onError: (Object error) {
        _listening = false;
        onError?.call('$error');
      },
      cancelOnError: false,
    );
  }

  Future<void> cancel() async {
    _startGeneration += 1;
    final subscription = _subscription;
    _subscription = null;
    _listening = false;
    _speechActive = false;
    unawaited(subscription?.cancel());
    _backend?.dispose();
    _backend = null;
  }

  static Float32List _pcm16LittleEndianToFloat32(Uint8List chunk) {
    final samples = Float32List(chunk.length ~/ 2);
    final data = ByteData.sublistView(chunk);
    for (var i = 0; i < samples.length; i += 1) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }
}
