import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:typed_data';

class AudioRecordingService {
  AudioRecordingService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  Future<String> start() async {
    final directory = await getTemporaryDirectory();
    final filePath =
        '${directory.path}/omni-code-${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: filePath,
    );

    return filePath;
  }

  Future<Stream<Uint8List>> startStream() {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  Future<String?> stop() {
    return _recorder.stop();
  }

  Future<void> cancel() {
    return _recorder.cancel();
  }
}
