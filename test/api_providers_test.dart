import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/providers/api_providers.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  test('caches the same project query and supports invalidation', () async {
    var calls = 0;
    final client = BridgeClient(
      httpClient: _FakeClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'project-1',
                'name': 'Project',
                'root_path': '/tmp/project',
                'updated_at': '2026-09-14T00:00:00.000Z',
                'session_count': 0,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [bridgeClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await container.read(projectProvider('project-1').future);
    await container.read(projectProvider('project-1').future);
    expect(calls, 1);

    await container.refresh(projectsProvider.future);
    await container.refresh(projectProvider('project-1').future);
    expect(calls, 2);
  });
}

class _MemoryStore implements AppSettingsStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String settings) async => value = settings;
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.Request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copied = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    final response = await handler(copied);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
