import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/relay/relay_settings.dart';
import 'package:omni_code/src/services/session_event_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() =>
      appSettingsController.pushEphemeralSettings(AppSettings.defaults()));
  tearDown(() => appSettingsController.popEphemeralSettings());
  test('late HTTP responses cannot repopulate caches after switching Bridge',
      () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      requests++;
      if (requests == 1) return response.future;
      return http.Response('{"data":[]}', 200,
          headers: {'content-type': 'application/json'});
    }));
    final pending = client.listProjects();
    await Future<void>.delayed(Duration.zero);
    appSettingsController.pushEphemeralSettings(appSettingsController.settings
        .copyWith(bridgeUrl: 'https://other.example'));
    response.complete(http.Response('{"data":[]}', 200,
        headers: {'content-type': 'application/json'}));
    await expectLater(
        pending,
        throwsA(isA<RelayException>()
            .having((error) => error.code, 'code', 'connection_changed')));
    expect(await client.listProjects(), isEmpty);
    expect(requests, 2);
    client.dispose();
  });
  test(
      'connection changes cancel an idle SSE body instead of waiting for another event',
      () async {
    final body = StreamController<List<int>>();
    var canceled = false;
    body.onCancel = () => canceled = true;
    final client = BridgeClient(httpClient: _StreamClient(body.stream));
    final first = Completer<void>(), done = Completer<void>();
    final errors = <Object>[];
    final subscription =
        client.subscribeToAllDomainSessionEvents().listen((event) {
      if (!first.isCompleted) first.complete();
    }, onError: errors.add, onDone: done.complete);
    body.add(utf8.encode('data: {"type":"fixture"}\n\n'));
    await first.future;
    appSettingsController.pushEphemeralSettings(appSettingsController.settings
        .copyWith(bridgeUrl: 'https://other.example'));
    await done.future.timeout(const Duration(seconds: 2));
    expect(canceled, isTrue);
    expect(
        errors.single,
        isA<RelayException>()
            .having((error) => error.code, 'code', 'connection_changed'));
    await subscription.cancel();
    await body.close();
    client.dispose();
  });
  test('global event service replaces the old stream on a connection switch',
      () async {
    final client = _EventsClient();
    final service = SessionEventService(client: client);
    try {
      service.start();
      await service.synchronizeForTest();
      expect(client.starts, 1);
      appSettingsController.pushEphemeralSettings(appSettingsController.settings
          .copyWith(bridgeUrl: 'https://other.example'));
      await service.synchronizeForTest();
      expect(client.starts, 2);
      expect(client.stops, 1);
    } finally {
      service.dispose();
      await client.events.close();
      client.dispose();
    }
  });
  test('global events wait for an explicit reconnect after Relay denies access',
      () async {
    final client = _EventsClient()..denied = true;
    final service = SessionEventService(client: client);
    try {
      service.start();
      await service.synchronizeForTest();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(client.loads, 1);
      client.denied = false;
      service.refreshConnection();
      await service.synchronizeForTest();
      expect(client.starts, 1);
    } finally {
      service.dispose();
      await client.events.close();
      client.dispose();
    }
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body);
  final Stream<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body, 200,
          headers: {'content-type': 'text/event-stream'});
}

class _EventsClient extends BridgeClient {
  int starts = 0, stops = 0, loads = 0;
  bool denied = false;
  late final events = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () => starts++, onCancel: () => stops++);
  @override
  Future<List<SessionSummary>> listDomainSessions(
      {String? projectId, String? profileId, bool forceRefresh = false}) async {
    loads++;
    if (denied) throw const RelayException('service_access_denied');
    return [];
  }

  @override
  Stream<Map<String, dynamic>> subscribeToAllDomainSessionEvents() =>
      events.stream;
}
