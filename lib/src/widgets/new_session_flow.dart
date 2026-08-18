import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../screens/session_detail_screen.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'create_session_dialog.dart';

Future<void> startNewSessionFlow(
  BuildContext context, {
  BridgeClient? client,
  List<ProjectSummary>? initialProjects,
  ProjectSummary? initialProject,
  FutureOr<void> Function()? onSessionClosed,
}) async {
  final resolvedClient = client ?? bridgeClient;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  ProjectSummary? project = initialProject;
  if (project == null) {
    var projects = initialProjects ?? resolvedClient.peekProjects();
    if (projects == null) {
      try {
        projects = await resolvedClient.listProjects(forceRefresh: true);
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.loadProjectsFailed('$error'))),
        );
        return;
      }
    }

    if (!context.mounted) {
      return;
    }
    if (projects.isEmpty) {
      project = await _createProject(context, resolvedClient);
      if (project == null || !context.mounted) {
        return;
      }
    } else {
      final selection = await showDialog<_ProjectSelection>(
        context: context,
        builder: (context) => SelectProjectDialog(projects: projects!),
      );
      if (selection == null || !context.mounted) {
        return;
      }
      if (selection is ExistingProjectSelection) {
        project = selection.project;
      } else {
        project = await _createProject(context, resolvedClient);
        if (project == null || !context.mounted) {
          return;
        }
      }
    }
  }

  final sessionResult = await showDialog<CreateSessionDialogResult>(
    context: context,
    builder: (context) => CreateSessionDialog(
      client: resolvedClient,
      initialProviderId: appSettingsController
          .settings.lastSelectedProviderByProject[project!.id],
    ),
  );
  if (sessionResult == null || !context.mounted) {
    return;
  }

  final savedProviderSelections = Map<String, String?>.from(
    appSettingsController.settings.lastSelectedProviderByProject,
  )..[project.id] = sessionResult.$3;
  unawaited(
    appSettingsController.save(
      appSettingsController.settings.copyWith(
        lastSelectedAgent: sessionResult.$2,
        lastSelectedProviderByProject: savedProviderSelections,
      ),
    ),
  );

  final initialTitle = sessionResult.$1?.trim();
  final clientSessionId = BridgeClient.newClientSessionId();
  final placeholderSession = SessionSummary(
    id: clientSessionId,
    projectId: project.id,
    title: (initialTitle != null && initialTitle.isNotEmpty)
        ? initialTitle
        : l10n.newSession,
    agentId: sessionResult.$2,
    briefReplyMode: appSettingsController.settings.compressAssistantReplies,
    status: SessionStatus.idle,
    updatedAt: DateTime.now(),
    unreadCount: 0,
    providerId: sessionResult.$3,
    model: sessionResult.$4,
  );
  final sessionFuture = resolvedClient.createSession(
    projectId: project.id,
    title: sessionResult.$1,
    agent: sessionResult.$2,
    clientSessionId: clientSessionId,
    briefReplyMode: appSettingsController.settings.compressAssistantReplies,
    providerId: sessionResult.$3,
    model: sessionResult.$4,
  );

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionDetailScreen(
        session: placeholderSession,
        sessionInitializer: sessionFuture,
      ),
    ),
  );
  await onSessionClosed?.call();
}

Future<ProjectSummary?> _createProject(
  BuildContext context,
  BridgeClient client,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => const CreateProjectDialog(),
  );
  if (result == null) {
    return null;
  }
  return client.createProject(name: result.$1, rootPath: result.$2);
}

sealed class _ProjectSelection {}

class ExistingProjectSelection extends _ProjectSelection {
  ExistingProjectSelection(this.project);

  final ProjectSummary project;
}

class CreateProjectSelection extends _ProjectSelection {}

class SelectProjectDialog extends StatelessWidget {
  const SelectProjectDialog({super.key, required this.projects});

  final List<ProjectSummary> projects;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.selectProject),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: projects.length + 1,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: AppColors.outlineFor(brightness),
          ),
          itemBuilder: (context, index) {
            if (index == projects.length) {
              return ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(context.l10n.createNewProject),
                onTap: () =>
                    Navigator.of(context).pop(CreateProjectSelection()),
              );
            }
            final project = projects[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                project.rootPath,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(
                context,
              ).pop(ExistingProjectSelection(project)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}

class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: AppColors.panelFor(brightness),
      title: Text(context.l10n.newProject),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.l10n.projectName),
          ),
          const SizedBox(height: AppSpacing.stack),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(labelText: context.l10n.localPath),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final path = _pathController.text.trim();
            if (name.isEmpty || path.isEmpty) {
              return;
            }
            Navigator.of(context).pop((name, path));
          },
          child: Text(context.l10n.createProject),
        ),
      ],
    );
  }
}
