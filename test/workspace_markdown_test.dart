import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/message_markdown.dart';
import 'package:omni_code/src/widgets/session_file_preview.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

import 'workspace_agent_test.dart' as fixtures;

class _MarkdownServer {
  List<Map<String, dynamic>> chat = [];
  final files = <String, String>{};
  final fileRequests = <http.Request>[];
  int revision = 0;

  Future<http.Response> call(http.Request request) async {
    switch (request.url.path) {
      case '/settings':
        return fixtures.ok({'model_providers': []});
      case '/workspace-agent/model':
        return fixtures.ok({'selection': null});
      case '/workspace-agent/dispatch/settings':
        return fixtures.ok({'agent': 'pi'});
      case '/files/info':
      case '/files':
        fileRequests.add(request);
        final path = request.url.queryParameters['path']!;
        final content = files[path];
        if (content == null) return http.Response('File not found', 404);
        return request.url.path.endsWith('/info')
            ? fixtures.ok({
                'name': path.split('/').last,
                'path': path,
                'size': content.length,
              })
            : http.Response(content, 200);
      default:
        return fixtures.ok({
          ...fixtures.snapshot(chat: chat),
          'cached_sessions': 3 + revision,
        });
    }
  }
}

Future<void> _showChat(WidgetTester tester, _MarkdownServer server,
    {bool inline = false, ProjectSummary? project}) async {
  final client = BridgeClient(httpClient: MockClient(server.call));
  addTearDown(client.dispose);
  final chat = WorkspaceAgentChat(
    client: client,
    fullPage: !inline,
    inline: inline,
    projectId: project?.id,
    projects: project == null ? const [] : [project],
  );
  await tester.pumpWidget(MaterialApp(
      home:
          inline ? Scaffold(body: SingleChildScrollView(child: chat)) : chat));
  await tester.pumpAndSettle();
}

Future<void> _settleFilePreview(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final inline in [false, true]) {
    for (final width in [320.0, 1000.0]) {
      testWidgets(
          'assistant renders rich messages at width $width, inline $inline',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final server = _MarkdownServer()
          ..chat = [
            {
              'id': 'user',
              'role': 'user',
              'content': 'Need **review**.',
            },
            {
              'id': 'answer',
              'role': 'assistant',
              'content': '# Review\n\n'
                  '**Ready** with `inline`.\n\n'
                  '- First item\n- Second item\n\n'
                  '> A quoted note.\n\n'
                  '```dart\nfinal count = 2;\n```\n\n'
                  '| Task | Status |\n| --- | --- |\n| Review | Done |\n\n'
                  '[Documentation](https://example.com/docs)',
            },
          ];
        await _showChat(tester, server, inline: inline);

        expect(find.text('Need review.'), findsOneWidget);
        expect(find.text('Ready with inline.'), findsOneWidget);
        expect(find.text('First item'), findsOneWidget);
        expect(find.text('A quoted note.'), findsOneWidget);
        expect(find.textContaining('final count = 2;'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(find.text(server.chat.last['content'] as String), findsNothing);
        final markdown = find.descendant(
            of: find.byKey(const ValueKey('assistant-message-markdown-answer')),
            matching: find.byType(MarkdownBody));
        expect(markdown, findsOneWidget);
        expect(
            find.ancestor(of: markdown, matching: find.byType(SelectionArea)),
            findsOneWidget);
        expect(tester.widget<MarkdownBody>(markdown).selectable, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('polling preserves existing markdown and renders changed replies',
      (tester) async {
    final server = _MarkdownServer()
      ..chat = [
        {'id': 'answer', 'role': 'assistant', 'content': 'First **answer**.'}
      ];
    await _showChat(tester, server);
    final markdown = find.byType(MarkdownBody);
    final original = tester.widget<MarkdownBody>(markdown);
    final selection = tester.state(find.byType(SelectionArea));

    server.revision++;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<MarkdownBody>(markdown), same(original));
    expect(tester.state(find.byType(SelectionArea)), same(selection));

    server.chat.single['content'] = 'Updated **answer**.\n\n- Verified';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Updated answer.'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('First answer.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rules preserve fenced code, headings and reference links',
      (tester) async {
    String? openedLink;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => MessageMarkdown(
                      data: 'Setext heading\n---\n\n'
                          '```text\nbefore\n---\nafter\n```\n\n'
                          '[guide][docs]\n\n---\n\n'
                          '[docs]: https://example.com/guide',
                      theme: Theme.of(context),
                      textColor: Theme.of(context).colorScheme.onSurface,
                      onTapLink: (href) => openedLink = href,
                    )))));
    await tester.pumpAndSettle();

    expect(find.text('Setext heading'), findsOneWidget);
    expect(find.textContaining('before\n---\nafter'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('markdown-horizontal-rule')), findsOneWidget);
    final rule =
        tester.getSize(find.byKey(const ValueKey('markdown-horizontal-rule')));
    expect(rule.width, greaterThan(0));
    expect(rule.height, 1);
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.tap(find.text('guide'));
    expect(openedLink, 'https://example.com/guide');
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant file links preview project files and nested links',
      (tester) async {
    final server = _MarkdownServer()
      ..chat = [
        {
          'id': 'answer',
          'role': 'assistant',
          'content': '[Open guide](docs/guide.md)'
        }
      ]
      ..files.addAll({
        '/missing/workspace/docs/guide.md':
            '# Linked guide\n\n[Details](../src/detail.dart#L2)',
        '/missing/workspace/src/detail.dart': 'final details = 1;',
      });
    final project = ProjectSummary(
      id: 'project',
      name: 'Workspace',
      rootPath: '/missing/workspace',
      updatedAt: DateTime(2026, 11, 16),
      sessionCount: 0,
    );
    await _showChat(tester, server, project: project);
    await tester.tap(find.text('Open guide'));
    await _settleFilePreview(tester);
    expect(find.byType(SessionFilePreview), findsOneWidget);
    expect(find.text('Linked guide'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await _settleFilePreview(tester);
    expect(find.textContaining('final details = 1;'), findsOneWidget);
    expect(server.fileRequests.map((r) => r.url.queryParameters['path']), [
      '/missing/workspace/docs/guide.md',
      '/missing/workspace/docs/guide.md',
      '/missing/workspace/src/detail.dart',
      '/missing/workspace/src/detail.dart',
    ]);
    for (final request in server.fileRequests) {
      expect(request.url.queryParameters['project_id'], 'project');
      expect(request.url.queryParameters.containsKey('session_id'), isFalse);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
