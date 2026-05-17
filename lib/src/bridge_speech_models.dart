enum SpeechModelKind { asr, tts, vad }

enum SpeechRuntime { offline, streaming }

enum SpeechComputeBackend { cpu, onnx }

enum SpeechProfile { asrBatch, asrRealtime, ttsDefault, vadDefault }

enum SpeechDownloadStatus {
  queued,
  downloading,
  extracting,
  verifying,
  completed,
  failed,
}

class SpeechModelCapabilities {
  const SpeechModelCapabilities({
    required this.streaming,
    required this.realtimeAsr,
    required this.batchAsr,
    required this.speechSynthesis,
    required this.vad,
    required this.endpointing,
    required this.punctuation,
    required this.inverseTextNormalization,
    required this.multilingual,
  });

  final bool streaming;
  final bool realtimeAsr;
  final bool batchAsr;
  final bool speechSynthesis;
  final bool vad;
  final bool endpointing;
  final bool punctuation;
  final bool inverseTextNormalization;
  final bool multilingual;

  factory SpeechModelCapabilities.fromJson(Map<String, dynamic> json) {
    return SpeechModelCapabilities(
      streaming: json['streaming'] as bool? ?? false,
      realtimeAsr: json['realtime_asr'] as bool? ?? false,
      batchAsr: json['batch_asr'] as bool? ?? false,
      speechSynthesis: json['speech_synthesis'] as bool? ?? false,
      vad: json['vad'] as bool? ?? false,
      endpointing: json['endpointing'] as bool? ?? false,
      punctuation: json['punctuation'] as bool? ?? false,
      inverseTextNormalization:
          json['inverse_text_normalization'] as bool? ?? false,
      multilingual: json['multilingual'] as bool? ?? false,
    );
  }
}

class SpeechProfileSelection {
  const SpeechProfileSelection({
    this.asrBatch,
    this.asrRealtime,
    this.ttsDefault,
    this.vadDefault,
  });

  final String? asrBatch;
  final String? asrRealtime;
  final String? ttsDefault;
  final String? vadDefault;

  String? modelForProfile(SpeechProfile profile) {
    return switch (profile) {
      SpeechProfile.asrBatch => asrBatch,
      SpeechProfile.asrRealtime => asrRealtime,
      SpeechProfile.ttsDefault => ttsDefault,
      SpeechProfile.vadDefault => vadDefault,
    };
  }

  factory SpeechProfileSelection.fromJson(Map<String, dynamic> json) {
    return SpeechProfileSelection(
      asrBatch: _readNullableString(json['asr_batch']),
      asrRealtime: _readNullableString(json['asr_realtime']),
      ttsDefault: _readNullableString(json['tts_default']),
      vadDefault: _readNullableString(json['vad_default']),
    );
  }
}

class SpeechModelSummary {
  const SpeechModelSummary({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.description,
    required this.languages,
    required this.runtime,
    required this.backend,
    required this.capabilities,
    required this.features,
    required this.supportsProfiles,
    required this.recommendedProfiles,
    required this.downloadUrl,
    required this.voices,
    required this.voiceDetails,
    required this.installed,
    required this.selectedBy,
    this.docsUrl,
    this.downloadSizeMb,
    this.memoryHint,
    this.notes,
    this.sampleRateHz,
    this.defaultVoice,
    this.installPath,
  });

  final String id;
  final SpeechModelKind kind;
  final String displayName;
  final String description;
  final List<String> languages;
  final SpeechRuntime runtime;
  final SpeechComputeBackend backend;
  final SpeechModelCapabilities capabilities;
  final List<String> features;
  final List<SpeechProfile> supportsProfiles;
  final List<SpeechProfile> recommendedProfiles;
  final String downloadUrl;
  final String? docsUrl;
  final int? downloadSizeMb;
  final String? memoryHint;
  final String? notes;
  final int? sampleRateHz;
  final String? defaultVoice;
  final List<String> voices;
  final List<SpeechVoiceSummary> voiceDetails;
  final bool installed;
  final String? installPath;
  final List<SpeechProfile> selectedBy;

  factory SpeechModelSummary.fromJson(Map<String, dynamic> json) {
    return SpeechModelSummary(
      id: json['id'] as String? ?? '',
      kind: _parseSpeechModelKind(json['kind'] as String?),
      displayName: json['display_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      languages: _readStringList(json['languages']),
      runtime: _parseSpeechRuntime(json['runtime'] as String?),
      backend: _parseSpeechComputeBackend(json['backend'] as String?),
      capabilities: SpeechModelCapabilities.fromJson(
        (json['capabilities'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      features: _readStringList(json['features']),
      supportsProfiles: _readSpeechProfiles(json['supports_profiles']),
      recommendedProfiles: _readSpeechProfiles(json['recommended_profiles']),
      downloadUrl: json['download_url'] as String? ?? '',
      docsUrl: _readNullableString(json['docs_url']),
      downloadSizeMb: _readNullableInt(json['download_size_mb']),
      memoryHint: _readNullableString(json['memory_hint']),
      notes: _readNullableString(json['notes']),
      sampleRateHz: _readNullableInt(json['sample_rate_hz']),
      defaultVoice: _readNullableString(json['default_voice']),
      voices: _readStringList(json['voices']),
      voiceDetails: _readVoiceSummaries(json['voice_details']),
      installed: json['installed'] as bool? ?? false,
      installPath: _readNullableString(json['install_path']),
      selectedBy: _readSpeechProfiles(json['selected_by']),
    );
  }
}

class SpeechVoiceSummary {
  const SpeechVoiceSummary({
    required this.id,
    required this.name,
    required this.language,
    this.accent,
    this.gender,
  });

  final String id;
  final String name;
  final String language;
  final String? accent;
  final String? gender;

  factory SpeechVoiceSummary.fromJson(Map<String, dynamic> json) {
    return SpeechVoiceSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? '',
      accent: _readNullableString(json['accent']),
      gender: _readNullableString(json['gender']),
    );
  }
}

class SpeechDownloadTask {
  const SpeechDownloadTask({
    required this.taskId,
    required this.modelId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.progressBytes,
    this.totalBytes,
    this.installPath,
    this.error,
  });

  final String taskId;
  final String modelId;
  final SpeechDownloadStatus status;
  final int? progressBytes;
  final int? totalBytes;
  final String? installPath;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal =>
      status == SpeechDownloadStatus.completed ||
      status == SpeechDownloadStatus.failed;

  double? get progress {
    final total = totalBytes;
    final current = progressBytes;
    if (total == null || total <= 0 || current == null) {
      return null;
    }
    return current / total;
  }

  factory SpeechDownloadTask.fromJson(Map<String, dynamic> json) {
    return SpeechDownloadTask(
      taskId: json['task_id'] as String? ?? '',
      modelId: json['model_id'] as String? ?? '',
      status: _parseSpeechDownloadStatus(json['status'] as String?),
      progressBytes: _readNullableInt(json['progress_bytes']),
      totalBytes: _readNullableInt(json['total_bytes']),
      installPath: _readNullableString(json['install_path']),
      error: _readNullableString(json['error']),
      createdAt: _readDateTime(json['created_at']),
      updatedAt: _readDateTime(json['updated_at']),
    );
  }
}

class SpeechStatus {
  const SpeechStatus({
    required this.rootDir,
    required this.profiles,
    required this.models,
    required this.downloads,
  });

  final String rootDir;
  final SpeechProfileSelection profiles;
  final List<SpeechModelSummary> models;
  final List<SpeechDownloadTask> downloads;

  List<SpeechDownloadTask> get activeDownloads =>
      downloads.where((task) => !task.isTerminal).toList(growable: false);

  factory SpeechStatus.fromJson(Map<String, dynamic> json) {
    return SpeechStatus(
      rootDir: json['root_dir'] as String? ?? '',
      profiles: SpeechProfileSelection.fromJson(
        (json['profiles'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      models: _readModelList(json['models']),
      downloads: _readDownloadList(json['downloads']),
    );
  }
}

class SpeechProfileBinding {
  const SpeechProfileBinding({
    required this.profile,
    required this.modelId,
  });

  final SpeechProfile profile;
  final String? modelId;

  factory SpeechProfileBinding.fromJson(Map<String, dynamic> json) {
    return SpeechProfileBinding(
      profile: _parseSpeechProfile(json['profile'] as String?),
      modelId: _readNullableString(json['model_id']),
    );
  }
}

SpeechModelKind _parseSpeechModelKind(String? raw) {
  return switch (raw) {
    'tts' => SpeechModelKind.tts,
    'vad' => SpeechModelKind.vad,
    _ => SpeechModelKind.asr,
  };
}

SpeechRuntime _parseSpeechRuntime(String? raw) {
  return raw == 'streaming' ? SpeechRuntime.streaming : SpeechRuntime.offline;
}

SpeechComputeBackend _parseSpeechComputeBackend(String? raw) {
  return raw == 'onnx' ? SpeechComputeBackend.onnx : SpeechComputeBackend.cpu;
}

SpeechProfile _parseSpeechProfile(String? raw) {
  return switch (raw) {
    'asr_realtime' => SpeechProfile.asrRealtime,
    'tts_default' => SpeechProfile.ttsDefault,
    'vad_default' => SpeechProfile.vadDefault,
    _ => SpeechProfile.asrBatch,
  };
}

SpeechDownloadStatus _parseSpeechDownloadStatus(String? raw) {
  return switch (raw) {
    'downloading' => SpeechDownloadStatus.downloading,
    'extracting' => SpeechDownloadStatus.extracting,
    'verifying' => SpeechDownloadStatus.verifying,
    'completed' => SpeechDownloadStatus.completed,
    'failed' => SpeechDownloadStatus.failed,
    _ => SpeechDownloadStatus.queued,
  };
}

List<String> _readStringList(Object? raw) {
  final values = raw as List<dynamic>? ?? const <dynamic>[];
  return values
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<SpeechVoiceSummary> _readVoiceSummaries(Object? raw) {
  final values = raw as List<dynamic>? ?? const <dynamic>[];
  return values
      .whereType<Map<String, dynamic>>()
      .map(SpeechVoiceSummary.fromJson)
      .where((item) => item.id.trim().isNotEmpty)
      .toList(growable: false);
}

List<SpeechProfile> _readSpeechProfiles(Object? raw) {
  final values = raw as List<dynamic>? ?? const <dynamic>[];
  return values
      .map((item) => _parseSpeechProfile(item as String?))
      .toList(growable: false);
}

List<SpeechModelSummary> _readModelList(Object? raw) {
  final values = raw as List<dynamic>? ?? const <dynamic>[];
  return values
      .whereType<Map<String, dynamic>>()
      .map(SpeechModelSummary.fromJson)
      .toList(growable: false);
}

List<SpeechDownloadTask> _readDownloadList(Object? raw) {
  final values = raw as List<dynamic>? ?? const <dynamic>[];
  return values
      .whereType<Map<String, dynamic>>()
      .map(SpeechDownloadTask.fromJson)
      .toList(growable: false);
}

String? _readNullableString(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

int? _readNullableInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw?.toString() ?? '');
}

DateTime _readDateTime(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.trim().isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
