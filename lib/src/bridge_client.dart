import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings/app_settings.dart';

class BridgeClient {
  BridgeClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const Duration _listCacheTtl = Duration(seconds: 15);

  final http.Client _httpClient;
  _CacheEntry<List<ProjectSummary>>? _projectsCache;
  _CacheEntry<List<SessionSummary>>? _sessionsCache;
  final Map<String, _CacheEntry<List<SessionSummary>>> _projectSessionsCache =
      {};

  void _assertJsonResponse(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json') &&
        response.statusCode >= 400) {
      throw Exception(
        'Bridge error (${response.statusCode}): ${response.body}',
      );
    }
    if (response.statusCode >= 400) {
      throw Exception(
        'Bridge error (${response.statusCode}): ${response.body}',
      );
    }
  }

  @visibleForTesting
  static List<ProjectSummary> sortProjectsForDisplay(
    Iterable<ProjectSummary> projects,
  ) {
    final sorted = projects.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @visibleForTesting
  static List<SessionSummary> sortSessionsForDisplay(
    Iterable<SessionSummary> sessions,
  ) {
    final sorted = sessions.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  String get baseUrl {
    final configured = appSettingsController.settings.bridgeUrl.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8787';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://127.0.0.1:8787'
        : 'http://127.0.0.1:8787';
  }

  Map<String, String> get _defaultHeaders {
    final settings = appSettingsController.settings;
    final headers = <String, String>{
      'X-Omni-Code-Client-Id': settings.clientId,
    };
    if (settings.bridgeToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.bridgeToken.trim()}';
    }
    return headers;
  }

  bool _isUnauthorized(http.Response response) {
    return response.statusCode == 401 || response.statusCode == 403;
  }

  Future<ClientAuthRequest> registerClient() async {
    final settings = appSettingsController.settings;
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/client-auth/requests'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': settings.clientId,
        'device_name': _deviceName(),
      }),
    );
    debugPrint(
        '[auth] registerClient response (${response.statusCode}): ${response.body}');
    if (response.statusCode >= 400) {
      throw Exception(
        'Register client failed (${response.statusCode}): ${response.body}',
      );
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>? ?? payload;
      debugPrint('[auth] registerClient payload keys: ${data.keys.toList()}');
      return ClientAuthRequest.fromJson(data);
    } catch (e) {
      throw Exception('Invalid response from server: ${response.body}');
    }
  }

  Future<ClientAuthRequest> checkClientAuthStatus(String requestId) async {
    final url = '$baseUrl/client-auth/requests/$requestId';
    debugPrint('[auth] Polling URL: $url');
    final response = await _httpClient.get(Uri.parse(url));
    debugPrint(
        '[auth] Poll response (${response.statusCode}): ${response.body}');
    if (response.statusCode >= 400) {
      throw Exception(
        'Check auth status failed (${response.statusCode}): ${response.body}',
      );
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>? ?? payload;
      return ClientAuthRequest.fromJson(data);
    } catch (e) {
      throw Exception('Invalid response from server: ${response.body}');
    }
  }

  String _deviceName() {
    if (kIsWeb) return 'Web Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android Device';
      case TargetPlatform.iOS:
        return 'iOS Device';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Unknown Device';
    }
  }

  Future<List<SessionSummary>> listSessions({bool forceRefresh = false}) async {
    final cache = _sessionsCache;
    if (!forceRefresh && cache != null && cache.isFresh) {
      return cache.value;
    }
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/sessions'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['data'] as List<dynamic>;
    final sessions = sortSessionsForDisplay(
      items
          .map((item) => SessionSummary.fromJson(item as Map<String, dynamic>)),
    );
    final syncedSessions = _syncSessions(
      current: sessions,
      cached: _sessionsCache?.value ?? const <SessionSummary>[],
    );
    _sessionsCache = _CacheEntry(syncedSessions);
    for (final session in syncedSessions) {
      _upsertProjectSessionCache(session);
    }
    return syncedSessions;
  }

  List<ProjectSummary>? peekProjects() => _projectsCache?.value;

  List<SessionSummary>? peekSessions() => _sessionsCache?.value;

  ProjectSummary? peekProject(String projectId) {
    return _projectsCache?.value
        .where((project) => project.id == projectId)
        .firstOrNull;
  }

  List<SessionSummary>? peekProjectSessions(String projectId) {
    return _projectSessionsCache[projectId]?.value;
  }

  SessionSummary? peekSession(String projectId, String sessionId) {
    return _projectSessionsCache[projectId]
        ?.value
        .where((session) => session.id == sessionId)
        .firstOrNull;
  }

  Future<List<ProjectSummary>> listProjects({bool forceRefresh = false}) async {
    final cache = _projectsCache;
    if (!forceRefresh && cache != null && cache.isFresh) {
      return cache.value;
    }
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/projects'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['data'] as List<dynamic>;
    final projects = sortProjectsForDisplay(
      items.map(
        (item) => ProjectSummary.fromJson(item as Map<String, dynamic>),
      ),
    );
    final mergedProjects = _mergeProjects(
      cached: _projectsCache?.value ?? const <ProjectSummary>[],
      incoming: projects,
    );
    _projectsCache = _CacheEntry(mergedProjects);
    return mergedProjects;
  }

  Future<ProjectSummary> getProject(
    String projectId, {
    bool forceRefresh = false,
  }) async {
    final cachedProject = peekProject(projectId);
    if (cachedProject != null && !forceRefresh) {
      return cachedProject;
    }

    final projects = await listProjects(forceRefresh: true);
    final project = projects.where((item) => item.id == projectId).firstOrNull;
    if (project == null) {
      throw StateError('Project not found: $projectId');
    }
    return project;
  }

  Future<List<ChatMessage>> listMessages(String sessionId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/sessions/$sessionId/messages'),
      headers: _defaultHeaders,
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['data'] as List<dynamic>;
    return items
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BridgeFileResponse> readFile(
    String path, {
    String? projectId,
    String? sessionId,
  }) async {
    if (projectId != null && sessionId != null) {
      throw ArgumentError(
        'projectId and sessionId cannot be set at the same time.',
      );
    }

    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError('path cannot be empty.');
    }

    final queryParameters = <String, String>{
      'path': trimmedPath,
    };
    if (!isAbsoluteFilePath(trimmedPath)) {
      final trimmedSessionId = sessionId?.trim();
      final trimmedProjectId = projectId?.trim();
      if (trimmedSessionId != null && trimmedSessionId.isNotEmpty) {
        queryParameters['session_id'] = trimmedSessionId;
      } else if (trimmedProjectId != null && trimmedProjectId.isNotEmpty) {
        queryParameters['project_id'] = trimmedProjectId;
      }
    }

    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/files').replace(queryParameters: queryParameters),
    )..headers.addAll(_defaultHeaders);
    final response = await _httpClient.send(request);
    final bytes = await response.stream.toBytes();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'file request failed (${response.statusCode}): '
        '${utf8.decode(bytes, allowMalformed: true)}',
      );
    }

    return BridgeFileResponse(
      bytes: bytes,
      contentType:
          response.headers['content-type'] ?? _guessContentType(trimmedPath),
    );
  }

  Future<List<SessionSummary>> listProjectSessions(
    String projectId, {
    bool forceRefresh = false,
  }) async {
    final cached = _projectSessionsCache[projectId];
    if (!forceRefresh && cached != null && cached.isFresh) {
      return cached.value;
    }
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/projects/$projectId/sessions'),
      headers: _defaultHeaders,
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['data'] as List<dynamic>;
    final sessions = items
        .map((item) => SessionSummary.fromJson(item as Map<String, dynamic>))
        .toList();
    final syncedSessions = _syncSessions(
      current: sessions,
      cached: cached?.value ?? const <SessionSummary>[],
    );
    _projectSessionsCache[projectId] = _CacheEntry(syncedSessions);
    _sessionsCache = _CacheEntry(
      _mergeSessions(
        cached: _sessionsCache?.value ?? const <SessionSummary>[],
        incoming: syncedSessions,
      ),
    );
    return syncedSessions;
  }

  Future<SessionSummary> getProjectSession(
    String projectId,
    String sessionId, {
    bool forceRefresh = false,
  }) async {
    final cachedSession = peekSession(projectId, sessionId);
    if (cachedSession != null && !forceRefresh) {
      return cachedSession;
    }

    final sessions = await listProjectSessions(
      projectId,
      forceRefresh: true,
    );
    final session = sessions.where((item) => item.id == sessionId).firstOrNull;
    if (session == null) {
      throw StateError('Session not found: $sessionId');
    }
    return session;
  }

  Future<SendMessageResult> sendMessage(
    String sessionId,
    String content, {
    String inputMode = 'text',
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions/$sessionId/messages'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'content': content, 'input_mode': inputMode}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'send message failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    return SendMessageResult(
      userMessage: ChatMessage.fromJson(
        data['user_message'] as Map<String, dynamic>,
      ),
      reply: ChatMessage.fromJson(data['reply'] as Map<String, dynamic>),
    );
  }

  Future<void> cancelReply(String sessionId) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions/$sessionId/cancel'),
      headers: _defaultHeaders,
    );

    if (response.statusCode != 204) {
      throw Exception(
        'cancel request failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> submitApproval(
    String sessionId,
    String requestId,
    String choice,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions/$sessionId/approvals/$requestId'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'choice': choice}),
    );

    if (response.statusCode != 204) {
      throw Exception(
        'approval request failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> updateBridgeSettings(AppSettings settings) async {
    final response = await _httpClient.put(
      Uri.parse('$baseUrl/settings'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'ai_approval': {
          'enabled': settings.aiApprovalEnabled,
          'base_url': settings.aiApprovalBaseUrl.trim(),
          'api_key': settings.aiApprovalApiKey.trim(),
          'model': settings.aiApprovalModel.trim(),
          'max_risk': settings.aiApprovalMaxRisk.trim(),
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'update settings failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<SessionSummary> createSession({
    required String projectId,
    String? title,
    String agent = 'codex',
    bool? briefReplyMode,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'project_id': projectId,
        'title': title,
        'agent': agent,
        'brief_reply_mode': briefReplyMode ??
            appSettingsController.settings.compressAssistantReplies,
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final session =
        SessionSummary.fromJson(payload['data'] as Map<String, dynamic>);
    _upsertSession(session);
    return session;
  }

  Future<ProjectSummary> createProject({
    required String name,
    required String rootPath,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/projects'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name, 'root_path': rootPath}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final project =
        ProjectSummary.fromJson(payload['data'] as Map<String, dynamic>);
    _upsertProject(project);
    return project;
  }

  Future<void> registerPushDevice({
    required String platform,
    String? manufacturer,
    String? model,
    String? appVersion,
    String? fcmToken,
    String? miPushRegId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/devices/register'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'platform': platform,
        'manufacturer': manufacturer,
        'model': model,
        'app_version': appVersion,
        'fcm_token': fcmToken,
        'mi_push_reg_id': miPushRegId,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'register push device failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<String> transcribeAudio(File audioFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/audio/transcriptions'),
    );
    request.headers.addAll(_defaultHeaders);
    request.files
        .add(await http.MultipartFile.fromPath('file', audioFile.path));

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('ASR request failed (${response.statusCode}): $body');
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    return data['text'] as String;
  }

  Future<SynthesizedSpeech> synthesizeSpeech(
    String text, {
    String voice = 'female',
    double speed = 1.0,
    double volume = 1.0,
    String responseFormat = 'wav',
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/audio/speech'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'input': text,
        'voice': voice,
        'speed': speed,
        'volume': volume,
        'response_format': responseFormat,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'TTS request failed (${response.statusCode}): ${response.body}',
      );
    }

    return SynthesizedSpeech(
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'audio/wav',
    );
  }

  Stream<Map<String, dynamic>> subscribeToSessionEvents(
    String sessionId,
  ) async* {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/sessions/$sessionId/events'),
    );
    request.headers['Accept'] = 'text/event-stream';
    request.headers.addAll(_defaultHeaders);

    final response = await _httpClient.send(request);
    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    String? eventName;
    final dataBuffer = <String>[];

    await for (final line in lines) {
      if (line.isEmpty) {
        if (eventName != null && dataBuffer.isNotEmpty) {
          yield {
            'event': eventName,
            'data': jsonDecode(dataBuffer.join('\n')) as Map<String, dynamic>,
          };
        }
        eventName = null;
        dataBuffer.clear();
        continue;
      }

      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataBuffer.add(line.substring(5).trim());
      }
    }
  }

  void _upsertProject(ProjectSummary project) {
    final current = _projectsCache?.value ?? const <ProjectSummary>[];
    final next = sortProjectsForDisplay([
      ...current.where((item) => item.id != project.id),
      project,
    ]);
    _projectsCache = _CacheEntry(next);
  }

  void _upsertSession(SessionSummary session) {
    final current = _sessionsCache?.value ?? const <SessionSummary>[];
    final next = _mergeSessions(
      cached: current,
      incoming: [session],
    );
    _sessionsCache = _CacheEntry(next);
    _upsertProjectSessionCache(session);

    ProjectSummary? project;
    for (final item in _projectsCache?.value ?? const <ProjectSummary>[]) {
      if (item.id == session.projectId) {
        project = item;
        break;
      }
    }
    if (project == null) {
      return;
    }
    _upsertProject(
      project.copyWith(
        updatedAt: session.updatedAt,
        sessionCount: next.length,
        lastSessionPreview:
            session.lastMessagePreview?.trim().isNotEmpty == true
                ? session.lastMessagePreview
                : project.lastSessionPreview,
      ),
    );
  }

  void _upsertProjectSessionCache(SessionSummary session) {
    final current = _projectSessionsCache[session.projectId]?.value ??
        const <SessionSummary>[];
    final next = _mergeSessions(
      cached: current,
      incoming: [session],
    );
    _projectSessionsCache[session.projectId] = _CacheEntry(next);
  }

  void syncSessionSummary(SessionSummary session) {
    _upsertSession(session);
  }

  @visibleForTesting
  void debugSeedProjects(Iterable<ProjectSummary> projects) {
    _projectsCache = _CacheEntry(sortProjectsForDisplay(projects));
  }

  @visibleForTesting
  void debugSeedSessions(Iterable<SessionSummary> sessions) {
    final sorted = sortSessionsForDisplay(sessions);
    _sessionsCache = _CacheEntry(sorted);
    for (final session in sorted) {
      _upsertProjectSessionCache(session);
    }
  }

  static List<ProjectSummary> _mergeProjects({
    required Iterable<ProjectSummary> cached,
    required Iterable<ProjectSummary> incoming,
  }) {
    final merged = <String, ProjectSummary>{};

    for (final project in cached) {
      merged[project.id] = project;
    }

    for (final project in incoming) {
      final existing = merged[project.id];
      if (existing == null || project.updatedAt.isAfter(existing.updatedAt)) {
        merged[project.id] = project;
        continue;
      }

      if (project.updatedAt.isAtSameMomentAs(existing.updatedAt)) {
        merged[project.id] = ProjectSummary(
          id: project.id,
          name: project.name,
          rootPath: project.rootPath,
          updatedAt: project.updatedAt,
          sessionCount: max(project.sessionCount, existing.sessionCount),
          lastSessionPreview: _preferNonEmptyPreview(
            project.lastSessionPreview,
            existing.lastSessionPreview,
          ),
        );
      }
    }

    return sortProjectsForDisplay(merged.values);
  }

  static String? _preferNonEmptyPreview(String? primary, String? fallback) {
    if (primary?.trim().isNotEmpty == true) {
      return primary;
    }
    if (fallback?.trim().isNotEmpty == true) {
      return fallback;
    }
    return null;
  }

  static List<SessionSummary> _mergeSessions({
    required Iterable<SessionSummary> cached,
    required Iterable<SessionSummary> incoming,
  }) {
    final merged = <String, SessionSummary>{};

    for (final session in cached) {
      merged[session.id] = session;
    }

    for (final session in incoming) {
      final existing = merged[session.id];
      if (existing == null || session.updatedAt.isAfter(existing.updatedAt)) {
        merged[session.id] = session;
        continue;
      }

      if (session.updatedAt.isAtSameMomentAs(existing.updatedAt)) {
        merged[session.id] = session.copyWith(
          unreadCount: max(session.unreadCount, existing.unreadCount),
          lastMessagePreview: _preferNonEmptyPreview(
            session.lastMessagePreview,
            existing.lastMessagePreview,
          ),
          pendingApproval: session.pendingApproval ?? existing.pendingApproval,
        );
      }
    }

    final sorted = merged.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  static List<SessionSummary> _syncSessions({
    required Iterable<SessionSummary> current,
    required Iterable<SessionSummary> cached,
  }) {
    final cachedById = {
      for (final session in cached) session.id: session,
    };
    final synced = current.map((session) {
      final existing = cachedById[session.id];
      if (existing == null) {
        return session;
      }
      if (existing.updatedAt.isAfter(session.updatedAt)) {
        return existing;
      }
      if (existing.updatedAt.isAtSameMomentAs(session.updatedAt)) {
        return session.copyWith(
          unreadCount: max(session.unreadCount, existing.unreadCount),
          lastMessagePreview: _preferNonEmptyPreview(
            session.lastMessagePreview,
            existing.lastMessagePreview,
          ),
          pendingApproval: session.pendingApproval ?? existing.pendingApproval,
        );
      }
      return session;
    }).toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return synced;
  }

  static bool isAbsoluteFilePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.eq('file')) {
      return true;
    }

    return trimmed.startsWith('/') ||
        trimmed.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
  }

  static bool isSupportedImagePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        uri.hasScheme &&
        !uri.scheme.eq('http') &&
        !uri.scheme.eq('https') &&
        !uri.scheme.eq('file')) {
      return false;
    }

    final normalizedPath =
        uri != null && uri.hasScheme ? uri.path : trimmed.split('?').first;
    return RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|svg)$',
      caseSensitive: false,
    ).hasMatch(normalizedPath);
  }

  static String _guessContentType(String path) {
    final normalized = path.toLowerCase();
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.gif')) {
      return 'image/gif';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalized.endsWith('.bmp')) {
      return 'image/bmp';
    }
    if (normalized.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    return 'application/octet-stream';
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value) : storedAt = DateTime.now();

  final T value;
  final DateTime storedAt;

  bool get isFresh =>
      DateTime.now().difference(storedAt) < BridgeClient._listCacheTtl;
}

final bridgeClient = BridgeClient();

class SynthesizedSpeech {
  const SynthesizedSpeech({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final String contentType;
}

class BridgeFileResponse {
  const BridgeFileResponse({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final String contentType;
}

class SendMessageResult {
  const SendMessageResult({
    required this.userMessage,
    required this.reply,
  });

  final ChatMessage userMessage;
  final ChatMessage reply;
}

class ClientUnauthorizedException implements Exception {
  const ClientUnauthorizedException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension on String {
  bool eq(String other) => toLowerCase() == other;
}
