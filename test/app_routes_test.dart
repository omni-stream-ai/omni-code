import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/app_routes.dart';

void main() {
  group('AppRoutes', () {
    test('builds project and session paths using raw IDs', () {
      expect(AppRoutes.project('project-1'), '/projects/project-1');
      expect(
        AppRoutes.session('project-1', 'session-1'),
        '/projects/project-1/session-1',
      );
    });

    test('builds paths for IDs without project- prefix', () {
      expect(AppRoutes.project('alpha'), '/projects/alpha');
      expect(
        AppRoutes.session('alpha', 's-1'),
        '/projects/alpha/s-1',
      );
    });

    test('roundtrips project and session paths', () {
      final projectMatch = AppRoutes.parse('/projects/project-1');
      expect(projectMatch.kind, AppRouteKind.project);
      expect(projectMatch.projectId, 'project-1');

      final sessionMatch = AppRoutes.parse('/projects/project-1/session-1');
      expect(sessionMatch.kind, AppRouteKind.session);
      expect(sessionMatch.projectId, 'project-1');
      expect(sessionMatch.sessionId, 'session-1');
    });

    test('roundtrips IDs without project- prefix', () {
      final projectMatch = AppRoutes.parse('/projects/alpha');
      expect(projectMatch.kind, AppRouteKind.project);
      expect(projectMatch.projectId, 'alpha');

      final sessionMatch = AppRoutes.parse('/projects/alpha/s-1');
      expect(sessionMatch.kind, AppRouteKind.session);
      expect(sessionMatch.projectId, 'alpha');
      expect(sessionMatch.sessionId, 's-1');
    });

    test('parses root and settings paths', () {
      expect(AppRoutes.parse('/').kind, AppRouteKind.home);
      expect(AppRoutes.parse('/projects').kind, AppRouteKind.projects);
      expect(AppRoutes.parse('/settings').kind, AppRouteKind.settings);
    });

    test('parses legacy session paths with sessions segment', () {
      final sessionMatch = AppRoutes.parse(
        '/projects/project-1/sessions/session-1',
      );
      expect(sessionMatch.kind, AppRouteKind.session);
      expect(sessionMatch.projectId, 'project-1');
      expect(sessionMatch.sessionId, 'session-1');
    });

    test('decodes escaped path segments', () {
      final match = AppRoutes.parse(
        '/projects/abc%20def/session%2Fone',
      );
      expect(match.kind, AppRouteKind.session);
      expect(match.projectId, 'abc def');
      expect(match.sessionId, 'session/one');
    });
  });
}
