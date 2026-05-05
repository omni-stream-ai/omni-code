import 'dart:convert';

import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('BridgeClient project ordering', () {
    test('sortProjectsForDisplay orders projects by updatedAt descending', () {
      final older = _project(
        id: 'older',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      final newer = _project(
        id: 'newer',
        updatedAt: DateTime(2026, 5, 5, 11),
      );

      final sorted = BridgeClient.sortProjectsForDisplay([older, newer]);

      expect(sorted.map((item) => item.id).toList(), ['newer', 'older']);
    });

    test('syncSessionSummary promotes active project to first', () {
      final client = BridgeClient();
      final older = _project(
        id: 'older',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      final newer = _project(
        id: 'newer',
        updatedAt: DateTime(2026, 5, 5, 11),
      );

      client.debugSeedProjects([older, newer]);
      client.syncSessionSummary(
        _session(
          id: 'session-1',
          projectId: 'older',
          updatedAt: DateTime(2026, 5, 5, 12),
          lastMessagePreview: 'latest activity',
        ),
      );

      final projects = client.peekProjects();
      expect(projects, isNotNull);
      expect(projects!.map((item) => item.id).toList(), ['older', 'newer']);
      expect(projects.first.lastSessionPreview, 'latest activity');
      expect(projects.first.sessionCount, 1);
      expect(projects.first.updatedAt, DateTime(2026, 5, 5, 12));
    });

    test(
      'listProjects keeps newer local project state when network is older',
      () async {
        final client = BridgeClient(
          httpClient: _FakeHttpClient((request) async {
            expect(request.url.path, '/projects');
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'alpha',
                    'name': 'Alpha',
                    'root_path': '/tmp/alpha',
                    'updated_at': '2026-05-05T11:00:00.000',
                    'session_count': 0,
                    'last_session_preview': null,
                  },
                  {
                    'id': 'beta',
                    'name': 'Beta',
                    'root_path': '/tmp/beta',
                    'updated_at': '2026-05-05T10:00:00.000',
                    'session_count': 0,
                    'last_session_preview': null,
                  },
                ],
              }),
              200,
            );
          }),
        );

        client.debugSeedProjects([
          _project(
            id: 'alpha',
            updatedAt: DateTime(2026, 5, 5, 11),
          ),
          _project(
            id: 'beta',
            updatedAt: DateTime(2026, 5, 5, 10),
          ),
        ]);
        client.syncSessionSummary(
          _session(
            id: 'session-beta',
            projectId: 'beta',
            updatedAt: DateTime(2026, 5, 5, 12),
            lastMessagePreview: 'latest activity',
          ),
        );

        final projects = await client.listProjects(forceRefresh: true);

        expect(projects.map((item) => item.id).toList(), ['beta', 'alpha']);
        expect(projects.first.updatedAt, DateTime(2026, 5, 5, 12));
        expect(projects.first.lastSessionPreview, 'latest activity');
      },
    );
  });
}

ProjectSummary _project({
  required String id,
  required DateTime updatedAt,
}) {
  return ProjectSummary(
    id: id,
    name: id,
    rootPath: '/tmp/$id',
    updatedAt: updatedAt,
    sessionCount: 0,
    lastSessionPreview: null,
  );
}

SessionSummary _session({
  required String id,
  required String projectId,
  required DateTime updatedAt,
  String? lastMessagePreview,
}) {
  return SessionSummary(
    id: id,
    projectId: projectId,
    title: id,
    agent: AgentKind.codex,
    briefReplyMode: false,
    status: SessionStatus.idle,
    updatedAt: updatedAt,
    unreadCount: 0,
    lastMessagePreview: lastMessagePreview,
    pendingApproval: null,
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
