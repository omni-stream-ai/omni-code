enum AgentKind { codex, claudecode, opencode, custom }

enum SessionStatus { idle, running, awaitingApproval, waiting, failed }

enum MessageRole { user, assistant, system }

enum ApprovalChoice {
  accept,
  acceptForSession,
  alwaysAllow,
  decline,
  cancel,
}

AgentKind parseAgentKind(String value) {
  switch (value) {
    case 'codex':
      return AgentKind.codex;
    case 'claude_code':
    case 'claudecode':
      return AgentKind.claudecode;
    case 'open_code':
    case 'opencode':
      return AgentKind.opencode;
    default:
      return AgentKind.custom;
  }
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

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.updatedAt,
    required this.sessionCount,
    this.lastSessionPreview,
  });

  final String id;
  final String name;
  final String rootPath;
  final DateTime updatedAt;
  final int sessionCount;
  final String? lastSessionPreview;

  ProjectSummary copyWith({
    String? id,
    String? name,
    String? rootPath,
    DateTime? updatedAt,
    int? sessionCount,
    String? lastSessionPreview,
  }) {
    return ProjectSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionCount: sessionCount ?? this.sessionCount,
      lastSessionPreview: lastSessionPreview ?? this.lastSessionPreview,
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
    );
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
    required this.agent,
    required this.briefReplyMode,
    required this.status,
    required this.updatedAt,
    required this.unreadCount,
    this.lastMessagePreview,
    this.pendingApproval,
  });

  final String id;
  final String projectId;
  final String title;
  final AgentKind agent;
  final bool briefReplyMode;
  final SessionStatus status;
  final DateTime updatedAt;
  final int unreadCount;
  final String? lastMessagePreview;
  final ApprovalRequest? pendingApproval;

  SessionSummary copyWith({
    String? id,
    String? projectId,
    String? title,
    AgentKind? agent,
    bool? briefReplyMode,
    SessionStatus? status,
    DateTime? updatedAt,
    int? unreadCount,
    String? lastMessagePreview,
    ApprovalRequest? pendingApproval,
    bool clearPendingApproval = false,
  }) {
    return SessionSummary(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      agent: agent ?? this.agent,
      briefReplyMode: briefReplyMode ?? this.briefReplyMode,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      pendingApproval:
          clearPendingApproval ? null : pendingApproval ?? this.pendingApproval,
    );
  }

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      title: json['title'] as String,
      agent: parseAgentKind(json['agent'] as String),
      briefReplyMode: json['brief_reply_mode'] as bool? ?? false,
      status: parseSessionStatus(json['status'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      unreadCount: json['unread_count'] as int,
      lastMessagePreview: json['last_message_preview'] as String?,
      pendingApproval: json['pending_approval'] == null
          ? null
          : ApprovalRequest.fromJson(
              json['pending_approval'] as Map<String, dynamic>,
            ),
    );
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
