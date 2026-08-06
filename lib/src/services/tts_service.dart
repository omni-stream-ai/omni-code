import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cloud_speech_service.dart';
import '../plugins/speech_plugin_models.dart';
import '../plugins/speech_plugin_registry.dart';
import '../settings/app_settings.dart';

const int _wavHeaderLength = 44;

@visibleForTesting
bool shouldStopFlutterTts({
  required bool isWeb,
  required bool isLinux,
}) =>
    isWeb || !isLinux;

class TtsService {
  TtsService({
    FlutterTts? flutterTts,
    CloudSpeechService? speechService,
  })  : _flutterTts = flutterTts ?? FlutterTts(),
        _speechService = speechService ?? cloudSpeechService;

  final FlutterTts _flutterTts;
  final CloudSpeechService _speechService;
  StreamSubscription<void>? _finishedSubscription;
  AudioSource? _loadedSource;
  SoundHandle? _activeHandle;
  Process? _streamingPlaybackProcess;
  http.Client? _streamingPlaybackClient;
  bool _streamingPlaybackStopping = false;
  bool _systemTtsReady = false;
  bool _systemTtsUnavailable = false;
  bool _linuxTtsEngineDetected = false;
  int? _linuxTtsRunId;
  Process? _linuxTtsProcess;
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

    await _finishedSubscription?.cancel();
    _finishedSubscription = null;
    await _configurePlaybackContext();
    final ttsPlugin = speechPluginRegistry.selectedPluginForCapability(
      SpeechPluginCapability.tts,
    );
    final usesSystemTts = ttsPlugin == null &&
        appSettingsController.settings.ttsProvider == TtsProvider.system;

    if (!usesSystemTts) {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
      return;
    }

    if (!kIsWeb && Platform.isLinux) {
      _linuxTtsEngineDetected =
          await _hasExecutable('spd-say') || await _hasExecutable('espeak-ng');
      _systemTtsReady = _linuxTtsEngineDetected;
      _systemTtsUnavailable = !_linuxTtsEngineDetected;
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
      final ttsPlugin = speechPluginRegistry.selectedPluginForCapability(
        SpeechPluginCapability.tts,
      );
      final provider = appSettingsController.settings.ttsProvider;
      if (ttsPlugin == null && provider == TtsProvider.system) {
        if (_systemTtsUnavailable) {
          throw Exception(
            !kIsWeb && Platform.isLinux
                ? 'Linux system TTS requires speech-dispatcher (spd-say) '
                    'or espeak-ng. Install one and retry, or switch to Omni '
                    'Bridge Local TTS in Settings.'
                : 'System TTS is unavailable on this device. Please switch '
                    'to Omni Bridge Local TTS in Settings.',
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
        await _playUrl(speech.streamUrl!);
        return;
      }
      final filePath = await _writeAudioFile(speech.bytes);
      _currentAudioPath = filePath;
      await _playFile(filePath);
    } catch (error) {
      _onError?.call(error.toString());
      rethrow;
    }
  }

  Future<void> stop({bool notifyCancel = true}) async {
    _linuxTtsRunId = (_linuxTtsRunId ?? 0) + 1;
    final linuxTtsProcess = _linuxTtsProcess;
    _linuxTtsProcess = null;
    linuxTtsProcess?.kill();
    if (_systemTtsReady &&
        shouldStopFlutterTts(
          isWeb: kIsWeb,
          isLinux: !kIsWeb && Platform.isLinux,
        )) {
      try {
        await _flutterTts.stop();
      } catch (_) {
        _systemTtsReady = false;
        _systemTtsUnavailable = true;
      }
    }
    await _stopPlayback();
    await _stopStreamingPlaybackProcess();
    await _cleanupAudioFile();
    if (notifyCancel) {
      _onCancel?.call();
    }
  }

  Future<void> _stopPlayback() async {
    await _finishedSubscription?.cancel();
    _finishedSubscription = null;
    final handle = _activeHandle;
    _activeHandle = null;
    if (handle != null && SoLoud.instance.isInitialized) {
      try {
        await SoLoud.instance.stop(handle);
      } catch (_) {
        // The voice may already have ended on its own.
      }
    }
    final source = _loadedSource;
    _loadedSource = null;
    if (source != null && SoLoud.instance.isInitialized) {
      try {
        await SoLoud.instance.disposeSource(source);
      } catch (_) {
        // Best-effort source cleanup.
      }
    }
  }

  Future<void> _playFile(String filePath) async {
    final source = await SoLoud.instance.loadFile(filePath);
    await _playSource(source);
  }

  Future<void> _playUrl(String url) async {
    final source = await SoLoud.instance.loadUrl(url);
    await _playSource(source);
  }

  Future<void> _playSource(AudioSource source) async {
    await _finishedSubscription?.cancel();
    _finishedSubscription = source.allInstancesFinished.listen((_) {
      _cleanupAudioFile();
      _onComplete?.call();
    });
    final previous = _loadedSource;
    _loadedSource = source;
    if (previous != null && previous != source) {
      try {
        await SoLoud.instance.disposeSource(previous);
      } catch (_) {
        // Best-effort source cleanup.
      }
    }
    final handle = SoLoud.instance.play(source);
    _activeHandle = handle;
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
    if (!kIsWeb && Platform.isLinux) {
      await _speakWithLinuxSystemTts(text);
      return;
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

  Future<void> _speakWithLinuxSystemTts(String text) async {
    final runId = (_linuxTtsRunId ?? 0) + 1;
    _linuxTtsRunId = runId;
    final hasChinese = _containsCjk(text);
    final useEspeak = hasChinese && await _hasExecutable('espeak-ng');
    final isSpeechDispatcher = !useEspeak && await _hasExecutable('spd-say');
    try {
      _onStart?.call();
      final process = useEspeak
          ? await Process.start(
              'espeak-ng',
              ['-v', 'zh', text],
            )
          : isSpeechDispatcher
              ? await Process.start('spd-say', ['-w', text])
              : await Process.start(
                  'espeak-ng',
                  [text],
                );
      _linuxTtsProcess = process;
      _drainPlaybackProcessOutput(process);
      final exitCode = await process.exitCode;
      if (_linuxTtsRunId != runId) {
        return;
      }
      if (_linuxTtsProcess == process) {
        _linuxTtsProcess = null;
      }
      if (exitCode != 0) {
        throw Exception('Linux system TTS failed (exit code $exitCode)');
      }
      _onComplete?.call();
    } on Object {
      if (_linuxTtsRunId == runId) {
        final process = _linuxTtsProcess;
        _linuxTtsProcess = null;
        process?.kill();
      }
      rethrow;
    }
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

  bool _containsCjk(String text) {
    for (final codeUnit in text.runes) {
      if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF ||
          codeUnit >= 0x3400 && codeUnit <= 0x4DBF ||
          codeUnit >= 0xF900 && codeUnit <= 0xFAFF) {
        return true;
      }
    }
    return false;
  }

  Future<void> _configurePlaybackContext() async {
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
