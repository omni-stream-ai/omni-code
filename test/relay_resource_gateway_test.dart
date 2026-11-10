import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/relay/resource_gateway_io.dart';
import 'package:omni_code/src/relay/relay_settings.dart';

void main() {
  test(
      'native resource gateway isolates HTML, scopes credentials and streams HTTP and WebSocket',
      () async {
    final relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final origin = 'http://127.0.0.1:${relay.port}';
    final session = RelaySettings(
        origin: origin,
        token: token,
        clientKey: token,
        clientId: 'fixture',
        serviceId: 'service',
        enabled: true,
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var authorized = false;
    relay.listen((request) async {
      authorized = request.headers.value('authorization') == 'Bearer $token';
      expect(
          request.uri.path.startsWith('/s/service/v2/acceptance/run/desktop/'),
          isTrue);
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((value) => socket.add(value));
        return;
      }
      request.response.headers.set('content-type', 'text/html');
      request.response.headers
          .set('content-security-policy', "default-src 'none'");
      request.response.headers.set('set-cookie', 'fixture=private');
      request.response.write('<html>fixture</html>');
      await request.response.close();
    });
    final gateway =
        await RelayResourceGateway.open(session, '/v2/acceptance/run/desktop/');
    final client = http.Client();
    try {
      final uri = gateway.urlFor('/v2/acceptance/run/desktop/viewer.html');
      expect(uri.toString().contains(token), isFalse);
      final response = await client.get(uri);
      expect(response.statusCode, 200);
      expect(authorized, isTrue);
      expect(response.body.contains(token), isFalse);
      expect(response.headers.containsKey('set-cookie'), isFalse);
      expect(response.headers['content-security-policy'],
          contains("script-src 'self'"));
      expect(
          (await client.get(uri, headers: {'Origin': 'https://hostile.test'}))
              .statusCode,
          403);
      expect((await client.get(uri.replace(path: '/relay/status'))).statusCode,
          403);
      expect(() => gateway.urlFor('/v2/acceptance/other/desktop/viewer.html'),
          throwsA(isA<RelayException>()));
      final socket = await WebSocket.connect(
          gateway
              .urlFor('/v2/acceptance/run/desktop/websockify')
              .replace(scheme: 'ws')
              .toString(),
          headers: {'Origin': uri.origin});
      socket.add([1, 2, 3, 4]);
      expect(await socket.first, [1, 2, 3, 4]);
      await socket.close();
    } finally {
      client.close();
      await gateway.close();
      await relay.close(force: true);
    }
  });
}
