import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/project_avatar.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';
import 'package:omni_code/src/workspace_agent_models.dart';

void main() {
  const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M0 0h16v16H0z" fill="#123456"/></svg>';
  final icon = 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
  final projectJson = <String, dynamic>{
    'id': 'project-1',
    'name': 'Omni',
    'root_path': '/project',
    'updated_at': '2026-11-13T10:00:00Z',
    'session_count': 1,
  };
  test('project icons are optional and survive metadata updates', () {
    expect(ProjectSummary.fromJson(projectJson).iconDataUri, isNull);
    final project =
        ProjectSummary.fromJson({...projectJson, 'icon_data_uri': icon});
    expect(project.copyWith(sessionCount: 2).iconDataUri, icon);
    expect(project.copyWith(clearIcon: true).iconDataUri, isNull);
  });
  testWidgets(
      'initial fallback handles whitespace, Chinese and emoji graphemes',
      (tester) async {
    for (final entry in {
      '  omni ': 'O',
      '项目': '项',
      '👩‍💻 Code': '👩‍💻',
      '  ': '?'
    }.entries) {
      await tester
          .pumpWidget(MaterialApp(home: ProjectAvatar(name: entry.key)));
      expect(find.text(entry.value), findsOneWidget);
    }
  });
  testWidgets('SVG is displayed and invalid data falls back', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: ProjectAvatar(name: 'Omni', iconDataUri: icon)));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('O'), findsNothing);
    for (final invalid in [
      'https://example.com/icon.png',
      'data:image/png;base64,invalid!',
      'data:text/html;base64,PGgxPg=='
    ]) {
      await tester.pumpWidget(
          MaterialApp(home: ProjectAvatar(name: 'Omni', iconDataUri: invalid)));
      await tester.pumpAndSettle();
      expect(find.text('O'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('corrupt raster falls back after decoder failure',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ProjectAvatar(
            name: 'Omni', iconDataUri: 'data:image/png;base64,YmFk')));
    await tester.pumpAndSettle();
    expect(find.text('O'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final homeSurface in [false, true]) {
    testWidgets(
        'tasks resolve project artwork from snapshot (home: $homeSurface)',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = {
        'scope': <String, dynamic>{},
        'selected_sessions': 1,
        'cached_sessions': 1,
        'projects': [
          {'id': 'project-1', 'name': 'Omni', 'icon_data_uri': icon}
        ],
        'tasks': [
          {
            'session_id': 'session-1',
            'project_id': 'project-1',
            'task': {
              'id': 'task-1',
              'title': 'Ship project icons',
              'summary': 'Show project identity',
              'status': 'in_progress'
            }
          }
        ],
      };
      final client = BridgeClient(
          httpClient: MockClient((request) async => http.Response(
                jsonEncode({
                  'data': request.url.path.endsWith('/analyze')
                      ? {'running': false}
                      : data
                }),
                200,
                headers: {'content-type': 'application/json'},
              )));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkspaceAgentPanel(
        client: client,
        homeSurface: homeSurface,
        sessionId: homeSurface ? null : 'session-1',
      )))));
      await tester.pumpAndSettle();
      final avatar = tester.widget<ProjectAvatar>(find.byType(ProjectAvatar));
      expect(avatar.name, 'Omni');
      expect(avatar.iconDataUri, icon);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
          WorkspaceAgentSnapshot.fromJson({...data}..remove('projects'))
              .projects,
          isEmpty);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }
}
