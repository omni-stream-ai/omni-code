import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/src/plugins/speech_plugin_models.dart';
import 'package:omni_code/src/plugins/plugin_text_loader.dart';
import 'package:omni_code/src/plugins/speech_plugin_registry.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  test('fetches repository index', () async {
    final registry = SpeechPluginRegistry(
      httpClient: _FakeHttpClient((request) async {
        expect(
          request.url.toString(),
          'https://example.com/community-plugins.json',
        );
        return http.Response(
          jsonEncode([
            {
              'id': 'tts-1',
              'name': 'TTS 1',
              'author': 'Vendor',
              'description': 'Plugin',
              'repo': 'vendor/tts-1',
              'registration_url': 'https://example.com/signup',
              'manifest_url': 'https://example.com/tts-1.json',
              'capabilities': ['tts'],
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final index = await registry.fetchRepositoryIndex(
      const SpeechPluginSource(
        id: 'official',
        name: 'Official',
        indexUrl: 'https://example.com/community-plugins.json',
      ),
    );

    expect(index.plugins, hasLength(1));
    expect(index.plugins.single.id, 'tts-1');
    expect(index.plugins.single.registrationUrl, 'https://example.com/signup');
  });

  test('installs plugin and selects by capability', () async {
    final registry = SpeechPluginRegistry(
      httpClient: _FakeHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'tts-1',
            'name': 'TTS 1',
            'vendor': 'Vendor',
            'version': '1.0.0',
            'registration_url': 'https://example.com/signup',
            'capabilities': ['tts'],
            'transport': 'openai_compatible',
            'base_url': 'https://example.com/v1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await registry.installFromRepositoryEntry(
      const SpeechPluginRepositoryEntry(
        id: 'tts-1',
        name: 'TTS 1',
        author: 'Vendor',
        description: 'Plugin',
        repo: 'vendor/tts-1',
        sourceId: 'official',
        manifestUrl: 'https://example.com/tts-1.json',
      ),
    );
    await registry.selectPluginForCapability(
      SpeechPluginCapability.tts,
      'tts-1',
    );

    final installed = registry.listInstalledSync();
    expect(installed, hasLength(1));
    expect(
      installed.single.manifest.registrationUrl,
      'https://example.com/signup',
    );
    expect(
      appSettingsController.settings.selectedSpeechPluginByCapability['tts'],
      'tts-1',
    );
  });

  test('fetches repository index from a local file path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'speech-plugin-registry-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final indexFile = File('${directory.path}/community-plugins.json');
    await indexFile.writeAsString(
      jsonEncode({
        'plugins': [
          {
            'id': 'volc-tts',
            'name': 'Volc TTS',
            'author': 'Vendor',
            'manifest_url': 'file://${directory.path}/volc-tts.json',
            'capabilities': ['tts'],
          },
        ],
      }),
    );

    final registry = SpeechPluginRegistry(
      httpClient: _FakeHttpClient.unused(),
      textLoader: _FileSystemPluginTextLoader(),
    );

    final index = await registry.fetchRepositoryIndex(
      SpeechPluginSource(
        id: 'local',
        name: 'Local',
        indexUrl: indexFile.path,
      ),
    );

    expect(index.plugins, hasLength(1));
    expect(index.plugins.single.id, 'volc-tts');
    expect(
      index.plugins.single.resolvedManifestUrl,
      'file://${directory.path}/volc-tts.json',
    );
  });

  test('resolves local manifest_path relative to local index file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'speech-plugin-registry-relative-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pluginsDirectory = Directory('${directory.path}/plugins/volc-tts');
    await pluginsDirectory.create(recursive: true);
    final manifestFile = File('${pluginsDirectory.path}/manifest.json');
    await manifestFile.writeAsString(
      jsonEncode({
        'id': 'volc-tts',
        'name': 'Volc TTS',
        'vendor': 'Vendor',
        'version': '1.0.0',
        'capabilities': ['tts'],
        'transport': 'openai_compatible',
      }),
    );
    final indexFile = File('${directory.path}/community-plugins.json');
    await indexFile.writeAsString(
      jsonEncode([
        {
          'id': 'volc-tts',
          'name': 'Volc TTS',
          'author': 'Vendor',
          'manifest_path': 'plugins/volc-tts/manifest.json',
          'capabilities': ['tts'],
        },
      ]),
    );

    final registry = SpeechPluginRegistry(
      httpClient: _FakeHttpClient.unused(),
      textLoader: _FileSystemPluginTextLoader(),
    );

    final index = await registry.fetchRepositoryIndex(
      SpeechPluginSource(
        id: 'local',
        name: 'Local',
        indexUrl: indexFile.path,
      ),
    );
    final manifest = await registry.fetchManifest(
      index.plugins.single.resolvedManifestUrl,
    );

    expect(manifest.id, 'volc-tts');
    expect(manifest.name, 'Volc TTS');
  });
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    value = next;
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient.unused() : _handler = _unusedHandler;

  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      nextRequest.body = request.body;
      nextRequest.encoding = request.encoding;
    }
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }

  static Future<http.Response> _unusedHandler(http.Request request) {
    throw StateError('HTTP client should not be called in this test.');
  }
}

class _FileSystemPluginTextLoader implements PluginTextLoader {
  @override
  Future<String> load(String location) async {
    final uri = Uri.tryParse(location);
    final file = uri != null && uri.scheme == 'file'
        ? File.fromUri(uri)
        : File(location);
    return file.readAsString();
  }
}
