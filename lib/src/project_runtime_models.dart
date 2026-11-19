import 'acceptance_models.dart';

class ProjectRuntime {
  ProjectRuntime.fromJson(Map<String, dynamic> json)
      : directory = json['directory'] as String,
        location = json['location'] as String,
        phase = json['phase'] as String,
        command = json['command'] as String,
        workingDirectory = json['working_directory'] as String,
        error = json['error'] as String?,
        acceptanceRunId = json['acceptance_run_id'] as String?,
        revision = json['revision'] as String?,
        leaseSessionId =
            (json['lease'] as Map<String, dynamic>?)?['session_id'] as String?,
        leaseExpiresAt = DateTime.tryParse((json['lease']
                as Map<String, dynamic>?)?['expires_at'] as String? ??
            '');
  final String directory, location, phase, command, workingDirectory;
  final String? error, acceptanceRunId, revision, leaseSessionId;
  final DateTime? leaseExpiresAt;
  bool get active => !const ['stopped', 'failed'].contains(phase);
  bool get occupied =>
      leaseSessionId != null &&
      leaseExpiresAt != null &&
      leaseExpiresAt!.isAfter(DateTime.now());
}

class ProjectRuntimeOverview {
  ProjectRuntimeOverview.fromJson(Map<String, dynamic> json)
      : names = Map<String, String>.from(
            (json['preferences'] as Map<String, dynamic>?)?['names'] as Map? ??
                {}),
        locations = Map<String, String>.from((json['preferences']
                as Map<String, dynamic>?)?['locations'] as Map? ??
            {}),
        targets = (json['targets'] as List<dynamic>? ?? [])
            .map((item) =>
                AcceptanceBuildTarget.fromJson(item as Map<String, dynamic>))
            .toList(),
        runtimes = (json['runtimes'] as List<dynamic>? ?? [])
            .map(
                (item) => ProjectRuntime.fromJson(item as Map<String, dynamic>))
            .toList();
  final Map<String, String> locations, names;
  final List<AcceptanceBuildTarget> targets;
  final List<ProjectRuntime> runtimes;
}
