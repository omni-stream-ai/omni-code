import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/workspace_agent_composer.dart';

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json'});

void main() {
  for (final home in [true, false]) {
    testWidgets(
        'approval choice persists and stays isolated from other open assistants, home=$home',
        (tester) async {
      tester.view.physicalSize = Size(home ? 360 : 1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var defaultMode = 'smart';
      final modes = <String, String>{};
      var failSave = false;
      BridgeClient client() =>
          BridgeClient(httpClient: MockClient((request) async {
            final id = request.headers['x-omni-code-conversation-id'] ?? '';
            if (request.url.path == '/settings') {
              return _ok({'model_providers': []});
            }
            if (request.url.path.endsWith('/dispatch/settings')) {
              return _ok({
                'agent': 'pi',
                'approval_mode': modes.putIfAbsent(id, () => defaultMode)
              });
            }
            if (request.url.path.endsWith('/approval-mode') &&
                request.method == 'PUT') {
              if (failSave) return http.Response('Save failed', 500);
              final mode = jsonDecode(request.body)['approval_mode'] as String;
              modes[id] = mode;
              defaultMode = mode;
              return _ok({'approval_mode': mode});
            }
            return _ok({'selection': null});
          }));
      final firstClient = client();
      final otherClient = client();
      final first = WorkspaceAgentComposerController(firstClient);
      final other = WorkspaceAgentComposerController(otherClient);
      await Future.wait([first.ready, other.ready]);
      Widget view(WorkspaceAgentComposerController controller, bool home) =>
          MaterialApp(
            home: Scaffold(
                body: Center(
                    child: WorkspaceAgentComposer(
              controller: controller,
              home: home,
              onSend: () {},
            ))),
          );
      Future<void> menu(bool home) async {
        await tester.tap(find.byKey(const Key('agent-approval-mode-button')));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(view(first, home));
      await tester.pumpAndSettle();
      final modelRect = tester.getRect(
          find.byKey(Key(home ? 'home-assistant-model' : 'agent-chat-model')));
      final approvalRect =
          tester.getRect(find.byKey(const Key('agent-approval-mode-button')));
      expect(approvalRect.left, greaterThanOrEqualTo(modelRect.right));
      expect(approvalRect.center.dy, closeTo(modelRect.center.dy, 1));
      await menu(home);
      expect(
          find.descendant(
              of: find.byKey(const Key('agent-approval-mode-option-smart')),
              matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      await tester
          .tap(find.byKey(const Key('agent-approval-mode-option-auto')));
      await tester.pumpAndSettle();
      expect(first.approvalMode, ApprovalMode.auto);
      expect(other.approvalMode, ApprovalMode.smart);
      expect(defaultMode, 'auto');
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      final reopened = WorkspaceAgentComposerController(firstClient);
      await reopened.ready;
      await tester.pumpWidget(view(reopened, !home));
      await tester.pumpAndSettle();
      await menu(!home);
      expect(
          find.descendant(
              of: find.byKey(const Key('agent-approval-mode-option-auto')),
              matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      failSave = true;
      await tester
          .tap(find.byKey(const Key('agent-approval-mode-option-manual')));
      await tester.pumpAndSettle();
      expect(reopened.approvalMode, ApprovalMode.auto);
      expect(find.text('Could not save approval mode. Please try again.'),
          findsOneWidget);
      failSave = false;
      firstClient.startWorkspaceConversation();
      await reopened.ready;
      expect(reopened.approvalMode, ApprovalMode.auto);
      expect(other.approvalMode, ApprovalMode.smart);
      await tester.pumpWidget(const SizedBox());
      reopened.dispose();
      other.dispose();
      firstClient.dispose();
      otherClient.dispose();
    });
  }

  test(
      'session mode update targets one session and requires server confirmation',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/v2/sessions/first');
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _ok({
        'id': 'first',
        'project_id': 'project',
        'title': 'First',
        'agent': 'codex',
        'status': 'idle',
        'updated_at': '2026-11-18T12:00:00Z',
        'unread_count': 0,
        'approval_mode': bodies.length == 1 ? 'auto' : 'smart'
      });
    }));
    expect(
        (await client.updateSessionApprovalMode('first', ApprovalMode.auto))
            .approvalMode,
        ApprovalMode.auto);
    expect(bodies.single, {'approval_mode': 'auto'});
    await expectLater(
        client.updateSessionApprovalMode('first', ApprovalMode.manual),
        throwsStateError);
    client.dispose();
  });

  test(
      'assistant save from an old conversation cannot change the new conversation',
      () async {
    final saving = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'PUT') return saving.future;
      if (request.url.path == '/settings') return _ok({'model_providers': []});
      if (request.url.path.endsWith('/dispatch/settings')) {
        return _ok({'agent': 'pi', 'approval_mode': 'manual'});
      }
      return _ok({'selection': null});
    }));
    final controller = WorkspaceAgentComposerController(client);
    await controller.ready;
    final pending = controller.saveApprovalMode(ApprovalMode.auto);
    client.startWorkspaceConversation();
    await controller.ready;
    saving.complete(_ok({'approval_mode': 'auto'}));
    await pending;
    expect(controller.approvalMode, ApprovalMode.manual);
    controller.dispose();
    client.dispose();
  });
}
