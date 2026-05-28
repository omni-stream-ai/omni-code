import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../bridge_client.dart';
import '../l10n/current_l10n.dart';
import '../settings/app_settings.dart';

class CloudSpeechService {
  CloudSpeechService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<String> transcribeAudio(File audioFile) async {
    final settings = appSettingsController.settings;
    if (settings.asrProvider == AsrProvider.system) {
      throw StateError(
        'System ASR should be handled by SpeechInputService, not CloudSpeechService.',
      );
    }
    if (settings.asrProvider == AsrProvider.bridgeLocal) {
      return BridgeClient(httpClient: _httpClient).transcribeAudio(audioFile);
    }
    if (settings.asrProvider == AsrProvider.whisper) {
      return _transcribeWithWhisper(
        audioFile,
        apiKey: settings.whisperApiKey,
        baseUrl: settings.whisperBaseUrl,
      );
    }
    throw StateError('Unsupported cloud ASR provider: ${settings.asrProvider}');
  }

  Future<SynthesizedSpeech> synthesizeSpeech(String text) async {
    final settings = appSettingsController.settings;
    if (settings.ttsProvider == TtsProvider.bridgeLocal) {
      final sanitizedText = _sanitizeBridgeLocalTtsInput(text);
      if (sanitizedText.isEmpty) {
        throw Exception(
          currentL10n().ttsFailed('Text contains no speakable characters.'),
        );
      }
      return BridgeClient(httpClient: _httpClient).synthesizeSpeech(
        sanitizedText,
        stream: settings.bridgeLocalTtsStreaming,
      );
    }
    throw StateError('Unsupported cloud TTS provider: ${settings.ttsProvider}');
  }

  Future<String> _transcribeWithWhisper(
    File audioFile, {
    required String apiKey,
    required String baseUrl,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception(currentL10n().whisperApiKeyRequired);
    }
    final normalizedBase = _normalizeBaseUrl(baseUrl);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$normalizedBase/audio/transcriptions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-1';
    request.files
        .add(await http.MultipartFile.fromPath('file', audioFile.path));

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        currentL10n().whisperAsrRequestFailed(response.statusCode, body),
      );
    }
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final text = payload['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception(currentL10n().whisperAsrMissingText);
    }
    return text;
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    final value = trimmed.isEmpty ? 'https://api.openai.com/v1' : trimmed;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _sanitizeBridgeLocalTtsInput(String value) {
    final buffer = StringBuffer();
    var previousWasWhitespace = false;

    for (final rune in value.runes) {
      if (_isEmojiLikeRune(rune)) {
        continue;
      }
      final character = String.fromCharCode(rune);
      if (character.trim().isEmpty) {
        if (!previousWasWhitespace && buffer.isNotEmpty) {
          buffer.write(' ');
          previousWasWhitespace = true;
        }
        continue;
      }
      buffer.write(character);
      previousWasWhitespace = false;
    }

    return buffer.toString().trim();
  }

  bool _isEmojiLikeRune(int rune) {
    return rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x200D ||
        rune == 0x203C ||
        rune == 0x2049 ||
        rune == 0x2122 ||
        rune == 0x2139 ||
        (rune >= 0x2194 && rune <= 0x21AA) ||
        (rune >= 0x231A && rune <= 0x231B) ||
        rune == 0x2328 ||
        rune == 0x23CF ||
        (rune >= 0x23E9 && rune <= 0x23F3) ||
        (rune >= 0x23F8 && rune <= 0x23FA) ||
        rune == 0x24C2 ||
        (rune >= 0x25AA && rune <= 0x25AB) ||
        rune == 0x25B6 ||
        rune == 0x25C0 ||
        (rune >= 0x25FB && rune <= 0x25FE) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2934 && rune <= 0x2935) ||
        (rune >= 0x2B05 && rune <= 0x2B55) ||
        rune == 0x3030 ||
        rune == 0x303D ||
        rune == 0x3297 ||
        rune == 0x3299 ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0x1F000 && rune <= 0x1FAFF);
  }
}

final cloudSpeechService = CloudSpeechService();
