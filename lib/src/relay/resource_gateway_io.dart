import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'relay_settings.dart';

/// An isolated origin for native WebView/media resources. The browser never
/// receives the Relay credential and cannot reach other Bridge APIs here.
class RelayResourceGateway {
  RelayResourceGateway._(this.session, this.prefix, this.server);
  final RelaySettings session;
  final String prefix;
  final HttpServer server;
  final HttpClient _http = HttpClient()..autoUncompress = false;
  final Set<WebSocket> _sockets = {};
  bool _closed = false;
  String get _origin => 'http://127.0.0.1:${server.port}';
  static Future<RelayResourceGateway> open(
      RelaySettings session, String prefix) async {
    session.headers;
    if (!prefix.startsWith('/v2/acceptance/') ||
        prefix.contains('..') ||
        prefix.contains('?') ||
        prefix.contains('#')) {
      throw const RelayException('invalid_resource_scope');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gateway = RelayResourceGateway._(session, prefix, server);
    server.listen((request) => unawaited(gateway._handle(request)),
        onError: (Object _) {});
    return gateway;
  }

  Uri urlFor(String path) {
    final uri = Uri.parse(path);
    if (!_allowed(uri)) throw const RelayException('resource_target_denied');
    return Uri.parse(_origin + path);
  }

  bool _allowed(Uri uri) =>
      !uri.hasScheme &&
      !uri.hasAuthority &&
      !uri.hasFragment &&
      (prefix.endsWith('/')
          ? uri.path.startsWith(prefix)
          : uri.path == prefix) &&
      !uri.pathSegments.any((part) =>
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\'));
  Future<void> _handle(HttpRequest request) async {
    try {
      final origin = request.headers.value('origin');
      if (_closed ||
          request.headers.value('host') != '127.0.0.1:${server.port}' ||
          (origin != null && origin != _origin) ||
          !['GET', 'HEAD'].contains(request.method) ||
          !_allowed(request.uri)) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      final headers = session.headers;
      final target = Uri.parse(session.serviceUrl + request.uri.toString());
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final protocols =
            (request.headers.value('sec-websocket-protocol') ?? '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList();
        final upstream = await WebSocket.connect(
            target
                .replace(scheme: target.scheme == 'https' ? 'wss' : 'ws')
                .toString(),
            headers: headers,
            protocols: protocols.isEmpty ? null : protocols);
        final client = await WebSocketTransformer.upgrade(request,
            protocolSelector: (offered) => upstream.protocol);
        _sockets.addAll([client, upstream]);
        Future<void> pump(WebSocket input, WebSocket output) async {
          try {
            await for (final message in input) {
              if (message is List<int>) {
                for (var offset = 0;
                    offset < message.length;
                    offset += 64 * 1024) {
                  final end = (offset + 64 * 1024).clamp(0, message.length);
                  output.add(Uint8List.fromList(message.sublist(offset, end)));
                }
              } else {
                output.add(message);
              }
            }
          } catch (_) {
          } finally {
            await input.close();
            await output.close();
            _sockets.remove(input);
            _sockets.remove(output);
          }
        }

        unawaited(pump(client, upstream));
        unawaited(pump(upstream, client));
        return;
      }
      final upstream = await _http.openUrl(request.method, target);
      upstream.followRedirects = false;
      headers.forEach(upstream.headers.set);
      for (final name in ['range', 'if-range', 'accept', 'accept-language']) {
        final value = request.headers.value(name);
        if (value != null) upstream.headers.set(name, value);
      }
      final response = await upstream.close();
      if (response.statusCode >= 300 && response.statusCode < 400) {
        await response.drain<void>();
        request.response.statusCode = 502;
        await request.response.close();
        return;
      }
      request.response.statusCode = response.statusCode;
      for (final name in [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'content-disposition'
      ]) {
        final value = response.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      request.response.headers.set('cache-control', 'no-store');
      request.response.headers.set('referrer-policy', 'no-referrer');
      request.response.headers.set('x-content-type-options', 'nosniff');
      request.response.headers.set('content-security-policy',
          "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self' ws://127.0.0.1:${server.port}; font-src 'self' data:; base-uri 'none'; object-src 'none'; frame-ancestors 'none'");
      if (request.method == 'HEAD') {
        await response.drain<void>();
        await request.response.close();
      } else {
        await request.response.addStream(response);
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = 502;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
    for (final socket in _sockets.toList()) {
      unawaited(socket.close());
    }
    _sockets.clear();
    await server.close(force: true);
  }
}
