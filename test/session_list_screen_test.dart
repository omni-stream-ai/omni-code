import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/project_detail_screen.dart';
import 'package:omni_code/src/screens/session_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'active project moves to the first position after returning to list',
    (tester) async {
      final client = BridgeClient();
      final alpha = _project(
        id: 'alpha',
        name: 'Alpha',
        updatedAt: DateTime(2026, 5, 5, 11),
      );
      final beta = _project(
        id: 'beta',
        name: 'Beta',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      client.debugSeedProjects([alpha, beta]);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionListScreen(client: client),
          onGenerateRoute: (settings) {
            if (settings.name == ProjectDetailScreen.routeName) {
              final project = settings.arguments! as ProjectSummary;
              return MaterialPageRoute<void>(
                builder: (_) => _FakeProjectDetailScreen(
                  client: client,
                  project: project,
                ),
              );
            }
            return null;
          },
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_projectNames(tester), ['Alpha', 'Beta']);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.text('模拟项目详情'), findsOneWidget);
      await tester.tap(find.text('触发活动并返回'));
      await tester.pumpAndSettle();

      expect(_projectNames(tester), ['Beta', 'Alpha']);
    },
  );
}

List<String> _projectNames(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .where((text) => text == 'Alpha' || text == 'Beta')
      .toList();
}

ProjectSummary _project({
  required String id,
  required String name,
  required DateTime updatedAt,
}) {
  return ProjectSummary(
    id: id,
    name: name,
    rootPath: '/tmp/$id',
    updatedAt: updatedAt,
    sessionCount: 0,
    lastSessionPreview: null,
  );
}

class _FakeProjectDetailScreen extends StatelessWidget {
  const _FakeProjectDetailScreen({
    required this.client,
    required this.project,
  });

  final BridgeClient client;
  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模拟项目详情')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            client.syncSessionSummary(
              SessionSummary(
                id: 'session-${project.id}',
                projectId: project.id,
                title: 'session-${project.id}',
                agent: AgentKind.codex,
                briefReplyMode: false,
                status: SessionStatus.running,
                updatedAt: DateTime(2026, 5, 5, 12),
                unreadCount: 0,
                lastMessagePreview: 'new activity',
                pendingApproval: null,
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('触发活动并返回'),
        ),
      ),
    );
  }
}
