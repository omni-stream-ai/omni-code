import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/relay/relay_api.dart';
import 'package:omni_code/src/relay/relay_settings.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/services/authenticated_resource_client.dart';

String secret() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
RelaySettings session() => RelaySettings(
    origin: 'https://relay.example',
    token: secret(),
    clientKey: secret(),
    clientId: 'device',
    expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    serviceId: 'service',
    enabled: true);
void main() {
  setUp(() =>
      appSettingsController.pushEphemeralSettings(AppSettings.defaults()));
  tearDown(() => appSettingsController.popEphemeralSettings());
  test('Relay state round-trips independently from direct Bridge credentials',
      () {
    final relay = session();
    final settings = AppSettings.defaults().copyWith(
        bridgeUrl: 'http://127.0.0.1:8787',
        bridgeToken: secret(),
        relay: relay);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.connectionUrl, 'https://relay.example/s/service');
    expect(restored.relay.token == relay.token, isTrue);
    expect(
        restored.copyWith(relay: relay.copyWith(enabled: false)).connectionUrl,
        'http://127.0.0.1:8787');
    expect(() => normalizeRelayOrigin('https://relay.example/path'),
        throwsFormatException);
    expect(() => normalizeRelayOrigin('http://remote.example'),
        throwsFormatException);
    expect(() => relay.copyWith(expiresAt: 0).headers,
        throwsA(isA<RelayException>()));
  });
  test(
      'pairing capabilities stay in the body and identity is reused on re-login',
      () async {
    final previous = session(), deviceCode = secret(), issued = secret();
    final requests = <http.Request>[];
    final api = RelayApi(client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/start')) {
        return http.Response(
            jsonEncode({
              'device_code': deviceCode,
              'user_code': 'ABCDEF23',
              'verification_uri': 'https://relay.example/',
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
              'interval': 5
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'token': issued,
            'client_id': 'next-device',
            'expires_at': previous.expiresAt
          }),
          200);
    }));
    final flow =
        await api.beginLogin(previous.origin, 'phone', previous: previous);
    expect(flow.clientKey == previous.clientKey, isTrue);
    expect(flow.verificationUri.contains(deviceCode), isFalse);
    final value = await api.pollLogin(flow);
    expect(value!.token == issued, isTrue);
    expect(jsonDecode(requests.last.body)['device_code'] == deviceCode, isTrue);
    expect(
        requests.every((request) =>
            !request.url.toString().contains(deviceCode) &&
            !request.followRedirects),
        isTrue);
    api.close();
  });
  test(
      'Bridge routes JSON and SSE with the Relay token and drops stale direct caches',
      () async {
    final relay = session(), direct = secret();
    appSettingsController.pushEphemeralSettings(
        AppSettings.defaults().copyWith(bridgeToken: direct));
    final requests = <http.Request>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/events')) {
        return http.Response('data: {"type":"fixture"}\n\n', 200,
            headers: {'content-type': 'text/event-stream'});
      }
      return http.Response('{"data":[]}', 200,
          headers: {'content-type': 'application/json'});
    }));
    await client.listProjects();
    appSettingsController.pushEphemeralSettings(
        appSettingsController.settings.copyWith(relay: relay));
    await client.listProjects();
    expect(requests.length, 2);
    expect(requests.last.url.path, '/s/service/projects');
    expect(requests.last.headers['authorization'] == 'Bearer ${relay.token}',
        isTrue);
    expect(requests.last.headers.containsKey('x-omni-code-client-id'), isFalse);
    expect(requests.last.followRedirects, isFalse);
    expect((await client.subscribeToAllDomainSessionEvents().first)['type'],
        'fixture');
    await expectLater(client.registerClient(), throwsA(isA<RelayException>()));
    appSettingsController.pushEphemeralSettings(appSettingsController.settings
        .copyWith(relay: relay.copyWith(enabled: false)));
    await client.listProjects();
    expect(requests.last.headers['authorization'] == 'Bearer $direct', isTrue);
    client.dispose();
  });
  test(
      'Relay services and WS tickets are scoped, and authorization is requested explicitly',
      () async {
    final relay = session();
    final requests = <http.Request>[];
    final api = RelayApi(client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v1/services') {
        return http.Response(
            jsonEncode({
              'services': [
                {
                  'id': 'service',
                  'name': 'Code',
                  'kind': 'omni-code',
                  'access': 'allowed',
                  'online': true
                },
                {
                  'id': 'core',
                  'name': 'Core',
                  'kind': 'omnistream',
                  'access': 'allowed',
                  'online': true
                }
              ]
            }),
            200);
      }
      if (request.url.path == '/v1/ws-tickets') {
        return http.Response(jsonEncode({'ticket': secret()}), 200);
      }
      return http.Response('{"access":"pending"}', 200);
    }));
    expect((await api.services(relay)).map((value) => value.id), ['service']);
    await api.requestAccess(relay, 'service');
    await api.websocketTicket(
        relay, Uri.parse('wss://relay.example/s/service/speech/ws'));
    expect(jsonDecode(requests.last.body)['path'], '/s/service/speech/ws');
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer ${relay.token}'),
        isTrue);
    await expectLater(
        api.websocketTicket(relay, Uri.parse('wss://other.example/ws')),
        throwsA(isA<RelayException>()));
    api.close();
  });
  test(
      'authenticated media cannot redirect or leak credentials to a second resource',
      () async {
    final uri = Uri.parse('https://relay.example/s/service/audio'),
        token = secret();
    final client =
        AuthenticatedResourceClient(uri, {'Authorization': 'Bearer $token'},
            client: MockClient((request) async {
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'] == 'Bearer $token', isTrue);
      return http.Response('', 200);
    }));
    expect((await client.get(uri)).statusCode, 200);
    await expectLater(
        client.get(Uri.parse('https://other.example/audio')), throwsStateError);
    client.close();
  });
}
