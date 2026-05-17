import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cloud_speech_service.dart';
import '../settings/app_settings.dart';

const int _wavHeaderLength = 44;

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
  Process? _streamingPlaybackProcess;
  http.Client? _streamingPlaybackClient;
  bool _streamingPlaybackStopping = false;
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

    await _configurePlaybackContext();
    if (appSettingsController.settings.ttsProvider != TtsProvider.system) {
      return;
    }

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
      _streamingPlaybackStopping = false;
      final provider = appSettingsController.settings.ttsProvider;
      if (provider == TtsProvider.system) {
        if (_systemTtsUnavailable) {
          throw Exception(
            'System TTS is unavailable on this device. '
            'Please switch to Omni Bridge Local TTS in Settings.',
          );
        }
        await _speakWithSystemTts(text);
        return;
      }
      final speech = await _speechService.synthesizeSpeech(text);
      _onStart?.call();
      if (speech.isStreaming) {
        if (!kIsWeb && Platform.isLinux) {
          await _playStreamingWavOnLinux(speech.streamUrl!);
          return;
        }
        await _player.play(
          UrlSource(
            speech.streamUrl!,
            mimeType: speech.contentType,
          ),
        );
        return;
      }
      final filePath = await _writeAudioFile(speech.bytes);
      _currentAudioPath = filePath;
      await _player.play(
        DeviceFileSource(
          filePath,
          mimeType: speech.contentType,
        ),
      );
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
    await _stopStreamingPlaybackProcess();
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
        'Please switch to Omni Bridge Local TTS in Settings.',
      );
    }
    final locale = _preferredSystemLocale();
    if (locale != null) {
      await _flutterTts.setLanguage(locale);
    }
    if (!kIsWeb && Platform.isAndroid) {
      await _flutterTts.speak(text, focus: true);
      return;
    }
    await _flutterTts.speak(text);
  }

  Future<void> _playStreamingWavOnLinux(String streamUrl) async {
    final client = http.Client();
    _streamingPlaybackClient = client;
    Process? process;
    try {
      final request = http.Request('GET', Uri.parse(streamUrl));
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('TTS stream failed (${response.statusCode})');
      }

      final headerBuffer = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (process == null) {
          headerBuffer.add(chunk);
          final buffered = headerBuffer.toBytes();
          if (buffered.length < _wavHeaderLength) {
            continue;
          }
          final header = Uint8List.sublistView(buffered, 0, _wavHeaderLength);
          final format = _parseWavFormat(header);
          process = await _startLinuxPcmPlayback(format);
          _streamingPlaybackProcess = process;
          final pcmOffset = _wavHeaderLength;
          if (buffered.length > pcmOffset) {
            process.stdin.add(
              Uint8List.sublistView(buffered, pcmOffset),
            );
            await process.stdin.flush();
          }
          continue;
        }

        final currentProcess = _streamingPlaybackProcess;
        if (currentProcess == null || currentProcess != process) {
          break;
        }

        process.stdin.add(chunk);
        await process.stdin.flush();
      }
      if (process == null) {
        throw Exception('TTS stream ended before WAV audio data was available');
      }
      await process.stdin.close();
      final exitCode = await process.exitCode;
      if (_streamingPlaybackProcess == process) {
        _streamingPlaybackProcess = null;
      }
      if (_streamingPlaybackStopping) {
        return;
      }
      if (exitCode != 0) {
        throw Exception('TTS playback exited with code $exitCode');
      }
      _onComplete?.call();
    } on Object {
      if (_streamingPlaybackStopping) {
        return;
      }
      if (_streamingPlaybackProcess == process) {
        _streamingPlaybackProcess = null;
      }
      process?.kill();
      rethrow;
    } finally {
      if (_streamingPlaybackClient == client) {
        _streamingPlaybackClient = null;
      }
      client.close();
      if (_streamingPlaybackProcess == process) {
        _streamingPlaybackProcess = null;
      }
      if (_streamingPlaybackProcess == null) {
        _streamingPlaybackStopping = false;
      }
    }
  }

  Future<Process> _startLinuxPcmPlayback(_WavStreamFormat format) async {
    if (await _hasExecutable('pw-play')) {
      final process = await Process.start(
        'pw-play',
        [
          '--raw',
          '--rate',
          '${format.sampleRate}',
          '--channels',
          '${format.channels}',
          '--format',
          's16',
          '--latency',
          '50ms',
          '-',
        ],
      );
      _drainPlaybackProcessOutput(process);
      return process;
    }

    final process = await Process.start(
      'gst-launch-1.0',
      [
        '-q',
        'fdsrc',
        'blocksize=4096',
        'do-timestamp=true',
        '!',
        'audio/x-raw,format=S16LE,layout=interleaved,rate=${format.sampleRate},channels=${format.channels}',
        '!',
        'queue',
        'max-size-buffers=8',
        'max-size-bytes=32768',
        'max-size-time=0',
        '!',
        'audioconvert',
        '!',
        'audioresample',
        '!',
        'autoaudiosink',
        'sync=false',
      ],
    );
    _drainPlaybackProcessOutput(process);
    return process;
  }

  Future<bool> _hasExecutable(String executable) async {
    try {
      final result = await Process.run('which', [executable]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void _drainPlaybackProcessOutput(Process process) {
    unawaited(process.stderr.drain<void>());
    unawaited(process.stdout.drain<void>());
  }

  _WavStreamFormat _parseWavFormat(Uint8List header) {
    if (header.length < _wavHeaderLength ||
        String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(header.sublist(8, 12)) != 'WAVE' ||
        String.fromCharCodes(header.sublist(12, 16)) != 'fmt ' ||
        String.fromCharCodes(header.sublist(36, 40)) != 'data') {
      throw Exception('Unsupported TTS WAV stream header');
    }
    final data = ByteData.sublistView(header);
    final audioFormat = data.getUint16(20, Endian.little);
    final channels = data.getUint16(22, Endian.little);
    final sampleRate = data.getUint32(24, Endian.little);
    final bitsPerSample = data.getUint16(34, Endian.little);
    if (audioFormat != 1 || bitsPerSample != 16 || channels == 0) {
      throw Exception(
        'Unsupported TTS WAV stream format: '
        'format=$audioFormat channels=$channels bits=$bitsPerSample',
      );
    }
    return _WavStreamFormat(sampleRate: sampleRate, channels: channels);
  }

  Future<void> _stopStreamingPlaybackProcess() async {
    _streamingPlaybackStopping = true;
    _streamingPlaybackClient?.close();
    _streamingPlaybackClient = null;
    final process = _streamingPlaybackProcess;
    _streamingPlaybackProcess = null;
    if (process == null) {
      _streamingPlaybackStopping = false;
      return;
    }
    try {
      await process.stdin.close();
    } catch (_) {
      // Process stdin may already be closed.
    }
    process.kill();
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

  Future<void> _configurePlaybackContext() async {
    try {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            stayAwake: true,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
          ),
        ),
      );
    } catch (_) {
      // Best-effort audio session tuning for lock-screen playback.
    }

    if (kIsWeb) {
      return;
    }

    if (Platform.isIOS) {
      try {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const <IosTextToSpeechAudioCategoryOptions>[],
        );
      } catch (_) {
        // Best-effort iOS session tuning for system TTS playback.
      }
      return;
    }

    if (Platform.isAndroid) {
      try {
        await _flutterTts.setAudioAttributesForNavigation();
      } catch (_) {
        // Best-effort Android audio attribute tuning for system TTS playback.
      }
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

class _WavStreamFormat {
  const _WavStreamFormat({
    required this.sampleRate,
    required this.channels,
  });

  final int sampleRate;
  final int channels;
}
