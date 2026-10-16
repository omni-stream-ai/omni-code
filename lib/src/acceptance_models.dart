class AcceptanceInstallation {
  const AcceptanceInstallation({required this.phase, this.error});
  factory AcceptanceInstallation.fromJson(Map<String, dynamic> json) =>
      AcceptanceInstallation(
        phase: json['phase'] as String,
        error: json['error'] as String?,
      );
  final String phase;
  final String? error;
  bool get ready => phase == 'ready';
  bool get busy => const ['checking', 'preparing', 'verifying'].contains(phase);
}

class AcceptanceRun {
  const AcceptanceRun(
      {required this.id,
      required this.projectId,
      required this.revision,
      required this.command,
      required this.phase,
      required this.createdAt,
      this.error,
      this.controller,
      required this.artifacts,
      this.passed,
      this.notes});

  factory AcceptanceRun.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    return AcceptanceRun(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      revision: json['revision'] as String,
      command: json['command'] as String,
      phase: json['phase'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      error: json['error'] as String?,
      controller: json['controller'] as String?,
      artifacts: (json['artifacts'] as List<dynamic>)
          .map((value) =>
              AcceptanceArtifact.fromJson(value as Map<String, dynamic>))
          .toList(),
      passed: result?['passed'] as bool?,
      notes: result?['notes'] as String?,
    );
  }

  final String id, projectId, revision, command, phase;
  final DateTime createdAt;
  final String? error, controller, notes;
  final bool? passed;
  final List<AcceptanceArtifact> artifacts;
  bool get running => phase == 'running';
  bool get terminal => phase == 'completed' || phase == 'failed';
}

class AcceptanceArtifact {
  const AcceptanceArtifact(
      {required this.name, required this.contentType, required this.bytes});
  factory AcceptanceArtifact.fromJson(Map<String, dynamic> json) =>
      AcceptanceArtifact(
        name: json['name'] as String,
        contentType: json['content_type'] as String,
        bytes: json['bytes'] as int,
      );
  final String name, contentType;
  final int bytes;
}
