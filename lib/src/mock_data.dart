import 'models.dart';

final mockSessions = <SessionSummary>[
  SessionSummary(
    id: 'session-build',
    projectId: 'project-ios',
    title: 'iOS 构建排障',
    agent: AgentKind.claudecode,
    briefReplyMode: false,
    status: SessionStatus.running,
    updatedAt: DateTime(2026, 4, 20, 15, 0),
    unreadCount: 1,
    lastMessagePreview: '我已经定位到签名阶段失败，下一步检查 Provisioning Profile。',
  ),
  SessionSummary(
    id: 'session-release',
    projectId: 'project-release',
    title: '发版检查单',
    agent: AgentKind.codex,
    briefReplyMode: false,
    status: SessionStatus.waiting,
    updatedAt: DateTime(2026, 4, 20, 14, 52),
    unreadCount: 0,
    lastMessagePreview: '等待确认是否同步更新 Android 版本号和 changelog。',
  ),
];

final mockMessages = <String, List<ChatMessage>>{
  'session-build': [
    ChatMessage(
      id: 'm1',
      sessionId: 'session-build',
      role: MessageRole.user,
      content: '帮我看一下 iOS 打包为什么失败，并用中文总结。',
      createdAt: DateTime(2026, 4, 20, 14, 58),
    ),
    ChatMessage(
      id: 'm2',
      sessionId: 'session-build',
      role: MessageRole.assistant,
      content:
          '目前已经定位到签名阶段失败。Release 配置缺少有效的 Provisioning Profile，而且 bundle identifier 和证书不匹配。',
      createdAt: DateTime(2026, 4, 20, 14, 59),
    ),
  ],
};
