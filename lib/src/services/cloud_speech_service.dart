import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../bridge_client.dart' show SynthesizedSpeech;
import '../l10n/current_l10n.dart';
import '../l10n/app_locale.dart';
import '../plugins/speech_plugin_models.dart';
import '../plugins/speech_plugin_registry.dart';
import '../settings/app_settings.dart';

class CloudSpeechService {
  CloudSpeechService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<String> transcribeAudio(File audioFile) async {
    final settings = appSettingsController.settings;
    final batchPlugin = speechPluginRegistry.selectedPluginForCapability(
      SpeechPluginCapability.batchAsr,
    );
    if (batchPlugin != null) {
      return _transcribeWithPlugin(audioFile, batchPlugin.manifest);
    }
    if (settings.asrProvider == AsrProvider.system) {
      throw StateError(
        'System ASR should be handled by SpeechInputService, not CloudSpeechService.',
      );
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
    final ttsPlugin = speechPluginRegistry.selectedPluginForCapability(
      SpeechPluginCapability.tts,
    );
    if (ttsPlugin != null) {
      return _synthesizeWithPlugin(text, ttsPlugin.manifest);
    }
    throw StateError('Unsupported cloud TTS provider: ${settings.ttsProvider}');
  }

  Future<String> _transcribeWithPlugin(
    File audioFile,
    SpeechPluginManifest manifest,
  ) async {
    final config = _resolvedPluginConfig(
      manifest,
      SpeechPluginCapability.batchAsr,
    );
    if (config == null) {
      throw StateError(
          'Selected plugin does not support batch ASR: ${manifest.id}');
    }
    final contentType = config.requestContentType.isNotEmpty
        ? config.requestContentType
        : 'multipart/form-data';
    switch (config.resolvedTransport) {
      case SpeechPluginTransport.openAiCompatible:
      case SpeechPluginTransport.bridgeOpenAiCompatible:
        if (contentType == 'application/json') {
          return _transcribeWithJsonPlugin(
            audioFile,
            manifest: manifest,
            config: config,
          );
        }
        if (contentType.startsWith('audio/')) {
          return _transcribeWithBinaryPlugin(
            audioFile,
            manifest: manifest,
            config: config,
          );
        }
        return _transcribeWithOpenAiCompatiblePlugin(
          audioFile,
          manifest: manifest,
          config: config,
        );
      case SpeechPluginTransport.realtimeWebsocket:
        throw StateError(
          'Realtime websocket plugins do not support batch ASR: ${manifest.id}',
        );
      case SpeechPluginTransport.metadataOnly:
        throw StateError(
          'Selected batch ASR plugin is metadata-only: ${manifest.id}',
        );
    }
  }

  Future<SynthesizedSpeech> _synthesizeWithPlugin(
    String text,
    SpeechPluginManifest manifest,
  ) async {
    final config = _resolvedPluginConfig(
      manifest,
      SpeechPluginCapability.tts,
    );
    if (config == null) {
      throw StateError('Selected plugin does not support TTS: ${manifest.id}');
    }
    switch (config.resolvedTransport) {
      case SpeechPluginTransport.openAiCompatible:
      case SpeechPluginTransport.bridgeOpenAiCompatible:
        if (config.requestContentType == 'application/json') {
          return _synthesizeWithJsonPlugin(
            text,
            manifest: manifest,
            config: config,
          );
        }
        return _synthesizeWithOpenAiCompatiblePlugin(
          text,
          manifest: manifest,
          config: config,
        );
      case SpeechPluginTransport.realtimeWebsocket:
        throw StateError(
          'Realtime websocket plugins do not support TTS: ${manifest.id}',
        );
      case SpeechPluginTransport.metadataOnly:
        throw StateError(
            'Selected TTS plugin is metadata-only: ${manifest.id}');
    }
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

  Future<String> _transcribeWithOpenAiCompatiblePlugin(
    File audioFile, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) async {
    final normalizedBase = _normalizeBaseUrl(config.baseUrl);
    final path = _normalizePluginPath(config.path, '/audio/transcriptions');
    final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(manifest);
    final authHeader = config.authHeader?.trim() ?? '';
    final authScheme = config.authScheme?.trim() ?? '';
    final fieldMap = config.requestFieldMap;
    final fileField = fieldMap['file'] ?? 'file';
    final modelField = fieldMap['model'] ?? 'model';
    final responseTextPath =
        config.responseTextPath.isNotEmpty ? config.responseTextPath : 'text';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$normalizedBase$path'),
    );
    if (apiKey.isNotEmpty) {
      if (authHeader.isNotEmpty) {
        request.headers[authHeader] = _authorizationValue(authScheme, apiKey);
      } else {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
    }
    for (final entry in config.extraHeaders.entries) {
      request.headers[entry.key] = _resolveHeaderValue(
        entry.value,
        manifest: manifest,
        config: config,
      );
    }
    final modelValue = config.model.isNotEmpty ? config.model : manifest.id;
    if (modelField.isNotEmpty && modelValue.isNotEmpty) {
      request.fields[modelField] = modelValue;
    }
    request.files
        .add(await http.MultipartFile.fromPath(fileField, audioFile.path));

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body);
    }
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final text = _extractNestedJsonValue(payload, responseTextPath) as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception(
          'Speech plugin ASR response missing text at "$responseTextPath".');
    }
    return text;
  }

  Future<String> _transcribeWithBinaryPlugin(
    File audioFile, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) async {
    final normalizedBase = _normalizeBaseUrl(config.baseUrl);
    final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(manifest);
    final settings =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final language = settings['resource_id'] ?? 'zh-CN';

    final pathVars = {
      'model': config.model.isNotEmpty ? config.model : manifest.id,
      'language': language,
    };
    final submitPath = _resolvePathVars(
      config.path ?? '',
      pathVars,
    );
    final bytes = await audioFile.readAsBytes();

    final headers = <String, String>{
      'Content-Type': config.requestContentType.isNotEmpty
          ? config.requestContentType
          : 'audio/wav',
    };
    if (apiKey.isNotEmpty) {
      final authHeader = config.authHeader?.trim() ?? '';
      if (authHeader.isNotEmpty) {
        headers[authHeader] = _authorizationValue(config.authScheme, apiKey);
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }
    }
    for (final entry in config.extraHeaders.entries) {
      headers[entry.key] = _resolveHeaderValue(
        entry.value,
        manifest: manifest,
        config: config,
      );
    }
    final submitUrl = Uri.parse('$normalizedBase$submitPath');
    final submitResp = await _httpClient.post(
      submitUrl,
      headers: headers,
      body: bytes,
    );
    if (submitResp.statusCode < 200 || submitResp.statusCode >= 300) {
      throw Exception(
        'Submit failed (${submitResp.statusCode}): ${submitResp.body}',
      );
    }
    final submitPayload = jsonDecode(submitResp.body) as Map<String, dynamic>;
    final taskId = submitPayload['id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw Exception('Submit response missing task id: ${submitResp.body}');
    }

    final pollUrlTemplate = config.pollPath?.trim() ?? '';
    if (pollUrlTemplate.isEmpty) {
      throw Exception('Batch ASR requires a poll endpoint.');
    }
    pathVars['task_id'] = taskId;
    final pollUrlStr =
        '$normalizedBase${_resolvePathVars(pollUrlTemplate, pathVars)}';
    const maxAttempts = 120;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final authHeader = config.authHeader?.trim() ?? '';
      final pollHeaders = <String, String>{};
      if (apiKey.isNotEmpty && authHeader.isNotEmpty) {
        final scheme = (config.authScheme?.trim() ?? '').isNotEmpty
            ? '${config.authScheme!.trim()} '
            : '';
        pollHeaders[authHeader] = '$scheme$apiKey';
      }
      final pollResp = await _httpClient.get(
        Uri.parse(pollUrlStr),
        headers: pollHeaders,
      );
      if (pollResp.statusCode < 200 || pollResp.statusCode >= 300) {
        throw Exception(
          'Poll failed (${pollResp.statusCode}): ${pollResp.body}',
        );
      }
      final payload = jsonDecode(pollResp.body) as Map<String, dynamic>;
      final code = payload['code'] as int?;
      if (code == 0) {
        final responseTextPath = config.responseTextPath.isNotEmpty
            ? config.responseTextPath
            : 'utterances.0.text';
        final text = _extractBatchAsrText(payload, responseTextPath);
        if (text == null || text.trim().isEmpty) {
          throw Exception(
            'Batch ASR response missing text at "$responseTextPath": '
            '${jsonEncode(payload)}',
          );
        }
        return text;
      }
      if (code == 1013) {
        throw Exception('No speech detected in the audio.');
      }
      if (code != 2000) {
        final message =
            payload['message'] as String? ?? payload['code'].toString();
        throw Exception('Batch ASR error $code: $message');
      }
    }
    throw Exception('Batch ASR polling timed out.');
  }

  Future<String> _transcribeWithJsonPlugin(
    File audioFile, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) async {
    final normalizedBase = _normalizeBaseUrl(config.baseUrl);
    final submitPath = _normalizePluginPath(config.path, '');
    final pollPath = config.pollPath?.trim() ?? '';
    final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(manifest);

    final bytes = await audioFile.readAsBytes();
    final base64 = base64Encode(bytes);
    final ext = audioFile.path.split('.').lastOrNull ?? 'wav';
    final mime = switch (ext.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'ogg' || 'opus' => 'audio/ogg',
      _ => 'audio/wav',
    };
    final dataUri = 'data:$mime;base64,$base64';

    final body = _buildJsonBody(
      config.requestBody,
      audioDataUri: dataUri,
      audioFormat: ext,
      manifest: manifest,
      config: config,
    );
    final headers = _buildJsonRequestHeaders(manifest, config, apiKey);
    final submitUrl = Uri.parse('$normalizedBase$submitPath');

    final submitResp = await _httpClient.post(
      submitUrl,
      headers: headers,
      body: jsonEncode(body),
    );
    if (submitResp.statusCode < 200 || submitResp.statusCode >= 300) {
      throw Exception(
        'Submit failed (${submitResp.statusCode}): ${submitResp.body}',
      );
    }

    if (pollPath.isEmpty) {
      final payload = jsonDecode(submitResp.body) as Map<String, dynamic>;
      final responseTextPath =
          config.responseTextPath.isNotEmpty ? config.responseTextPath : 'text';
      final text =
          _extractNestedJsonValue(payload, responseTextPath) as String?;
      if (text == null || text.trim().isEmpty) {
        throw Exception(
          'Speech plugin response missing text at "$responseTextPath".',
        );
      }
      return text;
    }

    final requestId = headers['X-Api-Request-Id'] ?? _uuidV4();
    final resourceId = _resourceIdForPlugin(manifest, config);
    final pollUrl = Uri.parse('$normalizedBase$pollPath');
    const maxAttempts = 120;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final pollHeaders = <String, String>{
        'Content-Type': 'application/json',
      };
      for (final entry in config.extraHeaders.entries) {
        pollHeaders[entry.key] = _resolveHeaderValue(
          entry.value,
          manifest: manifest,
          config: config,
        );
      }
      if (apiKey.isNotEmpty) {
        final authHeader = config.authHeader?.trim() ?? '';
        if (authHeader.isNotEmpty) {
          pollHeaders[authHeader] =
              _authorizationValue(config.authScheme, apiKey);
        }
      }
      pollHeaders['X-Api-Request-Id'] = requestId;
      pollHeaders['X-Api-Resource-Id'] = resourceId;

      final pollResp = await _httpClient.post(
        pollUrl,
        headers: pollHeaders,
        body: '{}',
      );
      if (pollResp.statusCode < 200 || pollResp.statusCode >= 300) {
        throw Exception(
          'Poll failed (${pollResp.statusCode}): ${pollResp.body}',
        );
      }
      final statusCode = pollResp.headers['x-api-status-code'] ??
          pollResp.headers['x-tt-status-code'];
      if (statusCode == '20000000') {
        final payload = jsonDecode(pollResp.body) as Map<String, dynamic>;
        final responseTextPath = config.responseTextPath.isNotEmpty
            ? config.responseTextPath
            : 'text';
        final text =
            _extractNestedJsonValue(payload, responseTextPath) as String?;
        if (text == null || text.trim().isEmpty) {
          throw Exception(
            'Speech plugin response missing text at "$responseTextPath".',
          );
        }
        return text;
      }
      if (statusCode == '20000003') {
        throw Exception('No speech detected in the audio.');
      }
      if (statusCode != '20000001' && statusCode != '20000002') {
        final msg = pollResp.headers['x-api-message'] ?? pollResp.body;
        throw Exception('Batch ASR error $statusCode: $msg');
      }
    }
    throw Exception('Batch ASR polling timed out.');
  }

  String _resolvePathVars(String template, Map<String, String> vars) {
    var result = template;
    for (final entry in vars.entries) {
      result = result.replaceAll('\${${entry.key}}', entry.value);
    }
    return result;
  }

  Map<String, dynamic> _buildJsonBody(
    Map<String, dynamic> template, {
    required String audioDataUri,
    required String audioFormat,
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) {
    final modelValue = config.model.isNotEmpty ? config.model : manifest.id;
    return _resolveBodyMap(template, {
      'audio_data_uri': audioDataUri,
      'audio_format': audioFormat,
      'resource_id': _resourceIdForPlugin(manifest, config),
      'model': modelValue,
      'uuid': _uuidV4(),
    });
  }

  Map<String, dynamic> _resolveBodyMap(
    Map<String, dynamic> source,
    Map<String, String> vars,
  ) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is String) {
        result[entry.key] = _resolveBodyString(value, vars);
      } else if (value is Map<String, dynamic>) {
        result[entry.key] = _resolveBodyMap(value, vars);
      } else if (value is List) {
        result[entry.key] = value
            .map((item) => item is Map<String, dynamic>
                ? _resolveBodyMap(item, vars)
                : item is String
                    ? _resolveBodyString(item, vars)
                    : item)
            .toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  String _resolveBodyString(String value, Map<String, String> vars) {
    var resolved = value;
    for (final entry in vars.entries) {
      resolved = resolved.replaceAll('\${${entry.key}}', entry.value);
    }
    return resolved;
  }

  void _resolveTtsBodyVars(
      Map<String, dynamic> body, String text, String speaker) {
    for (final entry in body.entries.toList()) {
      final value = entry.value;
      if (value is String) {
        body[entry.key] = value
            .replaceAll(r'${text}', text)
            .replaceAll(r'${speaker}', speaker);
      } else if (value is Map<String, dynamic>) {
        _resolveTtsBodyVars(value, text, speaker);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            _resolveTtsBodyVars(item, text, speaker);
          }
        }
      }
    }
  }

  Map<String, String> _buildJsonRequestHeaders(
    SpeechPluginManifest manifest,
    SpeechPluginCapabilityConfig config,
    String apiKey,
  ) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey.isNotEmpty) {
      final authHeader = config.authHeader?.trim() ?? '';
      if (authHeader.isNotEmpty) {
        headers[authHeader] = _authorizationValue(config.authScheme, apiKey);
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }
    }
    for (final entry in config.extraHeaders.entries) {
      headers[entry.key] = _resolveHeaderValue(
        entry.value,
        manifest: manifest,
        config: config,
      );
    }
    return headers;
  }

  Future<SynthesizedSpeech> _synthesizeWithJsonPlugin(
    String text, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) async {
    final input = _sanitizeBridgeLocalTtsInput(text);
    if (input.isEmpty) {
      throw Exception(
        currentL10n().ttsFailed('Text contains no speakable characters.'),
      );
    }

    final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(manifest);
    final normalizedBase = _normalizeBaseUrl(config.baseUrl);
    final path = _normalizePluginPath(config.path, '');

    final body = _buildJsonBody(
      config.requestBody,
      audioDataUri: '',
      audioFormat: 'mp3',
      manifest: manifest,
      config: config,
    );
    final settings =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final speaker = settings['resource_id'] ?? '';
    _resolveTtsBodyVars(body, input, speaker);

    final headers = _buildJsonRequestHeaders(manifest, config, apiKey);
    final response = await _httpClient.post(
      Uri.parse('$normalizedBase$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'TTS request failed (${response.statusCode}): ${response.body}',
      );
    }

    final lines = const LineSplitter().convert(response.body);
    final audioChunks = <List<int>>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final payload = jsonDecode(trimmed) as Map<String, dynamic>;
        final base64Audio = payload['data'] as String?;
        if (base64Audio != null && base64Audio.isNotEmpty) {
          audioChunks.add(base64Decode(base64Audio.trim()));
        }
      } catch (_) {
        continue;
      }
    }
    if (audioChunks.isEmpty) {
      throw Exception('TTS response contains no audio data.');
    }
    final totalLength =
        audioChunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final merged = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in audioChunks) {
      merged.setAll(offset, chunk);
      offset += chunk.length;
    }
    return SynthesizedSpeech(
      bytes: merged,
      contentType: 'audio/mpeg',
    );
  }

  Future<SynthesizedSpeech> _synthesizeWithOpenAiCompatiblePlugin(
    String text, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) async {
    final input = _sanitizeBridgeLocalTtsInput(text);
    if (input.isEmpty) {
      throw Exception(
        currentL10n().ttsFailed('Text contains no speakable characters.'),
      );
    }

    final normalizedBase = _normalizeBaseUrl(config.baseUrl);
    final path = _normalizePluginPath(config.path, '/audio/speech');
    final apiKey = speechPluginRegistry.effectiveApiKeyForManifest(manifest);
    final authHeader = config.authHeader?.trim() ?? '';
    final authScheme = config.authScheme?.trim() ?? '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey.isNotEmpty) {
      if (authHeader.isNotEmpty) {
        headers[authHeader] = _authorizationValue(authScheme, apiKey);
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }
    }
    for (final entry in config.extraHeaders.entries) {
      headers[entry.key] = _resolveHeaderValue(
        entry.value,
        manifest: manifest,
        config: config,
      );
    }
    final settings =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final body = config.requestBody.isEmpty
        ? <String, dynamic>{
            'model': config.model.isNotEmpty ? config.model : manifest.id,
            'input': input,
            'response_format': 'wav',
          }
        : _buildJsonBody(
            config.requestBody,
            audioDataUri: '',
            audioFormat: 'wav',
            manifest: manifest,
            config: config,
          );
    _resolveTtsBodyVars(
      body,
      input,
      settings[SpeechPluginSettingFieldKey.resourceId.id] ?? '',
    );

    final response = await _httpClient.post(
      Uri.parse('$normalizedBase$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(response.body);
    }

    final contentType = response.headers['content-type'] ?? 'audio/wav';
    if (contentType.contains('application/json')) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>? ?? payload;
      final streamUrl = (data['stream_url'] as String?)?.trim();
      if (streamUrl?.isNotEmpty == true) {
        final resolvedUrl =
            Uri.parse(normalizedBase).resolve(streamUrl!).toString();
        return SynthesizedSpeech(
          bytes: Uint8List(0),
          contentType: data['content_type'] as String? ?? 'audio/wav',
          streamUrl: resolvedUrl,
        );
      }
    }

    return SynthesizedSpeech(
      bytes: response.bodyBytes,
      contentType: contentType,
    );
  }

  SpeechPluginCapabilityConfig? _resolvedPluginConfig(
    SpeechPluginManifest manifest,
    SpeechPluginCapability capability,
  ) {
    final base = manifest.configFor(capability);
    if (base == null) {
      return null;
    }
    final overrides =
        speechPluginRegistry.configuredSettingsForPluginId(manifest.id);
    final modelKey = modelSettingFieldKeyForCapability(capability);
    final resolved = base.copyWith(
      model: overrides[modelKey.id] ??
          overrides[SpeechPluginSettingFieldKey.model.id] ??
          base.model,
      baseUrl:
          overrides[SpeechPluginSettingFieldKey.baseUrl.id] ?? base.baseUrl,
      path: overrides[SpeechPluginSettingFieldKey.path.id] ?? base.path,
      websocketUrl: overrides[SpeechPluginSettingFieldKey.websocketUrl.id] ??
          base.websocketUrl,
      authHeader: overrides[SpeechPluginSettingFieldKey.authHeader.id] ??
          base.authHeader,
      authScheme: overrides[SpeechPluginSettingFieldKey.authScheme.id] ??
          base.authScheme,
    );

    for (final field in manifest.settingFieldsForCapability(capability)) {
      final value = switch (field.key) {
        SpeechPluginSettingFieldKey.model ||
        SpeechPluginSettingFieldKey.batchAsrModel ||
        SpeechPluginSettingFieldKey.ttsModel =>
          resolved.model.trim(),
        SpeechPluginSettingFieldKey.baseUrl => resolved.baseUrl.trim(),
        SpeechPluginSettingFieldKey.path => resolved.path?.trim() ?? '',
        SpeechPluginSettingFieldKey.websocketUrl =>
          resolved.websocketUrl?.trim() ?? '',
        SpeechPluginSettingFieldKey.resourceId =>
          (overrides[field.key.id] ?? resolved.eventMap[field.key.id] ?? '')
              .trim(),
        SpeechPluginSettingFieldKey.authHeader =>
          resolved.authHeader?.trim() ?? '',
        SpeechPluginSettingFieldKey.authScheme =>
          resolved.authScheme?.trim() ?? '',
      };
      if (field.required && value.isEmpty) {
        throw Exception(
          'Plugin setting required: ${field.localizedLabel(_pluginLocaleTag())}',
        );
      }
    }

    return resolved;
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    final value = trimmed.isEmpty ? 'https://api.openai.com/v1' : trimmed;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _pluginLocaleTag() {
    return preferredLocaleTagFromSetting(
      appSettingsController.settings.appLanguage,
    );
  }

  String _normalizePluginPath(String? raw, String fallback) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return fallback;
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
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

  String _resolveHeaderValue(
    String template, {
    required SpeechPluginManifest manifest,
    required SpeechPluginCapabilityConfig config,
  }) {
    final modelValue = config.model.isNotEmpty ? config.model : manifest.id;
    return template
        .replaceAll(r'${resource_id}', _resourceIdForPlugin(manifest, config))
        .replaceAll(r'${model}', modelValue)
        .replaceAll(r'${uuid}', _uuidV4());
  }

  String _resourceIdForPlugin(
    SpeechPluginManifest manifest,
    SpeechPluginCapabilityConfig config,
  ) {
    final configured = speechPluginRegistry
        .configuredSettingsForPluginId(
            manifest.id)[SpeechPluginSettingFieldKey.resourceId.id]
        ?.trim();
    if (configured?.isNotEmpty == true) {
      return configured!;
    }
    return config.model.isNotEmpty ? config.model : manifest.id;
  }

  String _authorizationValue(String? rawScheme, String apiKey) {
    final scheme = rawScheme?.trim() ?? '';
    if (scheme.isEmpty) {
      return apiKey;
    }
    return '$scheme $apiKey';
  }

  static String _uuidV4() {
    final r =
        List<int>.generate(16, (_) => (_random.nextDouble() * 256).truncate());
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    final hex = r.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final _random = Random();
}

Object? _extractNestedJsonValue(Map<String, dynamic> root, String path) {
  final segments = path.split('.');
  dynamic current = root;
  for (final segment in segments) {
    if (current is List) {
      final index = int.tryParse(segment);
      if (index != null && index >= 0 && index < current.length) {
        current = current[index];
      } else {
        return null;
      }
    } else if (current is Map<String, dynamic>) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

String? _extractBatchAsrText(
  Map<String, dynamic> payload,
  String preferredPath,
) {
  const fallbackPaths = [
    'utterances.0.text',
    'data.utterances.0.text',
    'result.utterances.0.text',
    'data.result.utterances.0.text',
  ];
  for (final path in [preferredPath, ...fallbackPaths]) {
    final value = _extractNestedJsonValue(payload, path);
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

final cloudSpeechService = CloudSpeechService();
