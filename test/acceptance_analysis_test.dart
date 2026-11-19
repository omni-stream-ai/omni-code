import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/acceptance_models.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_screen.dart';
import 'package:omni_code/src/screens/session_detail_screen.dart';

Map<String, dynamic> runData() => {
      'id': 'result-run',
      'project_id': 'project-a',
      'session_id': 'source-session',
      'revision': 'frozen-source',
      'command': './app',
      'phase': 'completed',
      'created_at': '2026-11-15T00:00:00Z',
      'artifacts': [],
      'automatic': true,
      'automation': 'completed',
      'result': {'passed': false, 'notes': 'Focus lost'},
    };
Map<String, dynamic> sessionData(String id) => {
      'id': id,
      'project_id': 'project-a',
      'title': 'Result analysis',
      'agent': 'codex',
      'status': 'idle',
      'updated_at': '2026-11-15T00:00:00Z',
      'unread_count': 0,
    };
http.Response response(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status,
        headers: {'content-type': 'application/json'});
Widget screen(Map<String, dynamic> data, BridgeClient client) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AcceptanceDetailScreen(
        run: AcceptanceRun.fromJson(data), client: client));

void main() {
  for (final newSession in [false, true]) {
    testWidgets(
        'sends results to ${newSession ? 'new' : 'source'} session once and opens it',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final run = runData();
      final targetId = newSession ? 'new-analysis' : 'source-session';
      final submission = Completer<http.Response>();
      final requests = <Map<String, dynamic>>[];
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/v2/acceptance/result-run/analyze');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return submission.future;
        }
        if (request.url.path.startsWith('/v2/acceptance/')) {
          return response(run);
        }
        if (request.url.path.endsWith('/state')) {
          return response({
            'session': {
              ...sessionData(targetId),
              'version': 1,
              'config': {},
              'created_at': '2026-11-15T00:00:00Z'
            },
            'turns': [],
            'cursor': 0,
          });
        }
        if (request.url.path.endsWith('/events')) {
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.url.path.endsWith('/$targetId')) {
          return response({'session': sessionData(targetId)});
        }
        return response([]);
      }));
      await tester.pumpWidget(screen(run, client));
      await tester.pumpAndSettle();
      final button = find.byKey(Key(newSession
          ? 'acceptance-analyze-new'
          : 'acceptance-analyze-current'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      expect(requests, hasLength(1));
      expect(requests.single['new_session'], newSession);
      expect(requests.single['request_id'], isNotEmpty);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const Key('acceptance-analyze-new')))
              .onPressed,
          isNull);
      submission.complete(response(sessionData(targetId), status: 202));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final destination =
          tester.widget<SessionDetailScreen>(find.byType(SessionDetailScreen));
      expect(destination.session.id, targetId);
      expect(destination.client, same(client));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('project run explains missing source and allows a new analysis',
      (tester) async {
    final data = {...runData(), 'session_id': null};
    final client =
        BridgeClient(httpClient: MockClient((_) async => response(data)));
    await tester.pumpWidget(screen(data, client));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-analyze-current')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('acceptance-analyze-new')))
            .onPressed,
        isNotNull);
    expect(
        find.text(
            'This run has no source session. You can analyze it in a new session.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('analysis is unavailable while acceptance is executing',
      (tester) async {
    final data = {
      ...runData(),
      'phase': 'running',
      'automation': 'executing',
      'result': null
    };
    final client = BridgeClient(
        httpClient: MockClient((request) async =>
            request.url.path.endsWith('/preview')
                ? http.Response('Preview unavailable', 404)
                : response(data)));
    await tester.pumpWidget(screen(data, client));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('acceptance-result-analysis')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed submission displays its error and retries with the same request id',
      (tester) async {
    final data = runData();
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({'message': 'Source session is busy'}), 409);
      }
      return response(data);
    }));
    await tester.pumpWidget(screen(data, client));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('acceptance-analyze-current'));
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(requests, hasLength(2));
    expect(requests[0]['request_id'], requests[1]['request_id']);
    expect(find.textContaining('Source session is busy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
