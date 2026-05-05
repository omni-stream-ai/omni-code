import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import 'project_detail_screen.dart';
import 'settings_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key, this.client});

  final BridgeClient? client;

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<ProjectSummary>? _projects;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;

  BridgeClient get _client => widget.client ?? bridgeClient;

  @override
  void initState() {
    super.initState();
    _projects = _client.peekProjects();
    _isLoading = _projects == null;
    unawaited(_loadProjects());
  }

  Future<void> _loadProjects({bool forceRefresh = false}) async {
    final latestCachedProjects = _client.peekProjects();
    final shouldRefreshFromNetwork =
        forceRefresh || latestCachedProjects != null || _projects != null;
    setState(() {
      _error = null;
      _projects = latestCachedProjects ?? _projects;
      if (_projects == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });
    try {
      final projects = await _client.listProjects(
        forceRefresh: shouldRefreshFromNetwork,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _reloadProjects() {
    return _loadProjects(forceRefresh: true);
  }

  String _formatProjectUpdatedAt(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).pushNamed(SettingsScreen.routeName);
              if (!mounted) {
                return;
              }
              setState(() {});
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        label: Text(l10n.newProject),
        icon: const Icon(Icons.create_new_folder_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: _reloadProjects,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_isRefreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.homeManageByProject,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.homeBridgeAddress(_client.baseUrl),
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.homeIntro,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.projectsTitle,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null &&
                (_projects == null || _projects!.isEmpty))
              _ErrorCard(
                message: l10n.loadProjectsFailed('$_error'),
                onRetry: _reloadProjects,
              )
            else if (_projects == null || _projects!.isEmpty)
              _EmptyCard(onCreateProject: _createProject)
            else
              ..._projects!.map(
                (project) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () async {
                      await Navigator.of(context).pushNamed(
                        ProjectDetailScreen.routeName,
                        arguments: project,
                      );
                      if (!mounted) {
                        return;
                      }
                      unawaited(_loadProjects());
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  project.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                l10n.projectCount(project.sessionCount),
                                style: const TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            project.rootPath,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.projectUpdatedAt(
                              _formatProjectUpdatedAt(project.updatedAt),
                            ),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _CreateProjectDialog(),
    );
    if (result == null) {
      return;
    }

    final project = await _client.createProject(
      name: result.$1,
      rootPath: result.$2,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushNamed(
      ProjectDetailScreen.routeName,
      arguments: project,
    );
    if (!mounted) {
      return;
    }
    await _reloadProjects();
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3F1D1D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onCreateProject});

  final Future<void> Function() onCreateProject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.noProjectsYet),
          const SizedBox(height: 8),
          Text(
            context.l10n.noProjectsHelp,
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onCreateProject,
            child: Text(context.l10n.createProject),
          ),
        ],
      ),
    );
  }
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
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
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      title: Text(context.l10n.newProject),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.l10n.projectName),
          ),
          const SizedBox(height: 12),
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
