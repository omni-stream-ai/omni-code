import 'package:flutter/foundation.dart';

enum SpeechPluginCapability {
  realtimeAsr('speech.realtime_asr'),
  batchAsr('speech.batch_asr'),
  tts('speech.tts');

  const SpeechPluginCapability(this.id);

  final String id;

  static SpeechPluginCapability? tryParse(String value) {
    for (final capability in SpeechPluginCapability.values) {
      if (capability.id == value) {
        return capability;
      }
    }
    return null;
  }
}

enum SpeechPluginTransport {
  metadataOnly('metadata_only'),
  openAiCompatible('openai_compatible'),
  bridgeOpenAiCompatible('bridge_openai_compatible'),
  realtimeWebsocket('realtime_websocket');

  const SpeechPluginTransport(this.id);

  final String id;

  static SpeechPluginTransport parse(String? value) {
    for (final transport in SpeechPluginTransport.values) {
      if (transport.id == value) {
        return transport;
      }
    }
    return SpeechPluginTransport.metadataOnly;
  }
}

enum SpeechPluginSettingFieldKey {
  model('model'),
  batchAsrModel('batch_asr_model'),
  ttsModel('tts_model'),
  baseUrl('base_url'),
  path('path'),
  websocketUrl('websocket_url'),
  resourceId('resource_id'),
  authHeader('auth_header'),
  authScheme('auth_scheme');

  const SpeechPluginSettingFieldKey(this.id);

  final String id;

  static SpeechPluginSettingFieldKey? tryParse(String value) {
    for (final field in SpeechPluginSettingFieldKey.values) {
      if (field.id == value) {
        return field;
      }
    }
    return null;
  }
}

SpeechPluginSettingFieldKey modelSettingFieldKeyForCapability(
  SpeechPluginCapability capability,
) =>
    switch (capability) {
      SpeechPluginCapability.batchAsr =>
        SpeechPluginSettingFieldKey.batchAsrModel,
      SpeechPluginCapability.tts => SpeechPluginSettingFieldKey.ttsModel,
      SpeechPluginCapability.realtimeAsr => SpeechPluginSettingFieldKey.model,
    };

@immutable
class SpeechPluginSource {
  const SpeechPluginSource({
    required this.id,
    required this.name,
    required this.indexUrl,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String indexUrl;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'index_url': indexUrl,
      'enabled': enabled,
    };
  }

  factory SpeechPluginSource.fromJson(Map<String, dynamic> json) {
    return SpeechPluginSource(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      indexUrl: (json['index_url'] as String? ?? '').trim(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

@immutable
class SpeechPluginSettingField {
  const SpeechPluginSettingField({
    required this.key,
    required this.label,
    this.help = '',
    this.placeholder = '',
    this.required = false,
    this.options = const [],
    this.capabilities = const [],
    this.localized = const {},
  });

  final SpeechPluginSettingFieldKey key;
  final String label;
  final String help;
  final String placeholder;
  final bool required;
  final List<SpeechPluginSettingFieldOption> options;
  final List<SpeechPluginCapability> capabilities;
  final Map<String, Map<String, String>> localized;

  String localizedLabel(String localeTag) {
    return _localizedString(localized, localeTag, 'label', label);
  }

  String localizedHelp(String localeTag) {
    return _localizedString(localized, localeTag, 'help', help);
  }

  String localizedPlaceholder(String localeTag) {
    return _localizedString(
      localized,
      localeTag,
      'placeholder',
      placeholder,
    );
  }

  bool appliesTo(SpeechPluginCapability capability) {
    return capabilities.isEmpty || capabilities.contains(capability);
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key.id,
      'label': label,
      if (help.isNotEmpty) 'help': help,
      if (placeholder.isNotEmpty) 'placeholder': placeholder,
      if (required) 'required': true,
      if (options.isNotEmpty)
        'options': options.map((item) => item.toJson()).toList(),
      if (capabilities.isNotEmpty)
        'capabilities': capabilities.map((item) => item.id).toList(),
      if (localized.isNotEmpty) 'localized': localized,
    };
  }

  factory SpeechPluginSettingField.fromJson(Map<String, dynamic> json) {
    final key = SpeechPluginSettingFieldKey.tryParse(
      (json['key'] as String? ?? '').trim(),
    );
    if (key == null) {
      throw FormatException('Unknown speech plugin setting field key.');
    }
    return SpeechPluginSettingField(
      key: key,
      label: (json['label'] as String? ?? '').trim().isNotEmpty
          ? (json['label'] as String).trim()
          : key.id,
      help: (json['help'] as String? ?? '').trim(),
      placeholder: (json['placeholder'] as String? ?? '').trim(),
      required: json['required'] as bool? ?? false,
      options: _readSettingFieldOptions(json['options']),
      capabilities: _parseCapabilities(json['capabilities']),
      localized: _readLocalizedMap(json['localized']),
    );
  }
}

@immutable
class SpeechPluginSettingFieldOption {
  const SpeechPluginSettingFieldOption({
    required this.value,
    required this.label,
    this.help = '',
    this.localized = const {},
  });

  final String value;
  final String label;
  final String help;
  final Map<String, Map<String, String>> localized;

  String localizedLabel(String localeTag) {
    return _localizedString(localized, localeTag, 'label', label);
  }

  String localizedHelp(String localeTag) {
    return _localizedString(localized, localeTag, 'help', help);
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'label': label,
      if (help.isNotEmpty) 'help': help,
      if (localized.isNotEmpty) 'localized': localized,
    };
  }

  factory SpeechPluginSettingFieldOption.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] as String? ?? '').trim();
    return SpeechPluginSettingFieldOption(
      value: value,
      label: (json['label'] as String? ?? '').trim().isNotEmpty
          ? (json['label'] as String).trim()
          : value,
      help: (json['help'] as String? ?? '').trim(),
      localized: _readLocalizedMap(json['localized']),
    );
  }
}

@immutable
class SpeechPluginRepositoryEntry {
  const SpeechPluginRepositoryEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.repo,
    required this.sourceId,
    this.description = '',
    this.registrationUrl = '',
    this.manifestUrl,
    this.capabilities = const [],
    this.localized = const {},
    this.version = '',
    this.sourceName = '',
    this.indexUrl = '',
    this.repoBranch = 'main',
    this.manifestPath = 'manifest.json',
    this.builtInManifest,
  });

  final String id;
  final String name;
  final String author;
  final String repo;
  final String sourceId;
  final String sourceName;
  final String indexUrl;
  final String repoBranch;
  final String manifestPath;
  final String? manifestUrl;
  final SpeechPluginManifest? builtInManifest;
  final List<SpeechPluginCapability> capabilities;
  final String version;
  final String description;
  final String registrationUrl;
  final Map<String, Map<String, String>> localized;

  String localizedName(String localeTag) {
    return _localizedString(localized, localeTag, 'name', name);
  }

  String localizedDescription(String localeTag) {
    return _localizedString(
      localized,
      localeTag,
      'description',
      description,
    );
  }

  String get resolvedManifestUrl {
    final direct = manifestUrl?.trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final sourceIndex = indexUrl.trim();
    if (sourceIndex.isNotEmpty && repo.trim().isEmpty) {
      final path =
          manifestPath.trim().isEmpty ? 'manifest.json' : manifestPath.trim();
      final sourceUri = Uri.tryParse(sourceIndex);
      if (sourceUri != null && sourceUri.scheme == 'file') {
        return sourceUri.resolve(path).toString();
      }
      if (sourceUri != null && sourceUri.scheme.isNotEmpty) {
        return sourceUri.resolve(path).toString();
      }
      final separator = sourceIndex.contains('\\') ? '\\' : '/';
      final lastSeparator = sourceIndex.lastIndexOf(separator);
      final baseDirectory =
          lastSeparator >= 0 ? sourceIndex.substring(0, lastSeparator + 1) : '';
      return '$baseDirectory$path';
    }
    if (repo.trim().isEmpty) {
      return '';
    }
    final branch = repoBranch.trim().isEmpty ? 'main' : repoBranch.trim();
    final path =
        manifestPath.trim().isEmpty ? 'manifest.json' : manifestPath.trim();
    return 'https://raw.githubusercontent.com/${repo.trim()}/$branch/$path';
  }

  factory SpeechPluginRepositoryEntry.fromJson(
    Map<String, dynamic> json, {
    required SpeechPluginSource source,
  }) {
    return SpeechPluginRepositoryEntry(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      author: (json['author'] as String? ?? '').trim(),
      repo: (json['repo'] as String? ?? '').trim(),
      sourceId: source.id,
      sourceName: source.name,
      indexUrl: source.indexUrl,
      repoBranch: (json['branch'] as String? ?? 'main').trim(),
      manifestPath:
          (json['manifest_path'] as String? ?? 'manifest.json').trim(),
      manifestUrl: (json['manifest_url'] as String?)?.trim(),
      capabilities: _parseCapabilities(json['capabilities']),
      localized: _readLocalizedMap(json['localized']),
      version: (json['version'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
      registrationUrl: (json['registration_url'] as String? ?? '').trim(),
    );
  }
}

/// A ready-to-configure provider for OpenAI and services exposing the same
/// `/audio/transcriptions` and `/audio/speech` endpoints.
const openAiCompatibleSpeechManifest = SpeechPluginManifest(
  id: 'openai-compatible-speech',
  name: 'OpenAI Compatible Speech',
  version: '1.0.0',
  description:
      'Use an OpenAI-compatible API for audio transcription and text-to-speech.',
  apiKeyLabel: 'API Key',
  capabilities: [
    SpeechPluginCapability.batchAsr,
    SpeechPluginCapability.tts,
  ],
  transport: SpeechPluginTransport.openAiCompatible,
  capabilityConfigs: {
    SpeechPluginCapability.batchAsr: SpeechPluginCapabilityConfig(
      transport: SpeechPluginTransport.openAiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      model: 'whisper-1',
      path: '/audio/transcriptions',
    ),
    SpeechPluginCapability.tts: SpeechPluginCapabilityConfig(
      transport: SpeechPluginTransport.openAiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini-tts',
      path: '/audio/speech',
      requestBody: {
        'model': r'${model}',
        'input': r'${text}',
        'voice': r'${speaker}',
        'response_format': 'wav',
      },
    ),
  },
  settingFields: [
    SpeechPluginSettingField(
      key: SpeechPluginSettingFieldKey.baseUrl,
      label: 'Base URL',
      help:
          'Include the API version path, for example https://api.openai.com/v1.',
      placeholder: 'https://api.openai.com/v1',
      required: true,
    ),
    SpeechPluginSettingField(
      key: SpeechPluginSettingFieldKey.batchAsrModel,
      label: 'ASR model',
      placeholder: 'whisper-1',
      required: true,
      capabilities: [SpeechPluginCapability.batchAsr],
    ),
    SpeechPluginSettingField(
      key: SpeechPluginSettingFieldKey.ttsModel,
      label: 'TTS model',
      placeholder: 'gpt-4o-mini-tts',
      required: true,
      capabilities: [SpeechPluginCapability.tts],
    ),
    SpeechPluginSettingField(
      key: SpeechPluginSettingFieldKey.resourceId,
      label: 'TTS voice',
      help: 'The voice name accepted by the selected API.',
      placeholder: 'alloy',
      required: true,
      capabilities: [SpeechPluginCapability.tts],
    ),
  ],
  localized: {
    'zh': {
      'name': 'OpenAI 兼容语音服务',
      'description': '通过 OpenAI 兼容接口进行音频转写和文字转语音。',
      'api_key_label': 'API Key',
    },
  },
);

final builtInSpeechPluginRepositoryEntries =
    List<SpeechPluginRepositoryEntry>.unmodifiable([
  SpeechPluginRepositoryEntry(
    id: openAiCompatibleSpeechManifest.id,
    name: openAiCompatibleSpeechManifest.name,
    author: 'Omni Code',
    repo: '',
    sourceId: 'built-in',
    sourceName: 'Built in',
    description: openAiCompatibleSpeechManifest.description,
    capabilities: openAiCompatibleSpeechManifest.capabilities,
    builtInManifest: openAiCompatibleSpeechManifest,
    localized: openAiCompatibleSpeechManifest.localized,
    version: openAiCompatibleSpeechManifest.version,
  ),
]);

@immutable
class SpeechPluginRepositoryIndex {
  const SpeechPluginRepositoryIndex({
    required this.plugins,
    required this.source,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final SpeechPluginSource source;
  final List<SpeechPluginRepositoryEntry> plugins;

  factory SpeechPluginRepositoryIndex.fromJson(
    Object raw, {
    required SpeechPluginSource source,
  }) {
    final rawPlugins = switch (raw) {
      List<dynamic> list => list,
      Map<String, dynamic> map =>
        map['plugins'] as List<dynamic>? ?? const <dynamic>[],
      _ => const <dynamic>[],
    };
    final schemaVersion = switch (raw) {
      Map<String, dynamic> map => switch (map['schema_version']) {
          int value => value,
          num value => value.toInt(),
          _ => 1,
        },
      _ => 1,
    };
    return SpeechPluginRepositoryIndex(
      schemaVersion: schemaVersion,
      source: source,
      plugins: rawPlugins
          .whereType<Map>()
          .map(
            (item) => SpeechPluginRepositoryEntry.fromJson(
              Map<String, dynamic>.from(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
              source: source,
            ),
          )
          .where(
            (entry) =>
                entry.id.isNotEmpty &&
                entry.name.isNotEmpty &&
                (entry.resolvedManifestUrl.isNotEmpty || entry.repo.isNotEmpty),
          )
          .toList(growable: false),
    );
  }
}

@immutable
class SpeechPluginCapabilityConfig {
  const SpeechPluginCapabilityConfig({
    this.transport = SpeechPluginTransport.metadataOnly,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.path,
    this.pollPath,
    this.websocketUrl,
    this.authHeader,
    this.authScheme,
    this.eventMap = const {},
    this.textFieldMap = const {},
    this.requestFieldMap = const {},
    this.responseTextPath = '',
    this.requestContentType = '',
    this.requestBody = const {},
    this.extraHeaders = const {},
  });

  final SpeechPluginTransport transport;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String? path;
  final String? pollPath;
  final String? websocketUrl;
  final String? authHeader;
  final String? authScheme;
  final Map<String, String> eventMap;
  final Map<String, String> textFieldMap;
  final Map<String, String> requestFieldMap;
  final String responseTextPath;
  final String requestContentType;
  final Map<String, dynamic> requestBody;
  final Map<String, String> extraHeaders;

  SpeechPluginTransport get resolvedTransport {
    if (transport != SpeechPluginTransport.metadataOnly) return transport;
    if (websocketUrl != null && websocketUrl!.isNotEmpty) {
      return SpeechPluginTransport.realtimeWebsocket;
    }
    if (baseUrl.isNotEmpty) return SpeechPluginTransport.openAiCompatible;
    return SpeechPluginTransport.metadataOnly;
  }

  SpeechPluginCapabilityConfig copyWith({
    SpeechPluginTransport? transport,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? path,
    String? pollPath,
    String? websocketUrl,
    String? authHeader,
    String? authScheme,
    Map<String, String>? eventMap,
    Map<String, String>? textFieldMap,
    Map<String, String>? requestFieldMap,
    String? responseTextPath,
    String? requestContentType,
    Map<String, dynamic>? requestBody,
    Map<String, String>? extraHeaders,
  }) {
    return SpeechPluginCapabilityConfig(
      transport: transport ?? this.transport,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      path: path ?? this.path,
      pollPath: pollPath ?? this.pollPath,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      authHeader: authHeader ?? this.authHeader,
      authScheme: authScheme ?? this.authScheme,
      eventMap: eventMap ?? this.eventMap,
      textFieldMap: textFieldMap ?? this.textFieldMap,
      requestFieldMap: requestFieldMap ?? this.requestFieldMap,
      responseTextPath: responseTextPath ?? this.responseTextPath,
      requestContentType: requestContentType ?? this.requestContentType,
      requestBody: requestBody ?? this.requestBody,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transport': transport.id,
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
      if (path != null) 'path': path,
      if (pollPath != null) 'poll_path': pollPath,
      if (websocketUrl != null) 'websocket_url': websocketUrl,
      if (authHeader != null) 'auth_header': authHeader,
      if (authScheme != null) 'auth_scheme': authScheme,
      if (eventMap.isNotEmpty) 'event_map': eventMap,
      if (textFieldMap.isNotEmpty) 'text_field_map': textFieldMap,
      if (requestFieldMap.isNotEmpty) 'request_field_map': requestFieldMap,
      if (responseTextPath.isNotEmpty) 'response_text_path': responseTextPath,
      if (requestContentType.isNotEmpty)
        'request_content_type': requestContentType,
      if (requestBody.isNotEmpty) 'request_body': requestBody,
      if (extraHeaders.isNotEmpty) 'extra_headers': extraHeaders,
    };
  }

  factory SpeechPluginCapabilityConfig.fromJson(Map<String, dynamic> json) {
    return SpeechPluginCapabilityConfig(
      transport: SpeechPluginTransport.parse(json['transport'] as String?),
      baseUrl: (json['base_url'] as String? ?? '').trim(),
      apiKey: (json['api_key'] as String? ?? '').trim(),
      model: (json['model'] as String? ?? '').trim(),
      path: (json['path'] as String?)?.trim(),
      pollPath: (json['poll_path'] as String?)?.trim(),
      websocketUrl: (json['websocket_url'] as String?)?.trim(),
      authHeader: (json['auth_header'] as String?)?.trim(),
      authScheme: (json['auth_scheme'] as String?)?.trim(),
      eventMap: _readStringMap(json['event_map']),
      textFieldMap: _readStringMap(json['text_field_map']),
      requestFieldMap: _readStringMap(json['request_field_map']),
      responseTextPath: (json['response_text_path'] as String? ?? '').trim(),
      requestContentType:
          (json['request_content_type'] as String? ?? '').trim(),
      requestBody: json['request_body'] is Map
          ? Map<String, dynamic>.from(json['request_body'] as Map)
          : const {},
      extraHeaders: _readStringMap(json['extra_headers']),
    );
  }
}

@immutable
class SpeechPluginManifest {
  const SpeechPluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.capabilities,
    this.transport = SpeechPluginTransport.metadataOnly,
    this.capabilityConfigs = const {},
    this.settingFields = const [],
    this.description = '',
    this.registrationUrl = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.realtimeAsrPath,
    this.batchAsrPath,
    this.ttsPath,
    this.realtimeWebsocketUrl,
    this.realtimeAuthHeader,
    this.realtimeAuthScheme,
    this.realtimeEventMap = const {},
    this.realtimeTextFieldMap = const {},
    this.apiKeyLabel = '',
    this.requiresApiKey = true,
    this.serviceCommands = const {},
    this.localized = const {},
  });

  final String id;
  final String name;
  final String version;
  final List<SpeechPluginCapability> capabilities;
  final SpeechPluginTransport transport;
  final Map<SpeechPluginCapability, SpeechPluginCapabilityConfig>
      capabilityConfigs;
  final List<SpeechPluginSettingField> settingFields;
  final String description;
  final String registrationUrl;
  final String baseUrl;
  final String apiKey;
  final String? realtimeAsrPath;
  final String? batchAsrPath;
  final String? ttsPath;
  final String? realtimeWebsocketUrl;
  final String? realtimeAuthHeader;
  final String? realtimeAuthScheme;
  final Map<String, String> realtimeEventMap;
  final Map<String, String> realtimeTextFieldMap;
  final String apiKeyLabel;
  final bool requiresApiKey;
  final Map<String, String> serviceCommands;
  final Map<String, Map<String, String>> localized;

  String localizedName(String localeTag) {
    return _localizedString(localized, localeTag, 'name', name);
  }

  String localizedDescription(String localeTag) {
    return _localizedString(
      localized,
      localeTag,
      'description',
      description,
    );
  }

  String localizedApiKeyLabel(String localeTag) {
    return _localizedString(
      localized,
      localeTag,
      'api_key_label',
      apiKeyLabel,
    );
  }

  bool supports(SpeechPluginCapability capability) {
    return capabilities.contains(capability);
  }

  SpeechPluginCapabilityConfig? configFor(SpeechPluginCapability capability) {
    final scoped = capabilityConfigs[capability];
    if (scoped != null) {
      return scoped;
    }
    if (!supports(capability)) {
      return null;
    }
    return switch (capability) {
      SpeechPluginCapability.batchAsr => SpeechPluginCapabilityConfig(
          transport: transport,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: id,
          path: batchAsrPath,
        ),
      SpeechPluginCapability.tts => SpeechPluginCapabilityConfig(
          transport: transport,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: id,
          path: ttsPath,
        ),
      SpeechPluginCapability.realtimeAsr => SpeechPluginCapabilityConfig(
          transport: transport,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: id,
          path: realtimeAsrPath,
          websocketUrl: realtimeWebsocketUrl,
          authHeader: realtimeAuthHeader,
          authScheme: realtimeAuthScheme,
          eventMap: realtimeEventMap,
          textFieldMap: realtimeTextFieldMap,
        ),
    };
  }

  List<SpeechPluginSettingField> settingFieldsForCapability(
    SpeechPluginCapability capability,
  ) {
    return settingFields
        .where((field) => field.appliesTo(capability))
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      if (registrationUrl.isNotEmpty) 'registration_url': registrationUrl,
      'capabilities': capabilities.map((item) => item.id).toList(),
      'transport': transport.id,
      if (capabilityConfigs.isNotEmpty)
        'capability_configs': {
          for (final entry in capabilityConfigs.entries)
            entry.key.id: entry.value.toJson(),
        },
      if (settingFields.isNotEmpty)
        'setting_fields': settingFields.map((item) => item.toJson()).toList(),
      'base_url': baseUrl,
      'api_key': apiKey,
      if (realtimeAsrPath != null) 'realtime_asr_path': realtimeAsrPath,
      if (batchAsrPath != null) 'batch_asr_path': batchAsrPath,
      if (ttsPath != null) 'tts_path': ttsPath,
      if (realtimeWebsocketUrl != null)
        'realtime_websocket_url': realtimeWebsocketUrl,
      if (realtimeAuthHeader != null)
        'realtime_auth_header': realtimeAuthHeader,
      if (realtimeAuthScheme != null)
        'realtime_auth_scheme': realtimeAuthScheme,
      if (realtimeEventMap.isNotEmpty) 'realtime_event_map': realtimeEventMap,
      if (realtimeTextFieldMap.isNotEmpty)
        'realtime_text_field_map': realtimeTextFieldMap,
      if (apiKeyLabel.isNotEmpty) 'api_key_label': apiKeyLabel,
      if (!requiresApiKey) 'requires_api_key': false,
      if (serviceCommands.isNotEmpty) 'service_commands': serviceCommands,
      if (localized.isNotEmpty) 'localized': localized,
    };
  }

  factory SpeechPluginManifest.fromJson(Map<String, dynamic> json) {
    return SpeechPluginManifest(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      version: (json['version'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
      registrationUrl: (json['registration_url'] as String? ?? '').trim(),
      capabilities: _parseCapabilities(json['capabilities']),
      transport: SpeechPluginTransport.parse(json['transport'] as String?),
      capabilityConfigs: _readCapabilityConfigs(json['capability_configs']),
      settingFields: _readSettingFields(json['setting_fields']),
      baseUrl: (json['base_url'] as String? ?? '').trim(),
      apiKey: (json['api_key'] as String? ?? '').trim(),
      realtimeAsrPath: (json['realtime_asr_path'] as String?)?.trim(),
      batchAsrPath: (json['batch_asr_path'] as String?)?.trim(),
      ttsPath: (json['tts_path'] as String?)?.trim(),
      realtimeWebsocketUrl: (json['realtime_websocket_url'] as String?)?.trim(),
      realtimeAuthHeader: (json['realtime_auth_header'] as String?)?.trim(),
      realtimeAuthScheme: (json['realtime_auth_scheme'] as String?)?.trim(),
      realtimeEventMap: _readStringMap(json['realtime_event_map']),
      realtimeTextFieldMap: _readStringMap(json['realtime_text_field_map']),
      apiKeyLabel: (json['api_key_label'] as String? ?? '').trim(),
      requiresApiKey: json['requires_api_key'] as bool? ?? true,
      serviceCommands: _readStringMap(json['service_commands']),
      localized: _readLocalizedMap(json['localized']),
    );
  }
}

@immutable
class InstalledSpeechPlugin {
  const InstalledSpeechPlugin({
    required this.installedAt,
    required this.manifest,
  });

  final DateTime installedAt;
  final SpeechPluginManifest manifest;

  Map<String, dynamic> toJson() {
    return {
      'installed_at': installedAt.toIso8601String(),
      'manifest': manifest.toJson(),
    };
  }

  factory InstalledSpeechPlugin.fromJson(Map<String, dynamic> json) {
    final rawManifest = json['manifest'];
    return InstalledSpeechPlugin(
      installedAt: DateTime.tryParse(
            (json['installed_at'] as String? ?? '').trim(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      manifest: SpeechPluginManifest.fromJson(
        rawManifest is Map<String, dynamic>
            ? rawManifest
            : const <String, dynamic>{},
      ),
    );
  }
}

List<SpeechPluginCapability> _parseCapabilities(Object? raw) {
  final items = raw is List ? raw : const <dynamic>[];
  final capabilities = <SpeechPluginCapability>[];
  for (final item in items) {
    final value = item?.toString().trim() ?? '';
    final capability = SpeechPluginCapability.tryParse(value);
    if (capability != null && !capabilities.contains(capability)) {
      capabilities.add(capability);
    }
  }
  return List<SpeechPluginCapability>.unmodifiable(capabilities);
}

Map<String, String> _readStringMap(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  return Map<String, String>.unmodifiable({
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  });
}

Map<String, Map<String, String>> _readLocalizedMap(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  final result = <String, Map<String, String>>{};
  for (final entry in raw.entries) {
    final locale = entry.key.toString().trim().replaceAll('_', '-');
    if (locale.isEmpty || entry.value is! Map) {
      continue;
    }
    final values = _readStringMap(entry.value);
    if (values.isNotEmpty) {
      result[locale] = values;
    }
  }
  return Map<String, Map<String, String>>.unmodifiable(
    result.map(
      (key, value) => MapEntry(key, Map<String, String>.unmodifiable(value)),
    ),
  );
}

String _localizedString(
  Map<String, Map<String, String>> localized,
  String localeTag,
  String key,
  String fallback,
) {
  final locale = localeTag.trim().replaceAll('_', '-').toLowerCase();
  final language = locale.split('-').first;
  for (final candidate in <String>[locale, language]) {
    final values = localized[candidate] ?? localized[candidate.toUpperCase()];
    final value = values?[key]?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  for (final entry in localized.entries) {
    final entryLocale = entry.key.trim().replaceAll('_', '-').toLowerCase();
    if (entryLocale == locale || entryLocale.split('-').first == language) {
      final value = entry.value[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return fallback;
}

List<SpeechPluginSettingField> _readSettingFields(Object? raw) {
  final items = raw is List ? raw : const <dynamic>[];
  final result = <SpeechPluginSettingField>[];
  for (final item in items.whereType<Map>()) {
    try {
      result.add(
        SpeechPluginSettingField.fromJson(
          Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        ),
      );
    } catch (_) {
      continue;
    }
  }
  return List<SpeechPluginSettingField>.unmodifiable(result);
}

List<SpeechPluginSettingFieldOption> _readSettingFieldOptions(Object? raw) {
  final items = raw is List ? raw : const <dynamic>[];
  final result = <SpeechPluginSettingFieldOption>[];
  for (final item in items.whereType<Map>()) {
    try {
      final option = SpeechPluginSettingFieldOption.fromJson(
        Map<String, dynamic>.from(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
      if (option.value.isNotEmpty) {
        result.add(option);
      }
    } catch (_) {
      continue;
    }
  }
  return List<SpeechPluginSettingFieldOption>.unmodifiable(result);
}

Map<SpeechPluginCapability, SpeechPluginCapabilityConfig>
    _readCapabilityConfigs(
  Object? raw,
) {
  if (raw is! Map) {
    return const {};
  }
  final configs = <SpeechPluginCapability, SpeechPluginCapabilityConfig>{};
  for (final entry in raw.entries) {
    final capability =
        SpeechPluginCapability.tryParse(entry.key.toString().trim());
    if (capability == null || entry.value is! Map) {
      continue;
    }
    configs[capability] = SpeechPluginCapabilityConfig.fromJson(
      Map<String, dynamic>.from(
        (entry.value as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
    );
  }
  return Map<SpeechPluginCapability, SpeechPluginCapabilityConfig>.unmodifiable(
    configs,
  );
}
