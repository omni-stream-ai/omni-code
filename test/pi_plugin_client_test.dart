import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/pi_plugins_screen.dart';

void main() {
  test('infers plugin source kind from the source value', () {
    expect(inferPiPluginSourceKind('npm:@scope/plugin@1', false),
        PiPluginSourceKind.npm);
    expect(inferPiPluginSourceKind('https://example.test/plugin.js', false),
        PiPluginSourceKind.url);
    expect(inferPiPluginSourceKind('git@github.com:org/plugin.git', false),
        PiPluginSourceKind.git);
    expect(inferPiPluginSourceKind('/tmp/plugin', false),
        PiPluginSourceKind.local);
    expect(inferPiPluginSourceKind('', true), PiPluginSourceKind.upload);
  });

  test('lists Pi plugins from the v2 API', () async {
    final client = BridgeClient(httpClient: _Client((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v2/pi/plugins');
      return http.Response(
          jsonEncode({
            'data': [_pluginJson()]
          }),
          200,
          headers: {'content-type': 'application/json'});
    }));
    final plugins = await client.getPiPlugins();
    expect(plugins.single.id, 'formatter');
    expect(plugins.single.projectIds, ['project-a']);
  });

  test('installs, updates, validates and removes a Pi plugin', () async {
    final requests = <http.Request>[];
    final client = BridgeClient(httpClient: _Client((request) async {
      requests.add(request);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response(
          jsonEncode({'data': _pluginJson()}),
          request.method == 'POST' && request.url.path == '/v2/pi/plugins'
              ? 201
              : 200,
          headers: {'content-type': 'application/json'});
    }));
    await client.installPiPlugin(
        source: const PiPluginSource(
            kind: PiPluginSourceKind.url, value: 'https://example.test/ext.js'),
        sha256: 'abc',
        projectIds: ['project-a']);
    await client
        .updatePiPlugin('formatter', enabled: false, config: {'level': 2});
    await client.validatePiPlugin('formatter');
    await client.removePiPlugin('formatter');
    expect(requests.map((r) => r.method), ['POST', 'PATCH', 'POST', 'DELETE']);
    expect(jsonDecode(requests[0].body)['source']['kind'], 'url');
    expect(jsonDecode(requests[1].body), {
      'enabled': false,
      'config': {'level': 2}
    });
  });
}

Map<String, dynamic> _pluginJson() => {
      'id': 'formatter',
      'name': 'Formatter',
      'version': '1.0.0',
      'source': {'kind': 'url', 'value': 'https://example.test/ext.js'},
      'entry_path': 'installed/formatter/ext.js',
      'sha256': 'abc',
      'enabled': true,
      'project_ids': ['project-a'],
      'config': {},
      'installed_at': '2026-08-20T00:00:00Z',
      'validation_error': null,
      'permissions': ['fs.read'],
    };

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.Response> Function(http.Request) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copied = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    copied.bodyBytes = await request.finalize().toBytes();
    final response = await handler(copied);
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers, request: request);
  }
}
