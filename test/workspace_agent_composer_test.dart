import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/composer_settings_dropdown.dart';
import 'package:omni_code/src/widgets/workspace_agent_composer.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json'});
Map<String, dynamic> snapshot({List<dynamic> chat = const []}) => {
      'scope': {
        'include_other_sessions': true,
        'recent_days': 5,
        'max_sessions': 15
      },
      'tasks': [],
      'selected_sessions': 0,
      'cached_sessions': 0,
      'running': false,
      'errors': {},
      'chat': chat,
    };

void main() {
  testWidgets(
      'model picker saves provider and model and restores them on reopen',
      (tester) async {
    Map<String, dynamic>? saved;
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path == '/settings') {
        return ok({
          'model_providers': [
            {
              'id': 'service',
              'name': 'My provider',
              'enabled': true,
              'base_url': 'https://model.test/v1',
              'format': 'codex'
            },
            {
              'id': 'disabled',
              'name': 'Disabled provider',
              'enabled': false,
              'base_url': 'https://unused.test/v1'
            },
          ]
        });
      }
      if (r.url.path == '/v1/models') {
        return ok([
          {'id': 'model-one'},
          {'id': 'model-two'}
        ]);
      }
      if (r.url.path.endsWith('/workspace-agent/model')) {
        if (r.method == 'PUT') {
          saved = jsonDecode(r.body)['selection'] as Map<String, dynamic>?;
        }
        return ok({'selection': saved});
      }
      return ok(snapshot());
    }));
    final first = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceAgentChat(
                client: client, composerController: first))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-chat-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-provider-settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('Disabled provider'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const Key('agent-provider-option-service')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(find.text('model-two'));
    await tester.pump();
    expect(saved, {'provider_id': 'service', 'model': 'model-two'});
    expect(find.textContaining('My provider • model-two'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    final reopened = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceAgentChat(
                client: client, composerController: reopened))));
    await tester.pumpAndSettle();
    expect(find.textContaining('My provider • model-two'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-chat-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-provider-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-provider-option-auto')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Automatic model'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    reopened.dispose();
    client.dispose();
  });

  for (final width in [360.0, 1100.0]) {
    testWidgets(
        'home dropdown includes task agents, providers and models at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved = {
        'provider_id': 'first',
        'model': 'previous-model'
      };
      var writes = 0;
      var taskAgent = 'pi';
      var agentWrites = 0;
      var failAgentSave = false;
      final client = BridgeClient(httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/dispatch/settings')) {
          if (r.method == 'PUT') {
            if (failAgentSave) {
              return http.Response('Cannot save task agent', 500);
            }
            taskAgent = jsonDecode(r.body)['agent'] as String;
            agentWrites++;
          }
          return ok({'agent': taskAgent});
        }
        if (r.url.path == '/settings') {
          return ok({
            'model_providers': [
              {
                'id': 'first',
                'name': 'First service',
                'enabled': true,
                'base_url': 'https://first.test/v1',
                'model': 'default-model'
              },
              {
                'id': 'second',
                'name': 'Second service',
                'enabled': true,
                'base_url': 'https://second.test/v1'
              },
            ]
          });
        }
        if (r.url.path.endsWith('/workspace-agent/model')) {
          if (r.method == 'PUT') {
            saved = jsonDecode(r.body)['selection'] as Map<String, dynamic>?;
            writes++;
          }
          return ok({'selection': saved});
        }
        if (r.url.path == '/v1/models') {
          return http.Response('Catalog unavailable', 503);
        }
        return ok(
            r.url.path.endsWith('/analyze') ? {'running': false} : snapshot());
      }));
      Widget home() => MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      WorkspaceAgentPanel(client: client, homeSurface: true))));
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(find.textContaining('Run: '), findsNothing);
      Future<void> chooseSecondService() async {
        await tester.tap(find.byKey(const Key('home-assistant-model')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('agent-model-settings-button')),
            findsOneWidget);
        expect(find.byKey(const Key('agent-dispatch-settings-button')),
            findsOneWidget);
        await tester
            .tap(find.byKey(const Key('agent-provider-settings-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('agent-provider-option-second')));
        await tester.pumpAndSettle();
      }

      await chooseSecondService();
      expect(writes, 0);
      expect(saved!['provider_id'], 'first');
      // Dismissing a partially chosen service does not change the saved route.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('First service • previous-model'),
          findsOneWidget);
      await chooseSecondService();
      await tester.enterText(
          find.byKey(const Key('agent-model-custom-input')), 'manual-model');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(saved, {'provider_id': 'second', 'model': 'manual-model'});
      expect(
          find.textContaining('Second service • manual-model'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Second service • manual-model'), findsOneWidget);
      Future<void> openAgentMenu(String trigger) async {
        await tester.tap(find.byKey(Key(trigger)));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const Key('agent-dispatch-settings-button')));
        await tester.pumpAndSettle();
      }

      bool selectedAgent(String value) => tester
          .widget<ComposerSettingsOption>(
              find.byKey(ValueKey('agent-dispatch-option-$value')))
          .selected;
      await openAgentMenu('home-assistant-model');
      expect(selectedAgent('pi'), isTrue);
      await tester.tap(find.byKey(const Key('agent-dispatch-option-codex')));
      await tester.pumpAndSettle();
      expect(taskAgent, 'codex');
      expect(agentWrites, 1);
      expect(writes, 1);
      expect(
          find.byKey(const Key('agent-dispatch-option-codex')), findsNothing);
      expect(
          find.textContaining('Second service • manual-model'), findsOneWidget);
      await openAgentMenu('home-assistant-model');
      expect(selectedAgent('codex'), isTrue);
      failAgentSave = true;
      await tester
          .tap(find.byKey(const Key('agent-dispatch-option-claude_code')));
      await tester.pumpAndSettle();
      expect(taskAgent, 'codex');
      expect(agentWrites, 1);
      expect(selectedAgent('codex'), isTrue);
      expect(find.textContaining('Cannot save task agent'), findsOneWidget);
      expect(saved, {'provider_id': 'second', 'model': 'manual-model'});
      expect(writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      final chatDraft = WorkspaceAgentComposerController(client);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WorkspaceAgentChat(
                  client: client, composerController: chatDraft))));
      await tester.pumpAndSettle();
      await openAgentMenu('agent-chat-model');
      expect(selectedAgent('codex'), isTrue);
      expect(find.textContaining('Run: '), findsNothing);
      expect(writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      chatDraft.dispose();
      client.dispose();
    },
        variant: TargetPlatformVariant(
            {width < 600 ? TargetPlatform.android : TargetPlatform.linux}));
  }

  testWidgets('failed model save keeps the previous selection', (tester) async {
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path == '/settings') {
        return ok({
          'model_providers': [
            {
              'id': 'service',
              'name': 'My provider',
              'enabled': true,
              'base_url': 'https://model.test/v1',
              'model': 'previous-model'
            }
          ]
        });
      }
      if (r.url.path.endsWith('/workspace-agent/model')) {
        if (r.method == 'PUT') return http.Response('Cannot save model', 500);
        return ok({
          'selection': {'provider_id': 'service', 'model': 'previous-model'}
        });
      }
      if (r.url.path == '/v1/models') {
        return ok([
          {'id': 'next-model'}
        ]);
      }
      return ok(snapshot());
    }));
    final draft = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceAgentChat(
                client: client, composerController: draft))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-chat-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-model-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next-model'));
    await tester.pump();
    expect(draft.model, 'previous-model');
    expect(find.textContaining('My provider • previous-model'), findsOneWidget);
    expect(find.textContaining('Cannot save model'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    client.dispose();
  });

  testWidgets(
      'home attachment-only draft survives failure and uploads once on retry',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('agent-composer-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file =
        File([directory.path, 'notes.txt'].join(Platform.pathSeparator))
          ..writeAsStringSync('Export is pending.');
    var uploads = 0;
    var attempts = 0;
    final sent = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.path == '/settings') return ok({'model_providers': []});
      if (r.url.path.endsWith('/workspace-agent/model')) {
        return ok({'selection': null});
      }
      if (r.url.path == '/uploads') {
        uploads++;
        return ok({
          'id': 'uploaded-notes.txt',
          'file_name': 'notes.txt',
          'content_type': 'text/plain',
          'size_bytes': 18,
          'url': '/uploads/uploaded-notes.txt',
          'absolute_url': 'http://bridge/uploads/uploaded-notes.txt'
        });
      }
      if (r.url.path.endsWith('/chat') && r.method == 'POST') {
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        attempts++;
        if (attempts == 1) return http.Response('Temporary failure', 503);
        return ok([
          {
            'id': 'user',
            'role': 'user',
            'content': '',
            'attachments': sent.last['attachments']
          },
          {
            'id': 'reply',
            'role': 'assistant',
            'content': 'The export is pending.'
          }
        ]);
      }
      return ok(
          r.url.path.endsWith('/analyze') ? {'running': false} : snapshot());
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    WorkspaceAgentPanel(client: client, homeSurface: true)))));
    await tester.pumpAndSettle();
    final home = tester
        .widget<WorkspaceAgentComposer>(find.byType(WorkspaceAgentComposer));
    home.controller.addFiles([file.path]);
    await tester.pump();
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    for (var i = 0; i < 100 && attempts < 1; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(home.controller.paths, [file.path]);
    expect(sent.single['message'], '');
    expect((sent.single['attachments'] as List).single['id'],
        'uploaded-notes.txt');
    await tester.tap(find.byKey(const Key('main-agent-conversation-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    for (var i = 0; i < 100 && attempts < 2; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(uploads, 1);
    expect(sent.last['request_id'], sent.first['request_id']);
    expect(home.controller.paths, isEmpty);
    expect(find.text('The export is pending.'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('composer adds and removes files using the attachment button',
      (tester) async {
    final client = BridgeClient(
        httpClient: MockClient((r) async => ok(r.url.path == '/settings'
            ? {'model_providers': []}
            : {'selection': null})));
    final draft = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceAgentComposer(
                controller: draft,
                onSend: () {},
                pickAttachments: () async => ['/tmp/report.md']))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add attachment'));
    await tester.pumpAndSettle();
    expect(find.text('report.md'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pump();
    expect(draft.paths, isEmpty);
    expect(find.text('report.md'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    client.dispose();
  });
}
