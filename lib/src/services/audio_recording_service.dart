import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:typed_data';

class AudioRecordingService {
  AudioRecordingService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  static const speechRecordConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
      audioManagerMode: AudioManagerMode.modeInCommunication,
    ),
  );

  static const speechStreamConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
      audioManagerMode: AudioManagerMode.modeInCommunication,
    ),
  );

  final AudioRecorder _recorder;

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  Future<String> start() async {
    final directory = await getTemporaryDirectory();
    final filePath =
        '${directory.path}/omni-code-${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      speechRecordConfig,
      path: filePath,
    );

    return filePath;
  }

  Future<Stream<Uint8List>> startStream() {
    return _recorder.startStream(
      speechStreamConfig,
    );
  }

  Future<String?> stop() {
    return _recorder.stop();
  }

  Future<void> cancel() {
    return _recorder.cancel();
  }
}
