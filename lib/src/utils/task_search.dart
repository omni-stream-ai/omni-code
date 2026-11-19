import 'package:flutter/material.dart';
import '../app_routes.dart';
import '../bridge_client.dart';
import '../workspace_agent_models.dart';
import '../widgets/app_snack_bar.dart';

String taskSearchText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String taskSearchStatus(BuildContext context, WorkspaceTask task) {
  final status = switch (task.status) {
    'completed' => taskSearchText(context, '已完成', 'Completed'),
    'cancelled' => taskSearchText(context, '已取消', 'Cancelled'),
    'awaiting_review' => taskSearchText(context, '待验收', 'Awaiting review'),
    'blocked' => taskSearchText(context, '待解决', 'Blocked'),
    'in_progress' => taskSearchText(context, '进行中', 'In progress'),
    _ => taskSearchText(context, '待继续', 'Pending'),
  };
  return '${task.isOpen && !task.archived ? taskSearchText(context, '待办', 'Open') : taskSearchText(context, '历史', 'History')} · $status';
}

Future<void> openTaskSearchResult(
    BuildContext context, BridgeClient client, WorkspaceTask task) async {
  try {
    final detail = await client.getSession(task.sessionId);
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(
        AppRoutes.session(task.projectId, task.sessionId),
        arguments: detail.session);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(AppSnackBar(
          isError: true,
          content: Text(taskSearchText(context, '无法打开关联会话，请重试。',
              'Could not open the conversation. Please retry.'))));
    }
  }
}
