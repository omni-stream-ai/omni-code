import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_speech_service.dart';
import '../settings/app_settings.dart';

class TtsService {
  TtsService({
    AudioPlayer? player,
    FlutterTts? flutterTts,
    CloudSpeechService? speechService,
  })  : _player = player ?? AudioPlayer(),
        _flutterTts = flutterTts ?? FlutterTts(),
        _speechService = speechService ?? cloudSpeechService;

  final AudioPlayer _player;
  final FlutterTts _flutterTts;
  final CloudSpeechService _speechService;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _systemTtsReady = false;
  bool _systemTtsUnavailable = false;
  String? _currentAudioPath;
  void Function()? _onStart;
  void Function()? _onComplete;
  void Function()? _onCancel;
  void Function(String message)? _onError;

  bool get isSystemTtsAvailable => _systemTtsReady && !_systemTtsUnavailable;

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

    try {
      await _flutterTts.awaitSpeakCompletion(true);
      _flutterTts.setStartHandler(() {
        _onStart?.call();
      });
      _flutterTts.setCompletionHandler(() {
        _onComplete?.call();
      });
      _flutterTts.setCancelHandler(() {
        _onCancel?.call();
      });
      _flutterTts.setErrorHandler((message) {
        _onError?.call(message);
      });

      _systemTtsReady = true;
      _systemTtsUnavailable = false;
    } on MissingPluginException catch (_) {
      _systemTtsReady = false;
      _systemTtsUnavailable = true;
    } on PlatformException catch (_) {
      _systemTtsReady = false;
      _systemTtsUnavailable = true;
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    try {
      await stop(notifyCancel: false);
      final provider = appSettingsController.settings.ttsProvider;
      if (provider == TtsProvider.system) {
        if (_systemTtsUnavailable) {
          throw Exception(
            'System TTS is unavailable on this device. '
            'Please switch to Zhipu TTS in Settings, or configure a cloud TTS provider.',
          );
        }
        await _speakWithSystemTts(text);
        return;
      }
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
    if (_systemTtsReady) {
      try {
        await _flutterTts.stop();
      } catch (_) {
        _systemTtsReady = false;
        _systemTtsUnavailable = true;
      }
    }
    await _player.stop();
    await _cleanupAudioFile();
    if (notifyCancel) {
      _onCancel?.call();
    }
  }

  Future<void> _speakWithSystemTts(String text) async {
    if (!_systemTtsReady) {
      await initialize();
    }
    if (!_systemTtsReady) {
      throw Exception(
        'System TTS initialization failed. '
        'Please switch to Zhipu TTS in Settings, or configure a cloud TTS provider.',
      );
    }
    final locale = _preferredSystemLocale();
    if (locale != null) {
      await _flutterTts.setLanguage(locale);
    }
    await _flutterTts.speak(text);
  }

  String? _preferredSystemLocale() {
    if (kIsWeb) {
      return null;
    }
    final locale = Platform.localeName.replaceAll('_', '-').trim();
    if (locale.isEmpty) {
      return null;
    }
    return locale;
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
