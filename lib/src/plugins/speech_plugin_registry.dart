import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/app_settings.dart';
import 'plugin_text_loader.dart';
import 'speech_plugin_models.dart';

const defaultSpeechPluginRepositoryIndexUrl =
    'https://raw.githubusercontent.com/omni-stream-ai/omni-code-plugins/main/community-plugins.json';

const defaultSpeechPluginRepositorySourceId = 'official';
const defaultSpeechPluginRepositorySourceName = 'Official Plugins';

class SpeechPluginRegistry {
  SpeechPluginRegistry({
    http.Client? httpClient,
    PluginTextLoader? textLoader,
  }) : _httpClient = httpClient ?? http.Client(),
       _textLoader = textLoader ?? createPluginTextLoader();

  final http.Client _httpClient;
  final PluginTextLoader _textLoader;

  Future<SpeechPluginRepositoryIndex> fetchRepositoryIndex(
    SpeechPluginSource source,
  ) async {
    final url = source.indexUrl.trim();
    if (url.isEmpty) {
      throw Exception('Speech plugin repository URL is empty.');
    }
    final body = await _loadText(url, resourceLabel: 'speech plugin index');
    return SpeechPluginRepositoryIndex.fromJson(
      jsonDecode(body),
      source: source,
    );
  }

  Future<List<SpeechPluginRepositoryIndex>> fetchRepositoryIndexes({
    List<SpeechPluginSource>? sources,
  }) async {
    final nextSources = (sources ?? configuredSources())
        .where((source) => source.enabled && source.indexUrl.trim().isNotEmpty)
        .toList(growable: false);
    final indexes = <SpeechPluginRepositoryIndex>[];
    for (final source in nextSources) {
      indexes.add(await fetchRepositoryIndex(source));
    }
    return indexes;
  }

  Future<SpeechPluginManifest> fetchManifest(String manifestUrl) async {
    final url = manifestUrl.trim();
    if (url.isEmpty) {
      throw Exception('Speech plugin manifest URL is empty.');
    }
    final body = await _loadText(url, resourceLabel: 'speech plugin manifest');
    return SpeechPluginManifest.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
  }

  Future<List<InstalledSpeechPlugin>> listInstalled() async {
    final raw = appSettingsController.settings.installedSpeechPlugins;
    return raw
        .map((item) {
          try {
            return InstalledSpeechPlugin.fromJson(item);
          } catch (_) {
            return null;
          }
        })
        .whereType<InstalledSpeechPlugin>()
        .where((item) => item.manifest.id.isNotEmpty)
        .toList(growable: false);
  }

  InstalledSpeechPlugin? findInstalledById(String pluginId) {
    final normalizedId = pluginId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final plugin in listInstalledSync()) {
      if (plugin.manifest.id == normalizedId) {
        return plugin;
      }
    }
    return null;
  }

  List<InstalledSpeechPlugin> listInstalledSync() {
    final raw = appSettingsController.settings.installedSpeechPlugins;
    return raw
        .map((item) {
          try {
            return InstalledSpeechPlugin.fromJson(item);
          } catch (_) {
            return null;
          }
        })
        .whereType<InstalledSpeechPlugin>()
        .where((item) => item.manifest.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> installFromRepositoryEntry(
    SpeechPluginRepositoryEntry entry,
  ) async {
    final manifest = await fetchManifest(entry.resolvedManifestUrl);
    await installManifest(manifest);
  }

  Future<void> installManifest(SpeechPluginManifest manifest) async {
    if (manifest.id.isEmpty) {
      throw Exception('Speech plugin manifest is missing id.');
    }
    final installed = listInstalledSync()
        .where((item) => item.manifest.id != manifest.id)
        .toList(growable: true);
    installed.add(
      InstalledSpeechPlugin(
        installedAt: DateTime.now(),
        manifest: manifest,
      ),
    );
    await _saveInstalled(installed);
  }

  Future<void> uninstall(String pluginId) async {
    final normalizedId = pluginId.trim();
    final installed = listInstalledSync()
        .where((item) => item.manifest.id != normalizedId)
        .toList(growable: false);

    final nextSelections = Map<String, String?>.from(
      appSettingsController.settings.selectedSpeechPluginByCapability,
    );
    final nextApiKeysByPluginId = Map<String, String>.from(
      appSettingsController.settings.speechPluginApiKeysByPluginId,
    );
    for (final entry in nextSelections.entries.toList()) {
      if (entry.value == normalizedId) {
        nextSelections.remove(entry.key);
      }
    }
    nextApiKeysByPluginId.remove(normalizedId);

    final next = appSettingsController.settings.copyWith(
      installedSpeechPlugins:
          installed.map((item) => item.toJson()).toList(growable: false),
      selectedSpeechPluginByCapability: nextSelections,
      speechPluginApiKeysByPluginId: nextApiKeysByPluginId,
    );
    await appSettingsController.save(next);
  }

  Future<void> selectPluginForCapability(
    SpeechPluginCapability capability,
    String? pluginId,
  ) async {
    final normalizedPluginId = pluginId?.trim();
    if (normalizedPluginId?.isNotEmpty == true) {
      final installed = findInstalledById(normalizedPluginId!);
      if (installed == null) {
        throw Exception('Speech plugin is not installed: $normalizedPluginId');
      }
      if (!installed.manifest.supports(capability)) {
        throw Exception(
          'Speech plugin does not support capability ${capability.id}: $normalizedPluginId',
        );
      }
    }

    final nextSelections = Map<String, String?>.from(
      appSettingsController.settings.selectedSpeechPluginByCapability,
    );
    if (normalizedPluginId == null || normalizedPluginId.isEmpty) {
      nextSelections.remove(capability.id);
    } else {
      nextSelections[capability.id] = normalizedPluginId;
    }
    await appSettingsController.save(
      appSettingsController.settings.copyWith(
        selectedSpeechPluginByCapability: nextSelections,
      ),
    );
  }

  List<InstalledSpeechPlugin> installedForCapability(
    SpeechPluginCapability capability,
  ) {
    return listInstalledSync()
        .where((item) => item.manifest.supports(capability))
        .toList(growable: false);
  }

  String? selectedPluginIdForCapability(SpeechPluginCapability capability) {
    return appSettingsController
        .settings.selectedSpeechPluginByCapability[capability.id];
  }

  InstalledSpeechPlugin? selectedPluginForCapability(
    SpeechPluginCapability capability,
  ) {
    final pluginId = selectedPluginIdForCapability(capability);
    if (pluginId == null || pluginId.trim().isEmpty) {
      return null;
    }
    return findInstalledById(pluginId);
  }

  String configuredApiKeyForPluginId(String pluginId) {
    final normalizedId = pluginId.trim();
    if (normalizedId.isEmpty) {
      return '';
    }
    return appSettingsController.settings.speechPluginApiKeysByPluginId[
            normalizedId] ??
        '';
  }

  String effectiveApiKeyForManifest(SpeechPluginManifest manifest) {
    final configuredApiKey = configuredApiKeyForPluginId(manifest.id);
    if (configuredApiKey.isNotEmpty) {
      return configuredApiKey;
    }
    final manifestApiKey = manifest.apiKey.trim();
    if (manifestApiKey.isNotEmpty) {
      return manifestApiKey;
    }
    for (final config in manifest.capabilityConfigs.values) {
      final capabilityApiKey = config.apiKey.trim();
      if (capabilityApiKey.isNotEmpty) {
        return capabilityApiKey;
      }
    }
    return '';
  }

  Map<String, String> configuredSettingsForPluginId(String pluginId) {
    final normalizedId = pluginId.trim();
    if (normalizedId.isEmpty) {
      return const {};
    }
    return appSettingsController
            .settings
            .speechPluginSettingsByPluginId[normalizedId] ??
        const {};
  }

  List<SpeechPluginSource> configuredSources() {
    return const [
      SpeechPluginSource(
        id: defaultSpeechPluginRepositorySourceId,
        name: defaultSpeechPluginRepositorySourceName,
        indexUrl: defaultSpeechPluginRepositoryIndexUrl,
      ),
    ];
  }

  Future<void> _saveInstalled(List<InstalledSpeechPlugin> installed) async {
    final next = appSettingsController.settings.copyWith(
      installedSpeechPlugins:
          installed.map((item) => item.toJson()).toList(growable: false),
    );
    await appSettingsController.save(next);
  }

  Future<String> _loadText(
    String location, {
    required String resourceLabel,
  }) async {
    if (_isLocalLocation(location)) {
      return _textLoader.load(location);
    }
    final response = await _httpClient.get(Uri.parse(location));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load $resourceLabel (${response.statusCode}).',
      );
    }
    return response.body;
  }

  bool _isLocalLocation(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return true;
    }
    if (uri.scheme == 'file') {
      return true;
    }
    return uri.scheme.isEmpty;
  }
}

final speechPluginRegistry = SpeechPluginRegistry();
