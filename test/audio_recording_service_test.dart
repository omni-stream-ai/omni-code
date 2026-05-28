import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/audio_recording_service.dart';
import 'package:record/record.dart';

void main() {
  group('AudioRecordingService configs', () {
    test('enables speech enhancement for recorded transcription', () {
      const config = AudioRecordingService.speechRecordConfig;

      expect(config.encoder, AudioEncoder.wav);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.autoGain, isTrue);
      expect(config.echoCancel, isTrue);
      expect(config.noiseSuppress, isTrue);
      expect(
        config.androidConfig.audioSource,
        AndroidAudioSource.voiceCommunication,
      );
      expect(
        config.androidConfig.audioManagerMode,
        AudioManagerMode.modeInCommunication,
      );
    });

    test('enables speech enhancement for realtime call audio', () {
      const config = AudioRecordingService.speechStreamConfig;

      expect(config.encoder, AudioEncoder.pcm16bits);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.autoGain, isTrue);
      expect(config.echoCancel, isTrue);
      expect(config.noiseSuppress, isTrue);
      expect(
        config.androidConfig.audioSource,
        AndroidAudioSource.voiceCommunication,
      );
      expect(
        config.androidConfig.audioManagerMode,
        AudioManagerMode.modeInCommunication,
      );
    });
  });
}
