import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_speech_service.dart';

class TtsService {
  TtsService({
    AudioPlayer? player,
    CloudSpeechService? speechService,
  })  : _player = player ?? AudioPlayer(),
        _speechService = speechService ?? cloudSpeechService;

  final AudioPlayer _player;
  final CloudSpeechService _speechService;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  String? _currentAudioPath;
  void Function()? _onStart;
  void Function()? _onComplete;
  void Function()? _onCancel;
  void Function(String message)? _onError;

  Future<void> initialize({
    void Function()? onStart,
    void Function()? onComplete,
    void Function()? onCancel,
    void Function(String message)? onError,
  }) async {
    _onStart = onStart;
    _onComplete = onComplete;
    _onCancel = onCancel;
    _onError = onError;

    await _playerStateSubscription?.cancel();
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        _cleanupAudioFile();
        _onComplete?.call();
      }
    });
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    try {
      await stop(notifyCancel: false);
      final speech = await _speechService.synthesizeSpeech(text);
      final filePath = await _writeAudioFile(speech.bytes);
      _currentAudioPath = filePath;
      _onStart?.call();
      await _player.play(DeviceFileSource(filePath));
    } catch (error) {
      _onError?.call(error.toString());
      rethrow;
    }
  }

  Future<void> stop({bool notifyCancel = true}) async {
    await _player.stop();
    await _cleanupAudioFile();
    if (notifyCancel) {
      _onCancel?.call();
    }
  }

  Future<String> _writeAudioFile(List<int> bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/omni-code-tts-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _cleanupAudioFile() async {
    final path = _currentAudioPath;
    _currentAudioPath = null;
    if (path == null) {
      return;
    }
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup for temporary TTS audio.
    }
  }
}
