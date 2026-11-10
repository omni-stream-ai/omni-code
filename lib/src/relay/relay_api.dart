import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'relay_settings.dart';

class RelayLogin {
  RelayLogin(
      {required this.origin,
      required this.clientKey,
      required String deviceCode,
      required this.userCode,
      required this.verificationUri,
      required this.expiresAt,
      required this.interval})
      : _deviceCode = deviceCode;
  final String origin, clientKey, _deviceCode, userCode, verificationUri;
  final int expiresAt, interval;
}

class RelayService {
  RelayService.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        kind = json['kind'] as String,
        access = json['access'] as String,
        online = json['online'] == true;
  final String id, name, kind, access;
  final bool online;
}

class RelayApi {
  RelayApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();
  Future<Map<String, dynamic>> _request(String origin, String path,
      {Object? body, RelaySettings? session}) async {
    final base = normalizeRelayOrigin(origin);
    if (session != null && normalizeRelayOrigin(session.origin) != base) {
      throw const RelayException('provider_mismatch');
    }
    final request =
        http.Request(body == null ? 'GET' : 'POST', Uri.parse('$base$path'))
          ..followRedirects = false;
    if (session != null) request.headers.addAll(session.headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)));
    if (response.statusCode == 204) return {};
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const RelayException('invalid_response');
    }
    if (response.statusCode >= 300 || response.statusCode < 200) {
      throw RelayException(decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'http_${response.statusCode}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RelayException('invalid_response');
    }
    return decoded;
  }

  Future<RelayLogin> beginLogin(String origin, String name,
      {RelaySettings? previous}) async {
    final base = normalizeRelayOrigin(origin);
    if (name.trim().isEmpty || name.length > 100) {
      throw const RelayException('invalid_name');
    }
    final random = Random.secure();
    final clientKey = previous?.origin == base &&
            RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(previous!.clientKey)
        ? previous.clientKey
        : base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
            .replaceAll('=', '');
    final value = await _request(base, '/v1/device-login/start',
        body: {'name': name.trim(), 'client_key': clientKey});
    final verification = value['verification_uri'] as String;
    if (normalizeRelayOrigin(verification) != base) {
      throw const RelayException('provider_mismatch');
    }
    return RelayLogin(
        origin: base,
        clientKey: clientKey,
        deviceCode: value['device_code'] as String,
        userCode: value['user_code'] as String,
        verificationUri: verification,
        expiresAt: value['expires_at'] as int,
        interval: max(5, value['interval'] as int));
  }

  Future<RelaySettings?> pollLogin(RelayLogin flow) async {
    if (flow.expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const RelayException('login_expired');
    }
    final value = await _request(flow.origin, '/v1/device-login/poll',
        body: {'device_code': flow._deviceCode});
    if (value['status'] == 'pending') return null;
    final result = RelaySettings(
        origin: flow.origin,
        clientKey: flow.clientKey,
        token: value['token'] as String,
        clientId: value['client_id'] as String,
        expiresAt: value['expires_at'] as int);
    result.headers;
    return result;
  }

  Future<List<RelayService>> services(RelaySettings session) async {
    final result =
        await _request(session.origin, '/v1/services', session: session);
    return (result['services'] as List<dynamic>)
        .map((value) => RelayService.fromJson(value as Map<String, dynamic>))
        .where((value) => value.kind == 'omni-code')
        .toList();
  }

  Future<void> requestAccess(RelaySettings session, String id) async {
    await _request(session.origin,
        '/v1/services/${Uri.encodeComponent(id)}/request-access',
        body: {}, session: session);
  }

  Future<void> logout(RelaySettings session) async {
    if (session.signedIn) {
      await _request(session.origin, '/v1/logout', body: {}, session: session);
    }
  }

  Future<String> websocketTicket(RelaySettings session, Uri uri) async {
    final base = Uri.parse(session.serviceUrl);
    final socketPort =
        uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80);
    if (uri.host != base.host ||
        socketPort != base.port ||
        !uri.path.startsWith('${base.path}/') ||
        uri.scheme != (base.scheme == 'https' ? 'wss' : 'ws')) {
      throw const RelayException('websocket_target_denied');
    }
    final result = await _request(session.origin, '/v1/ws-tickets',
        body: {'path': uri.path + (uri.hasQuery ? '?${uri.query}' : '')},
        session: session);
    return result['ticket'] as String;
  }
}
