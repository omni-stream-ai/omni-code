enum ApiFormat {
  openaiCompatible('open-ai-compatible', 'OpenAI Compatible',
      ['openai', 'openai-compatible']),
  anthropicMessages(
      'anthropic-messages', 'Anthropic', ['anthropic', 'anthropic-messages']),
  codex('codex', 'Codex', ['codex']);

  const ApiFormat(this.id, this.label, [this.aliases = const []]);

  final String id;
  final String label;
  final List<String> aliases;

  static ApiFormat parse(String value) {
    for (final format in ApiFormat.values) {
      if (format.id == value || format.aliases.contains(value)) {
        return format;
      }
    }
    return ApiFormat.openaiCompatible;
  }
}

List<ApiFormat> parseApiFormats(Iterable<dynamic>? values) {
  if (values == null) {
    return const [];
  }
  final formats = <ApiFormat>[];
  for (final value in values) {
    if (value is! String) {
      continue;
    }
    final format = ApiFormat.parse(value);
    if (!formats.contains(format)) {
      formats.add(format);
    }
  }
  return List.unmodifiable(formats);
}

const autoProviderId = 'AUTO';

bool isAutoProviderId(String? providerId) =>
    providerId != null && providerId.toUpperCase() == autoProviderId;

class ModelProviderConfig {
  const ModelProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.model,
    this.format = ApiFormat.openaiCompatible,
    this.enabled = true,
    this.priority = 0,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String? model;
  final ApiFormat format;
  final bool enabled;
  final int priority;

  ModelProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool clearModel = false,
    ApiFormat? format,
    bool? enabled,
    int? priority,
  }) {
    return ModelProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: clearModel ? null : (model ?? this.model),
      format: format ?? this.format,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      if (apiKey.isNotEmpty) 'api_key': apiKey,
      if (model != null) 'model': model,
      'format': format.id,
      'enabled': enabled,
      'priority': priority,
    };
  }

  factory ModelProviderConfig.fromJson(Map<String, dynamic> json) {
    return ModelProviderConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      model: json['model'] as String?,
      format: ApiFormat.parse(json['format'] as String? ?? 'openai-compatible'),
      enabled: json['enabled'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
    );
  }
}

enum SessionStatus {
  idle,
  running,
  awaitingApproval,
  interrupted,
  waiting,
  failed,
}

enum MessageRole { user, assistant, system }

enum ReasoningEffort {
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh'),
  max('max');

  const ReasoningEffort(this.apiValue);

  final String apiValue;
}

enum ApprovalChoice {
  accept,
  acceptForSession,
  alwaysAllow,
  decline,
  cancel,
}

class AgentDescriptor {
  const AgentDescriptor({
    required this.id,
    required this.label,
    this.aliases = const [],
    this.selectable = true,
    this.defaultSelected = false,
    this.compatibleFormats = const [],
  });

  final String id;
  final String label;
  final List<String> aliases;
  final bool selectable;
  final bool defaultSelected;
  final List<ApiFormat> compatibleFormats;

  bool matches(String value) {
    return value == id || aliases.contains(value);
  }

  factory AgentDescriptor.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String?)?.trim();
    final legacyKind = (json['kind'] as String?)?.trim();
    final resolvedId = (id != null && id.isNotEmpty) ? id : (legacyKind ?? '');
    final compatibleFormats = parseApiFormats(
      json['compatible_formats'] as List<dynamic>?,
    );
    final trimmedLabel = (json['label'] as String?)?.trim();
    return AgentDescriptor(
      id: resolvedId.isNotEmpty ? resolvedId : 'unknown',
      label: trimmedLabel?.isNotEmpty == true
          ? trimmedLabel!
          : (resolvedId.isNotEmpty ? resolvedId : 'Agent'),
      aliases: _readStringList(json['aliases']) ?? const [],
      selectable: json['selectable'] as bool? ?? true,
      defaultSelected: json['default_selected'] as bool? ?? false,
      compatibleFormats: compatibleFormats,
    );
  }
}

AgentDescriptor fallbackAgentDescriptor(String? resolvedId) {
  final normalized = resolvedId?.trim() ?? '';
  return AgentDescriptor(
    id: normalized.isEmpty ? 'unknown' : normalized,
    label: normalized.isEmpty ? 'Agent' : normalized,
    compatibleFormats: const [],
  );
}

List<String>? _readStringList(Object? value) {
  if (value is! List) {
    return null;
  }
  return List.unmodifiable(
    value.whereType<String>().map((item) => item.trim()).where((item) {
      return item.isNotEmpty;
    }),
  );
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.requestId,
    required this.kind,
    required this.allowAcceptForSession,
    required this.allowCancel,
    required this.resolvable,
    this.command,
    this.reason,
  });

  final String requestId;
  final String kind;
  final String? command;
  final String? reason;
  final bool allowAcceptForSession;
  final bool allowCancel;
  final bool resolvable;

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      requestId: json['request_id'] as String,
      kind: json['kind'] as String,
      command: json['command'] as String?,
      reason: json['reason'] as String?,
      allowAcceptForSession: json['allow_accept_for_session'] as bool? ?? false,
      allowCancel: json['allow_cancel'] as bool? ?? false,
      resolvable: json['resolvable'] as bool? ?? true,
    );
  }
}

class ClientAuthRequest {
  const ClientAuthRequest({
    required this.requestId,
    required this.status,
    this.token,
  });

  final String requestId;
  final String status;
  final String? token;

  bool get isPending => status == 'pending';
  bool get isApproved => token != null && token!.isNotEmpty;

  factory ClientAuthRequest.fromJson(Map<String, dynamic> json) {
    return ClientAuthRequest(
      requestId: (json['request_id'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      token: json['token'] as String?,
    );
  }
}

class AgentSummary {
  const AgentSummary({
    required this.descriptor,
    required this.installed,
    required this.installHint,
    this.installedPath,
  });

  final AgentDescriptor descriptor;
  final bool installed;
  final String installHint;
  final String? installedPath;

  String get id => descriptor.id;
  String get label => descriptor.label;
  List<String> get aliases => descriptor.aliases;
  bool get selectable => descriptor.selectable;
  bool get defaultSelected => descriptor.defaultSelected;
  List<ApiFormat> get compatibleFormats => descriptor.compatibleFormats;

  factory AgentSummary.fromJson(Map<String, dynamic> json) {
    return AgentSummary(
      descriptor: AgentDescriptor.fromJson(json),
      installed: json['installed'] as bool? ?? false,
      installHint: json['install_hint'] as String? ?? '',
      installedPath: json['installed_path'] as String?,
    );
  }
}

class AgentInstallResult {
  const AgentInstallResult({
    required this.agentId,
    required this.success,
    this.message,
    this.installedPath,
  });

  final String agentId;
  final bool success;
  final String? message;
  final String? installedPath;

  factory AgentInstallResult.fromJson(Map<String, dynamic> json) {
    return AgentInstallResult(
      agentId: json['agent'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      installedPath: json['installed_path'] as String?,
    );
  }
}

class AgentCommand {
  const AgentCommand({
    required this.name,
    this.description,
    this.agentId,
    this.aliases = const [],
  });

  final String name;
  final String? description;
  final String? agentId;
  final List<String> aliases;

  factory AgentCommand.fromJson(Map<String, dynamic> json) {
    return AgentCommand(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      agentId: json['agent_id'] as String? ?? json['agent'] as String?,
      aliases: _readStringList(json['aliases']) ?? const [],
    );
  }
}

class FileCompletionItem {
  const FileCompletionItem({
    required this.path,
    required this.isDir,
  });

  final String path;
  final bool isDir;

  factory FileCompletionItem.fromJson(Map<String, dynamic> json) {
    return FileCompletionItem(
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
    );
  }
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.updatedAt,
    required this.sessionCount,
    this.lastSessionPreview,
    this.gitBranch,
    this.gitStatus,
  });

  final String id;
  final String name;
  final String rootPath;
  final DateTime updatedAt;
  final int sessionCount;
  final String? lastSessionPreview;
  final String? gitBranch;
  final ProjectGitStatus? gitStatus;

  ProjectSummary copyWith({
    String? id,
    String? name,
    String? rootPath,
    DateTime? updatedAt,
    int? sessionCount,
    String? lastSessionPreview,
    String? gitBranch,
    bool clearGitBranch = false,
    ProjectGitStatus? gitStatus,
    bool clearGitStatus = false,
  }) {
    return ProjectSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionCount: sessionCount ?? this.sessionCount,
      lastSessionPreview: lastSessionPreview ?? this.lastSessionPreview,
      gitBranch: clearGitBranch ? null : gitBranch ?? this.gitBranch,
      gitStatus: clearGitStatus ? null : gitStatus ?? this.gitStatus,
    );
  }

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    return ProjectSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      rootPath: json['root_path'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sessionCount: json['session_count'] as int,
      lastSessionPreview: json['last_session_preview'] as String?,
      gitBranch: json['git_branch'] as String?,
      gitStatus: parseProjectGitStatus(json['git_status'] as String?),
    );
  }
}

enum ProjectGitStatus { clean, dirty }

ProjectGitStatus? parseProjectGitStatus(String? value) {
  switch (value) {
    case 'clean':
      return ProjectGitStatus.clean;
    case 'dirty':
      return ProjectGitStatus.dirty;
    default:
      return null;
  }
}

SessionStatus parseSessionStatus(String value) {
  switch (value) {
    case 'idle':
      return SessionStatus.idle;
    case 'running':
      return SessionStatus.running;
    case 'awaiting_approval':
      return SessionStatus.awaitingApproval;
    case 'interrupted':
      return SessionStatus.interrupted;
    case 'waiting':
      return SessionStatus.waiting;
    case 'failed':
      return SessionStatus.failed;
    default:
      return SessionStatus.idle;
  }
}

MessageRole parseMessageRole(String value) {
  switch (value) {
    case 'user':
      return MessageRole.user;
    case 'system':
      return MessageRole.system;
    default:
      return MessageRole.assistant;
  }
}

ReasoningEffort? parseReasoningEffort(String? value) {
  switch (value) {
    case 'low':
      return ReasoningEffort.low;
    case 'medium':
      return ReasoningEffort.medium;
    case 'high':
      return ReasoningEffort.high;
    case 'xhigh':
      return ReasoningEffort.xhigh;
    case 'max':
      return ReasoningEffort.max;
    default:
      return null;
  }
}

ApprovalChoice parseApprovalChoice(String value) {
  switch (value) {
    case 'accept':
      return ApprovalChoice.accept;
    case 'accept_for_session':
      return ApprovalChoice.acceptForSession;
    case 'always_allow':
      return ApprovalChoice.alwaysAllow;
    case 'decline':
      return ApprovalChoice.decline;
    case 'cancel':
      return ApprovalChoice.cancel;
    default:
      return ApprovalChoice.accept;
  }
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.projectId,
    required this.title,
    required this.agentId,
    required this.briefReplyMode,
    required this.status,
    required this.updatedAt,
    required this.unreadCount,
    this.lastMessagePreview,
    this.pendingApproval,
    this.errorMessage,
    this.providerId,
    this.reasoningEffort,
    this.forkedFromSessionId,
  });

  final String id;
  final String projectId;
  final String title;
  final String agentId;
  final bool briefReplyMode;
  final SessionStatus status;
  final DateTime updatedAt;
  final int unreadCount;
  final String? lastMessagePreview;
  final ApprovalRequest? pendingApproval;
  final String? errorMessage;
  final String? providerId;
  final ReasoningEffort? reasoningEffort;
  final String? forkedFromSessionId;

  SessionSummary copyWith({
    String? id,
    String? projectId,
    String? title,
    String? agentId,
    bool? briefReplyMode,
    SessionStatus? status,
    DateTime? updatedAt,
    int? unreadCount,
    String? lastMessagePreview,
    ApprovalRequest? pendingApproval,
    bool clearPendingApproval = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? providerId,
    bool clearProviderId = false,
    ReasoningEffort? reasoningEffort,
    bool clearReasoningEffort = false,
    String? forkedFromSessionId,
    bool clearForkedFromSessionId = false,
  }) {
    return SessionSummary(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      agentId: agentId ?? this.agentId,
      briefReplyMode: briefReplyMode ?? this.briefReplyMode,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      pendingApproval:
          clearPendingApproval ? null : pendingApproval ?? this.pendingApproval,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      providerId: clearProviderId ? null : providerId ?? this.providerId,
      reasoningEffort: clearReasoningEffort
          ? null
          : reasoningEffort ?? this.reasoningEffort,
      forkedFromSessionId: clearForkedFromSessionId
          ? null
          : forkedFromSessionId ?? this.forkedFromSessionId,
    );
  }

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      title: json['title'] as String,
      agentId: json['agent'] as String,
      briefReplyMode: json['brief_reply_mode'] as bool? ?? false,
      status: parseSessionStatus(json['status'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      unreadCount: json['unread_count'] as int,
      lastMessagePreview: json['last_message_preview'] as String?,
      errorMessage: json['error_message'] as String?,
      providerId: json['provider_id'] as String?,
      reasoningEffort:
          parseReasoningEffort(json['reasoning_effort'] as String?),
      forkedFromSessionId: json['forked_from_session_id'] as String?,
      pendingApproval: json['pending_approval'] == null
          ? null
          : ApprovalRequest.fromJson(
              json['pending_approval'] as Map<String, dynamic>,
            ),
    );
  }
}

class SessionDetail {
  const SessionDetail({
    required this.session,
    this.gitStatus,
  });

  final SessionSummary session;
  final GitStatusDetail? gitStatus;

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final gitStatus = data['git_status'];
    return SessionDetail(
      session: SessionSummary.fromJson(data['session'] as Map<String, dynamic>),
      gitStatus: gitStatus == null
          ? null
          : GitStatusDetail.fromJson(gitStatus as Map<String, dynamic>),
    );
  }
}

class GitStatusDetail {
  const GitStatusDetail({
    required this.dirty,
    required this.staged,
    required this.unstaged,
    required this.untracked,
    this.stagedCount,
    this.unstagedCount,
    this.untrackedCount,
    this.changedCount,
    this.ahead,
    this.behind,
  });

  final bool dirty;
  final bool staged;
  final bool unstaged;
  final bool untracked;
  final int? stagedCount;
  final int? unstagedCount;
  final int? untrackedCount;
  final int? changedCount;
  final int? ahead;
  final int? behind;

  String get label {
    final parts = <String>[];
    final aheadCount = ahead;
    if (aheadCount != null && aheadCount > 0) {
      parts.add('ahead $aheadCount');
    }
    final behindCount = behind;
    if (behindCount != null && behindCount > 0) {
      parts.add('behind $behindCount');
    }
    final totalChanged = changedCount;
    if (totalChanged != null && totalChanged > 0) {
      parts.add('$totalChanged changed');
    } else if (dirty) {
      parts.add('dirty');
    }
    return parts.join(' · ');
  }

  factory GitStatusDetail.fromJson(Map<String, dynamic> json) {
    return GitStatusDetail(
      dirty: json['dirty'] as bool? ?? false,
      staged: json['staged'] as bool? ?? false,
      unstaged: json['unstaged'] as bool? ?? false,
      untracked: json['untracked'] as bool? ?? false,
      stagedCount: _readOptionalInt(json['staged_count']),
      unstagedCount: _readOptionalInt(json['unstaged_count']),
      untrackedCount: _readOptionalInt(json['untracked_count']),
      changedCount: _readOptionalInt(json['changed_count']),
      ahead: _readOptionalInt(json['ahead']),
      behind: _readOptionalInt(json['behind']),
    );
  }

  static int? _readOptionalInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  ChatMessage copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      role: parseMessageRole(json['role'] as String),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
