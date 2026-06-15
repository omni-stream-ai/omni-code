import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'bridge_speech_models.dart';
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
  Map<String, AgentDescriptor> _agentDescriptors = {};

  void _assertJsonResponse(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json') &&
        response.statusCode >= 400) {
      throw Exception(_extractErrorMessage(response));
    }
    if (response.statusCode >= 400) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  /// Extracts the error message from a JSON error response body.
  /// Falls back to the raw body if parsing fails.
  static String _extractErrorMessage(http.Response response) {
    return _extractErrorMessageFromBody(response.body);
  }

  /// Extracts the error message from a raw JSON body string.
  static String _extractErrorMessageFromBody(String rawBody) {
    try {
      final body = jsonDecode(rawBody) as Map<String, dynamic>;
      final error = body['error'];
      if (error is String) return error;
      if (error is Map<String, dynamic>) {
        return (error['message'] as String?) ?? rawBody;
      }
      return (body['message'] as String?) ?? rawBody;
    } catch (_) {
      return rawBody;
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

  Map<String, dynamic> _decodeApiData(String body) {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid bridge response: $body');
    }
    return data;
  }

  List<dynamic> _decodeApiListData(String body) {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is! List<dynamic>) {
      throw Exception('Invalid bridge response: $body');
    }
    return data;
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
      throw Exception(_extractErrorMessage(response));
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
      throw Exception(_extractErrorMessage(response));
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

  AgentDescriptor agentDescriptorFor(String agentId) {
    final direct = _agentDescriptors[agentId];
    if (direct != null) {
      return direct;
    }
    for (final descriptor in _agentDescriptors.values) {
      if (descriptor.matches(agentId)) {
        return descriptor;
      }
    }
    return fallbackAgentDescriptor(agentId);
  }

  String agentLabelFor(String agentId) => agentDescriptorFor(agentId).label;

  void _storeAgentDescriptors(Iterable<AgentSummary> agents) {
    _agentDescriptors = {
      for (final agent in agents) agent.id: agent.descriptor,
    };
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

  /// Fetches the full session detail (including optional git_status)
  /// from `GET /sessions/{id}`.
  Future<SessionDetail> getSession(String sessionId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/sessions/$sessionId'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final detail = SessionDetail.fromJson(payload);
    // Keep the session summary cache in sync.
    _upsertSession(detail.session);
    return detail;
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
        _extractErrorMessageFromBody(utf8.decode(bytes, allowMalformed: true)),
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
    String? systemPrompt,
    String? providerId,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'input_mode': inputMode,
    };
    final trimmedSystemPrompt = systemPrompt?.trim();
    if (trimmedSystemPrompt != null && trimmedSystemPrompt.isNotEmpty) {
      body['system_prompt'] = trimmedSystemPrompt;
    }
    if (providerId != null && providerId.isNotEmpty) {
      body['provider_id'] = providerId;
    }

    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions/$sessionId/messages'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
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

  Future<void> updateSessionProvider(
    String sessionId,
    String? providerId,
  ) async {
    final response = await _httpClient.patch(
      Uri.parse('$baseUrl/sessions/$sessionId'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'provider_id': providerId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> cancelReply(String sessionId) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions/$sessionId/cancel'),
      headers: _defaultHeaders,
    );

    if (response.statusCode != 204) {
      throw Exception(_extractErrorMessage(response));
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
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> updateBridgeSettings(
    AppSettings settings, {
    List<ModelProviderConfig>? modelProviders,
  }) async {
    final body = <String, dynamic>{
      'ai_approval': {
        'enabled': settings.aiApprovalEnabled,
        'base_url': settings.aiApprovalBaseUrl.trim(),
        'api_key': settings.aiApprovalApiKey.trim(),
        'model': settings.aiApprovalModel.trim(),
        'max_risk': settings.aiApprovalMaxRisk.trim(),
      },
    };
    if (modelProviders != null) {
      body['model_providers'] =
          modelProviders.map((p) => p.toJson()).toList();
    }
    final response = await _httpClient.put(
      Uri.parse('$baseUrl/settings'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<List<ModelProviderConfig>> getModelProviders() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/settings'),
      headers: _defaultHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>? ?? payload;
    final providers = data['model_providers'] as List<dynamic>? ?? [];
    return providers
        .map((p) => ModelProviderConfig.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<List<AgentSummary>> listAgents() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/agents'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final agents = _decodeApiListData(response.body)
        .whereType<Map<String, dynamic>>()
        .map(AgentSummary.fromJson)
        .toList(growable: false);
    _storeAgentDescriptors(agents);
    return agents;
  }

  Future<List<AgentCommand>> listAgentCommands() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/agents/commands'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final groups = _decodeApiListData(response.body).whereType<Map<String, dynamic>>();
    final commands = <AgentCommand>[];
    for (final group in groups) {
      final agentId =
          group['kind'] as String? ?? group['agent_id'] as String? ?? '';
      final items = group['commands'];
      if (items is! List) {
        continue;
      }
      for (final item in items.whereType<Map<String, dynamic>>()) {
        commands.add(
          AgentCommand.fromJson({
            ...item,
            if (agentId.isNotEmpty) 'agent_id': agentId,
          }),
        );
      }
    }
    return List.unmodifiable(commands);
  }

  Future<List<FileCompletionItem>> listFileCompletions({
    required String prefix,
    String? projectId,
    String? sessionId,
    int? limit,
  }) async {
    final trimmedPrefix = prefix.trim();
    if ((projectId == null || projectId.trim().isEmpty) &&
        (sessionId == null || sessionId.trim().isEmpty)) {
      throw ArgumentError('projectId or sessionId is required.');
    }
    final queryParameters = <String, String>{
      'prefix': trimmedPrefix,
    };
    final trimmedProjectId = projectId?.trim();
    final trimmedSessionId = sessionId?.trim();
    if (trimmedProjectId != null && trimmedProjectId.isNotEmpty) {
      queryParameters['project_id'] = trimmedProjectId;
    }
    if (trimmedSessionId != null && trimmedSessionId.isNotEmpty) {
      queryParameters['session_id'] = trimmedSessionId;
    }
    if (limit != null && limit > 0) {
      queryParameters['limit'] = '$limit';
    }
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/files/completions')
          .replace(queryParameters: queryParameters),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return _decodeApiListData(response.body)
        .whereType<Map<String, dynamic>>()
        .map(FileCompletionItem.fromJson)
        .toList(growable: false);
  }

  Future<AgentInstallResult> installAgent(String agentId) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/agents/install'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'agent': agentId}),
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return AgentInstallResult.fromJson(_decodeApiData(response.body));
  }

  Future<SessionSummary> createSession({
    required String projectId,
    String? title,
    required String agent,
    bool? briefReplyMode,
    String? providerId,
  }) async {
    final body = <String, dynamic>{
      'project_id': projectId,
      'title': title,
      'agent': agent,
      'brief_reply_mode': briefReplyMode ??
          appSettingsController.settings.compressAssistantReplies,
    };
    if (providerId != null && providerId.isNotEmpty) {
      body['provider_id'] = providerId;
    }
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/sessions'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
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
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<SpeechStatus> getSpeechStatus() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechStatus.fromJson(_decodeApiData(response.body));
  }

  Future<List<SpeechModelSummary>> listSpeechModels() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/models'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return _decodeApiListData(response.body)
        .whereType<Map<String, dynamic>>()
        .map(SpeechModelSummary.fromJson)
        .toList(growable: false);
  }

  Future<SpeechDownloadTask> createSpeechDownload(String modelId) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/speech/models/downloads'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'model_id': modelId}),
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechDownloadTask.fromJson(_decodeApiData(response.body));
  }

  Future<SpeechDownloadTask> getSpeechDownload(String taskId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/models/downloads/$taskId'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechDownloadTask.fromJson(_decodeApiData(response.body));
  }

  Future<void> deleteSpeechModel(String modelId) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/speech/models/$modelId'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<SpeechProfileBinding> getSpeechProfileModel(
      SpeechProfile profile) async {
    final response = await _httpClient.get(
      Uri.parse(
          '$baseUrl/speech/profiles/${_speechProfileSlug(profile)}/model'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechProfileBinding.fromJson(_decodeApiData(response.body));
  }

  Future<SpeechProfileSelection> updateSpeechProfileModel(
    SpeechProfile profile, {
    String? modelId,
  }) async {
    final response = await _httpClient.put(
      Uri.parse(
          '$baseUrl/speech/profiles/${_speechProfileSlug(profile)}/model'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'model_id': modelId}),
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechProfileSelection.fromJson(_decodeApiData(response.body));
  }

  Future<SpeechModelVoiceBinding> getSpeechModelVoice(String modelId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/models/$modelId/voice'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechModelVoiceBinding.fromJson(_decodeApiData(response.body));
  }

  Future<SpeechVoiceSelection> updateSpeechModelVoice(
    String modelId, {
    String? voice,
  }) async {
    final response = await _httpClient.put(
      Uri.parse('$baseUrl/speech/models/$modelId/voice'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'voice': voice}),
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeechVoiceSelection.fromJson(_decodeApiData(response.body));
  }

  Future<List<SpeakerRecord>> listSpeakers() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/speakers'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return _decodeApiListData(response.body)
        .whereType<Map<String, dynamic>>()
        .map(SpeakerRecord.fromJson)
        .toList(growable: false);
  }

  Future<SpeakerEnrollmentResult> enrollSpeaker(
    File audioFile, {
    required String name,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/speech/speakers'),
    );
    request.headers.addAll(_defaultHeaders);
    request.fields['name'] = name;
    request.files
        .add(await http.MultipartFile.fromPath('file', audioFile.path));
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessageFromBody(body));
    }
    return SpeakerEnrollmentResult.fromJson(_decodeApiData(body));
  }

  Future<void> deleteSpeaker(String speakerId) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/speech/speakers/$speakerId'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<SpeakerFilterSettings> getSpeakerFilter() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/speaker-filter'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeakerFilterSettings.fromJson(_decodeApiData(response.body));
  }

  Future<SpeakerFilterSettings> updateSpeakerFilter(
    SpeakerFilterSettings settings,
  ) async {
    final response = await _httpClient.put(
      Uri.parse('$baseUrl/speech/speaker-filter'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(settings.toJson()),
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return SpeakerFilterSettings.fromJson(_decodeApiData(response.body));
  }

  Future<Map<String, dynamic>> getSpeechRealtimeDescriptor() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/speech/realtime'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    return _decodeApiData(response.body);
  }

  Future<List<String>> listOpenAiSpeechModels() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/v1/models'),
      headers: _defaultHeaders,
    );
    if (_isUnauthorized(response)) {
      throw ClientUnauthorizedException(response.body);
    }
    _assertJsonResponse(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['data'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> transcribeAudio(
    File audioFile, {
    String? model,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/v1/audio/transcriptions'),
    );
    request.headers.addAll(_defaultHeaders);
    request.fields['response_format'] = 'json';
    if (model?.trim().isNotEmpty == true) {
      request.fields['model'] = model!.trim();
    }
    request.files
        .add(await http.MultipartFile.fromPath('file', audioFile.path));

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessageFromBody(body));
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final text = payload['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('ASR response missing text.');
    }
    return text;
  }

  Future<SynthesizedSpeech> synthesizeSpeech(
    String text, {
    String? model,
    String? voice,
    double speed = 1.0,
    String responseFormat = 'wav',
    bool stream = false,
  }) async {
    final input = _sanitizeSpeechInput(text);
    if (input.isEmpty) {
      throw Exception('TTS request missing speakable text.');
    }
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/v1/audio/speech'),
      headers: {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (model?.trim().isNotEmpty == true) 'model': model!.trim(),
        'input': input,
        if (voice?.trim().isNotEmpty == true) 'voice': voice!.trim(),
        'speed': speed,
        'response_format': responseFormat,
        if (stream) 'stream': true,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    final contentType = response.headers['content-type'] ?? 'audio/wav';
    if (contentType.contains('application/json')) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>? ?? payload;
      final streamUrl = (data['stream_url'] as String?)?.trim();
      if (streamUrl?.isNotEmpty == true) {
        return SynthesizedSpeech(
          bytes: Uint8List(0),
          contentType: data['content_type'] as String? ?? 'audio/wav',
          streamUrl: _resolveUrl(streamUrl!),
        );
      }
    }

    return SynthesizedSpeech(
      bytes: response.bodyBytes,
      contentType: contentType,
    );
  }

  String _resolveUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) {
      return uri.toString();
    }
    return Uri.parse(baseUrl).resolveUri(uri).toString();
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
          gitBranch: project.gitBranch ?? existing.gitBranch,
          gitStatus: project.gitStatus ?? existing.gitStatus,
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

  static String _speechProfileSlug(SpeechProfile profile) {
    return switch (profile) {
      SpeechProfile.asrBatch => 'asr.batch',
      SpeechProfile.asrRealtime => 'asr.realtime',
      SpeechProfile.ttsDefault => 'tts.default',
      SpeechProfile.vadDefault => 'vad.default',
      SpeechProfile.wakeWordDefault => 'wake_word.default',
    };
  }

  static String _sanitizeSpeechInput(String value) {
    final buffer = StringBuffer();
    var previousWasWhitespace = false;

    for (final rune in value.runes) {
      if (_isEmojiLikeRune(rune)) {
        continue;
      }
      final character = _normalizeSpeechRune(rune);
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

  static String _normalizeSpeechRune(int rune) {
    return switch (rune) {
      0x2018 || 0x2019 || 0x201A || 0x201B => "'",
      0x201C || 0x201D || 0x201E || 0x201F => '"',
      0x300C || 0x300D || 0x300E || 0x300F => '"',
      0x301D || 0x301E || 0x301F => '"',
      _ => String.fromCharCode(rune),
    };
  }

  static bool _isEmojiLikeRune(int rune) {
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
    this.streamUrl,
  });

  final Uint8List bytes;
  final String contentType;
  final String? streamUrl;

  bool get isStreaming => streamUrl?.isNotEmpty == true;
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
  factory ClientUnauthorizedException(String rawBody) {
    return ClientUnauthorizedException._(
      BridgeClient._extractErrorMessageFromBody(rawBody),
    );
  }
  const ClientUnauthorizedException._(this.message);
  final String message;

  @override
  String toString() => message;
}

extension on String {
  bool eq(String other) => toLowerCase() == other;
}
