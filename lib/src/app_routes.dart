enum AppRouteKind { home, settings, project, session, unknown }

class AppRouteMatch {
  const AppRouteMatch._({
    required this.kind,
    this.projectId,
    this.sessionId,
  });

  const AppRouteMatch.home() : this._(kind: AppRouteKind.home);

  const AppRouteMatch.settings() : this._(kind: AppRouteKind.settings);

  const AppRouteMatch.project(String projectId)
      : this._(kind: AppRouteKind.project, projectId: projectId);

  const AppRouteMatch.session({
    required String projectId,
    required String sessionId,
  }) : this._(
          kind: AppRouteKind.session,
          projectId: projectId,
          sessionId: sessionId,
        );

  const AppRouteMatch.unknown() : this._(kind: AppRouteKind.unknown);

  final AppRouteKind kind;
  final String? projectId;
  final String? sessionId;
}

abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
  static const projects = '/projects';
  static const sessions = 'sessions';

  static String project(String projectId) {
    return '$projects/${Uri.encodeFull(projectId)}';
  }

  static String session(String projectId, String sessionId) {
    return '${project(projectId)}/${Uri.encodeFull(sessionId)}';
  }

  static AppRouteMatch parse(String? location) {
    final rawLocation = location?.trim();
    if (rawLocation == null || rawLocation.isEmpty) {
      return const AppRouteMatch.home();
    }

    final uri = Uri.tryParse(rawLocation);
    if (uri == null) {
      return const AppRouteMatch.unknown();
    }

    final path = uri.path.isEmpty ? home : uri.path;
    final segments = uri.pathSegments.toList();
    if (path == home || segments.isEmpty) {
      return const AppRouteMatch.home();
    }

    if (path == settings) {
      return const AppRouteMatch.settings();
    }

    if (segments.length == 1 && segments.first == 'projects') {
      return const AppRouteMatch.home();
    }

    if (segments.length == 2 && segments.first == 'projects') {
      return AppRouteMatch.project(Uri.decodeFull(segments[1]));
    }

    if (segments.length == 3 && segments.first == 'projects') {
      return AppRouteMatch.session(
        projectId: Uri.decodeFull(segments[1]),
        sessionId: Uri.decodeFull(segments[2]),
      );
    }

    if (segments.length == 4 &&
        segments.first == 'projects' &&
        segments[2] == sessions) {
      return AppRouteMatch.session(
        projectId: Uri.decodeFull(segments[1]),
        sessionId: Uri.decodeFull(segments[3]),
      );
    }

    return const AppRouteMatch.unknown();
  }
}
