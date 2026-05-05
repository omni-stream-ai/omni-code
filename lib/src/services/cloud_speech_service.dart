import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../bridge_client.dart';
import '../l10n/current_l10n.dart';
import '../settings/app_settings.dart';

class CloudSpeechService {
  CloudSpeechService({
    http.Client? httpClient,
    BridgeClient? bridge,
  })  : _httpClient = httpClient ?? http.Client(),
        _bridge = bridge ?? bridgeClient;

  final http.Client _httpClient;
  final BridgeClient _bridge;

  Future<String> transcribeAudio(File audioFile) async {
    final settings = appSettingsController.settings;
    switch (settings.asrProvider) {
      case AsrProvider.bridge:
        return _bridge.transcribeAudio(audioFile);
      case AsrProvider.zhipu:
        return _transcribeWithZhipu(audioFile, settings.zhipuApiKey);
      case AsrProvider.whisper:
        return _transcribeWithWhisper(
          audioFile,
          apiKey: settings.whisperApiKey,
          baseUrl: settings.whisperBaseUrl,
        );
    }
  }

  Future<SynthesizedSpeech> synthesizeSpeech(String text) async {
    final settings = appSettingsController.settings;
    switch (settings.ttsProvider) {
      case TtsProvider.bridge:
        return _bridge.synthesizeSpeech(text);
      case TtsProvider.zhipu:
        return _synthesizeWithZhipu(text, settings.zhipuApiKey);
    }
  }

  Future<String> _transcribeWithZhipu(File audioFile, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw Exception(currentL10n().zhipuApiKeyRequired);
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://open.bigmodel.cn/api/paas/v4/audio/transcriptions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'glm-asr-2512';
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        currentL10n().zhipuAsrRequestFailed(response.statusCode, body),
      );
    }
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final text = payload['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception(currentL10n().zhipuAsrMissingText);
    }
    return text;
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
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));

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

  Future<SynthesizedSpeech> _synthesizeWithZhipu(String text, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw Exception(currentL10n().zhipuApiKeyRequired);
    }
    final response = await _httpClient.post(
      Uri.parse('https://open.bigmodel.cn/api/paas/v4/audio/speech'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'glm-tts',
        'input': text,
        'voice': 'female',
        'speed': 1.0,
        'volume': 1.0,
        'response_format': 'wav',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        currentL10n().zhipuTtsRequestFailed(
          response.statusCode,
          response.body,
        ),
      );
    }

    return SynthesizedSpeech(
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'audio/wav',
    );
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    final value = trimmed.isEmpty ? 'https://api.openai.com/v1' : trimmed;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}

final cloudSpeechService = CloudSpeechService();
