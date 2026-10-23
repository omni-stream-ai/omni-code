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
      this.notes,
      this.automation = 'pending',
      this.automatic = false,
      this.automationProgress = '',
      this.checklist = const [],
      this.autoVerdict,
      this.automationError,
      this.requirements,
      this.sessionId,
      this.requirementBrief,
      this.testPlan,
      this.planMessages = const [],
      this.environment,
      this.environmentReused = false});

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
      automation: json['automation'] as String? ?? 'pending',
      automatic: json['automatic'] as bool? ?? false,
      automationProgress: json['automation_progress'] as String? ?? '',
      checklist: (json['checklist'] as List<dynamic>? ?? const [])
          .map((value) =>
              AcceptanceCheck.fromJson(value as Map<String, dynamic>))
          .toList(),
      autoVerdict: json['auto_verdict'] == null
          ? null
          : AcceptanceVerdict.fromJson(
              json['auto_verdict'] as Map<String, dynamic>),
      automationError: json['automation_error'] as String?,
      requirements: json['requirements'] as String?,
      sessionId: json['session_id'] as String?,
      environment: json['environment'] == null
          ? null
          : AcceptanceEnvironment.fromJson(
              json['environment'] as Map<String, dynamic>),
      environmentReused: json['environment_reused'] as bool? ?? false,
      requirementBrief: json['requirement_brief'] == null
          ? null
          : AcceptanceRequirementBrief.fromJson(
              json['requirement_brief'] as Map<String, dynamic>),
      testPlan: json['test_plan'] == null
          ? null
          : AcceptanceTestPlan.fromJson(
              json['test_plan'] as Map<String, dynamic>),
      planMessages: (json['plan_messages'] as List<dynamic>? ?? const [])
          .map((item) =>
              AcceptancePlanMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id, projectId, revision, command, phase;
  final DateTime createdAt;
  final String? error, controller, notes;
  final bool? passed;
  final List<AcceptanceArtifact> artifacts;
  final String automation, automationProgress;
  final bool automatic;
  final List<AcceptanceCheck> checklist;
  final AcceptanceVerdict? autoVerdict;
  final String? automationError, requirements;
  final String? sessionId;
  final AcceptanceRequirementBrief? requirementBrief;
  final AcceptanceTestPlan? testPlan;
  final List<AcceptancePlanMessage> planMessages;
  final AcceptanceEnvironment? environment;
  final bool environmentReused;
  bool get running => phase == 'running';
  bool get terminal => phase == 'completed' || phase == 'failed';
}

class AcceptanceTestPlan {
  const AcceptanceTestPlan(
      {required this.version,
      required this.cases,
      this.notes = '',
      this.approvedVersion});
  factory AcceptanceTestPlan.fromJson(Map<String, dynamic> json) =>
      AcceptanceTestPlan(
        version: json['version'] as int,
        cases: (json['cases'] as List<dynamic>)
            .map((item) =>
                AcceptanceTestCase.fromJson(item as Map<String, dynamic>))
            .toList(),
        notes: json['notes'] as String? ?? '',
        approvedVersion: json['approved_version'] as int?,
      );
  final int version;
  final List<AcceptanceTestCase> cases;
  final String notes;
  final int? approvedVersion;
  bool get approved => approvedVersion == version;
}

class AcceptanceTestCase {
  const AcceptanceTestCase(
      {required this.id,
      required this.title,
      required this.steps,
      required this.expected});
  factory AcceptanceTestCase.fromJson(Map<String, dynamic> json) =>
      AcceptanceTestCase(
        id: json['id'] as String,
        title: json['title'] as String,
        steps: (json['steps'] as List<dynamic>).cast<String>(),
        expected: json['expected'] as String,
      );
  final String id, title, expected;
  final List<String> steps;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'steps': steps, 'expected': expected};
}

class AcceptancePlanMessage {
  const AcceptancePlanMessage({required this.role, required this.content});
  factory AcceptancePlanMessage.fromJson(Map<String, dynamic> json) =>
      AcceptancePlanMessage(
          role: json['role'] as String, content: json['content'] as String);
  final String role, content;
}

class AcceptanceEnvironmentConfig {
  const AcceptanceEnvironmentConfig(
      {this.mode = 'auto', this.dockerfile = '', this.image = ''});
  factory AcceptanceEnvironmentConfig.fromJson(Map<String, dynamic> json) =>
      AcceptanceEnvironmentConfig(
        mode: json['mode'] as String? ?? 'auto',
        dockerfile: json['dockerfile'] as String? ?? '',
        image: json['image'] as String? ?? '',
      );
  final String mode, dockerfile, image;
  Map<String, dynamic> toJson() =>
      {'mode': mode, 'dockerfile': dockerfile, 'image': image};
}

class AcceptanceEnvironment {
  const AcceptanceEnvironment(
      {required this.id,
      required this.name,
      required this.phase,
      this.description = '',
      this.progress = '',
      this.dockerfile = '',
      this.log = '',
      this.imageId,
      this.error});
  factory AcceptanceEnvironment.fromJson(Map<String, dynamic> json) =>
      AcceptanceEnvironment(
        id: json['id'] as String,
        name: json['name'] as String,
        phase: json['phase'] as String,
        description: json['description'] as String? ?? '',
        progress: json['progress'] as String? ?? '',
        dockerfile: json['dockerfile'] as String? ?? '',
        log: json['log'] as String? ?? '',
        imageId: json['image_id'] as String?,
        error: json['error'] as String?,
      );
  final String id, name, phase, description, progress, dockerfile, log;
  final String? imageId, error;
  bool get busy => !const ['ready', 'failed'].contains(phase);
}

class AcceptanceEnvironmentImage {
  const AcceptanceEnvironmentImage({required this.name, required this.imageId});
  factory AcceptanceEnvironmentImage.fromJson(Map<String, dynamic> json) =>
      AcceptanceEnvironmentImage(
          name: json['name'] as String, imageId: json['image_id'] as String);
  final String name, imageId;
}

class AcceptanceEnvironmentSettings {
  const AcceptanceEnvironmentSettings(
      {this.config = const AcceptanceEnvironmentConfig(),
      this.current,
      this.available = const []});
  factory AcceptanceEnvironmentSettings.fromJson(Map<String, dynamic> json) =>
      AcceptanceEnvironmentSettings(
        config: AcceptanceEnvironmentConfig.fromJson(
            json['config'] as Map<String, dynamic>? ?? const {}),
        current: json['current'] == null
            ? null
            : AcceptanceEnvironment.fromJson(
                json['current'] as Map<String, dynamic>),
        available: (json['available'] as List<dynamic>? ?? const [])
            .map((item) => AcceptanceEnvironmentImage.fromJson(
                item as Map<String, dynamic>))
            .toList(),
      );
  final AcceptanceEnvironmentConfig config;
  final AcceptanceEnvironment? current;
  final List<AcceptanceEnvironmentImage> available;
}

class AcceptanceRequirementBrief {
  const AcceptanceRequirementBrief({
    required this.requirements,
    required this.sourceMessageCount,
    this.notes = '',
  });
  factory AcceptanceRequirementBrief.fromJson(Map<String, dynamic> json) =>
      AcceptanceRequirementBrief(
        requirements: (json['requirements'] as List<dynamic>? ?? const [])
            .map((item) =>
                AcceptanceRequirement.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        sourceMessageCount: json['source_message_count'] as int? ?? 0,
        notes: json['notes'] as String? ?? '',
      );
  final List<AcceptanceRequirement> requirements;
  final int sourceMessageCount;
  final String notes;
}

class AcceptanceRequirement {
  const AcceptanceRequirement({required this.id, required this.description});
  factory AcceptanceRequirement.fromJson(Map<String, dynamic> json) =>
      AcceptanceRequirement(
        id: json['id'] as String,
        description: json['description'] as String,
      );
  final String id, description;
}

class AcceptanceCheck {
  const AcceptanceCheck(
      {required this.id,
      required this.title,
      required this.status,
      this.description = '',
      this.assertion = '',
      this.notes = '',
      this.evidence = const []});
  factory AcceptanceCheck.fromJson(Map<String, dynamic> json) =>
      AcceptanceCheck(
          id: json['id'] as String,
          title: json['title'] as String,
          description: json['description'] as String? ?? '',
          assertion: json['assertion'] as String? ?? '',
          status: json['status'] as String? ?? 'pending',
          notes: json['notes'] as String? ?? '',
          evidence:
              (json['evidence'] as List<dynamic>? ?? const []).cast<String>());
  final String id, title, description, assertion, status, notes;
  final List<String> evidence;
}

class AcceptanceVerdict {
  const AcceptanceVerdict(
      {required this.passed, required this.notes, required this.checks});
  factory AcceptanceVerdict.fromJson(Map<String, dynamic> json) =>
      AcceptanceVerdict(
          passed: json['passed'] as bool? ?? false,
          notes: json['notes'] as String? ?? '',
          checks: (json['checks'] as List<dynamic>? ?? const [])
              .map((value) => AcceptanceCheckVerdict.fromJson(
                  value as Map<String, dynamic>))
              .toList());
  final bool passed;
  final String notes;
  final List<AcceptanceCheckVerdict> checks;
}

class AcceptanceCheckVerdict {
  const AcceptanceCheckVerdict(
      {required this.id, required this.passed, required this.notes});
  factory AcceptanceCheckVerdict.fromJson(Map<String, dynamic> json) =>
      AcceptanceCheckVerdict(
          id: json['id'] as String,
          passed: json['passed'] as bool? ?? false,
          notes: json['notes'] as String? ?? '');
  final String id;
  final bool passed;
  final String notes;
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
