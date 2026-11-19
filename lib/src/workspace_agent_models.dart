import 'models.dart';

class WorkspaceProjectContext {
  const WorkspaceProjectContext({
    required this.project,
    this.gitStatus,
    this.branch,
    this.commitHead,
    this.commitSubject,
    this.sessions = const [],
  });

  factory WorkspaceProjectContext.fromJson(Map<String, dynamic> json) {
    final project = ProjectSummary.fromJson(
        Map<String, dynamic>.from(json['project'] as Map));
    final git = json['git_status'] as Map?;
    final commit = json['commit'] as Map?;
    return WorkspaceProjectContext(
      project: project,
      gitStatus: git == null
          ? null
          : GitStatusDetail.fromJson(Map<String, dynamic>.from(git)),
      branch: git?['branch'] as String? ?? project.gitBranch,
      commitHead: commit?['head'] as String?,
      commitSubject: commit?['subject'] as String?,
      sessions: (json['sessions'] as List? ?? [])
          .whereType<Map>()
          .map((session) => Map<String, dynamic>.from(session))
          .toList(),
    );
  }

  final ProjectSummary project;
  final GitStatusDetail? gitStatus;
  final String? branch, commitHead, commitSubject;
  final List<Map<String, dynamic>> sessions;
}

class WorkspaceProject {
  WorkspaceProject.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String? ?? '',
        iconDataUri = json['icon_data_uri'] as String?;
  final String id, name;
  final String? iconDataUri;
}

class AgentAnalysisScope {
  const AgentAnalysisScope(
      {this.includeOtherSessions = false,
      this.recentDays = 5,
      this.maxSessions = 15});
  final bool includeOtherSessions;
  final int recentDays, maxSessions;
  factory AgentAnalysisScope.fromJson(Map<String, dynamic> json) =>
      AgentAnalysisScope(
        includeOtherSessions: json['include_other_sessions'] as bool? ?? false,
        recentDays: json['recent_days'] as int? ?? 5,
        maxSessions: json['max_sessions'] as int? ?? 15,
      );
  Map<String, dynamic> toJson() => {
        'include_other_sessions': includeOtherSessions,
        'recent_days': recentDays,
        'max_sessions': maxSessions
      };
}

class WorkspaceTaskGroup {
  WorkspaceTaskGroup.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        title = json['title'] as String,
        summary = json['summary'] as String? ?? '';
  final String id, title, summary;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'summary': summary};
}

class WorkspaceTask {
  WorkspaceTask.fromJson(Map<String, dynamic> json)
      : sessionId = json['session_id'] as String,
        projectId = json['project_id'] as String,
        sessionTitle = json['session_title'] as String? ?? '',
        updatedAt = DateTime.tryParse(json['updated_at'] as String? ?? ''),
        createdAt =
            DateTime.tryParse(json['task']['created_at'] as String? ?? ''),
        taskUpdatedAt =
            DateTime.tryParse(json['task']['updated_at'] as String? ?? ''),
        completedAt =
            DateTime.tryParse(json['task']['completed_at'] as String? ?? ''),
        group = json['task']['group'] is Map
            ? WorkspaceTaskGroup.fromJson(
                Map<String, dynamic>.from(json['task']['group'] as Map))
            : null,
        archived = json['archived'] == true,
        stale = json['stale'] == true,
        truncated = json['truncated'] == true,
        id = json['task']['id'] as String,
        title = json['task']['title'] as String,
        summary = json['task']['summary'] as String,
        status = json['task']['status'] as String;
  final String id, sessionId, projectId, sessionTitle, title, summary, status;
  final WorkspaceTaskGroup? group;
  final bool archived, stale, truncated;
  final DateTime? updatedAt, createdAt, taskUpdatedAt, completedAt;
  bool matchesQuery(String query, {String projectName = ''}) {
    final text = '$title $summary $sessionTitle $projectName '
            '${group?.title ?? ''} ${group?.summary ?? ''}'
        .toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  bool get isOpen => status != 'completed' && status != 'cancelled';
  DateTime? get lastUpdatedAt => taskUpdatedAt ?? updatedAt;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'project_id': projectId,
        'session_title': sessionTitle,
        'updated_at': updatedAt?.toIso8601String(),
        'archived': archived,
        'stale': stale,
        'truncated': truncated,
        'task': <String, dynamic>{
          'id': id,
          'title': title,
          'summary': summary,
          'status': status,
          'created_at': createdAt?.toIso8601String(),
          'updated_at': taskUpdatedAt?.toIso8601String(),
          'completed_at': completedAt?.toIso8601String(),
          'group': group?.toJson()
        },
      };

  WorkspaceTask withState(String value, DateTime now) {
    final json = toJson();
    json['archived'] = false;
    (json['task'] as Map<String, dynamic>).addAll({
      'status': value,
      'updated_at': now.toIso8601String(),
      'completed_at': value == 'completed' || value == 'cancelled'
          ? now.toIso8601String()
          : null
    });
    return WorkspaceTask.fromJson(json);
  }

  Duration? elapsedAt(DateTime now) {
    final start = createdAt;
    final end = isOpen ? now : completedAt ?? taskUpdatedAt;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }
}

class WorkspaceTaskBundle {
  WorkspaceTaskBundle(this.members);
  final List<WorkspaceTask> members;
  WorkspaceTask get primary => members.first;
  WorkspaceTask get latestSessionTask => members.reduce((latest, task) {
        final currentTime = latest.updatedAt ?? latest.lastUpdatedAt;
        final candidateTime = task.updatedAt ?? task.lastUpdatedAt;
        return candidateTime != null &&
                (currentTime == null || candidateTime.isAfter(currentTime))
            ? task
            : latest;
      });
  bool get isGroup => members.length > 1 && primary.group != null;
  Object get key => isGroup
      ? (primary.projectId, 'group', primary.group!.id)
      : (primary.sessionId, primary.id);

  WorkspaceTask get displayTask {
    if (!isGroup) return primary;
    final open = members.where((task) => task.isOpen).toList();
    final status = open.isEmpty
        ? (members.every((task) => task.status == 'cancelled')
            ? 'cancelled'
            : 'completed')
        : ['blocked', 'in_progress', 'pending', 'awaiting_review'].firstWhere(
            (status) => open.any((task) => task.status == status),
            orElse: () => 'pending');
    final starts = members
        .map((task) => task.createdAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final updates = members
        .map((task) => task.lastUpdatedAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final ends = members
        .map((task) => task.completedAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final json = primary.toJson();
    (json['task'] as Map<String, dynamic>).addAll({
      'title': primary.group!.title,
      'summary': primary.group!.summary,
      'status': status,
      'created_at': starts.length == members.length
          ? starts.first.toIso8601String()
          : null,
      'updated_at': updates.lastOrNull?.toIso8601String(),
      'completed_at': open.isEmpty ? ends.lastOrNull?.toIso8601String() : null
    });
    return WorkspaceTask.fromJson(json);
  }

  static List<WorkspaceTaskBundle> fromTasks(List<WorkspaceTask> tasks) {
    final groups = <Object, List<WorkspaceTask>>{};
    for (final task in tasks) {
      final key = task.group == null
          ? (task.sessionId, task.id)
          : (task.projectId, 'group', task.group!.id);
      groups.putIfAbsent(key, () => []).add(task);
    }
    return groups.values.map(WorkspaceTaskBundle.new).toList();
  }
}

class WorkspaceAgentSnapshot {
  WorkspaceAgentSnapshot.fromJson(Map<String, dynamic> json)
      : projects = {
          for (final entry in json['projects'] as List? ?? [])
            entry['id'] as String:
                WorkspaceProject.fromJson(entry as Map<String, dynamic>),
        },
        scope =
            AgentAnalysisScope.fromJson(json['scope'] as Map<String, dynamic>),
        tasks = _tasksByLatestUpdate(json['tasks'] as List),
        selectedSessions = json['selected_sessions'] as int,
        cachedSessions = json['cached_sessions'] as int,
        participatedSessions = json['participated_sessions'] as int? ?? 0,
        externalSessions = json['external_sessions'] as int? ?? 0,
        running = json['running'] == true,
        errors = Map<String, dynamic>.from(json['errors'] as Map? ?? {}),
        chat = (json['chat'] as List? ?? []).cast<Map<String, dynamic>>();
  final Map<String, WorkspaceProject> projects;
  final AgentAnalysisScope scope;
  final List<WorkspaceTask> tasks;
  final int selectedSessions, cachedSessions;
  final int participatedSessions, externalSessions;
  final bool running;
  final Map<String, dynamic> errors;
  final List<Map<String, dynamic>> chat;
}

List<WorkspaceTask> _tasksByLatestUpdate(List entries) {
  return sortWorkspaceTasks(entries
      .map((entry) => WorkspaceTask.fromJson(entry as Map<String, dynamic>)));
}

List<WorkspaceTask> sortWorkspaceTasks(Iterable<WorkspaceTask> entries) {
  final tasks = entries.indexed.map((entry) => (entry.$1, entry.$2)).toList();
  tasks.sort((a, b) {
    final left = a.$2.lastUpdatedAt;
    final right = b.$2.lastUpdatedAt;
    final comparison = left == null
        ? (right == null ? 0 : 1)
        : right == null
            ? -1
            : right.compareTo(left);
    return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
  });
  return tasks.map((entry) => entry.$2).toList();
}
