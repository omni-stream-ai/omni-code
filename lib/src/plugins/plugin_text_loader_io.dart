import 'dart:io';

import 'plugin_text_loader.dart';

class FilePluginTextLoader implements PluginTextLoader {
  @override
  Future<String> load(String location) async {
    final file = _resolveFile(location);
    if (!await file.exists()) {
      throw Exception('Plugin source file not found: ${file.path}');
    }
    return file.readAsString();
  }

  File _resolveFile(String location) {
    final trimmed = location.trim();
    if (trimmed.isEmpty) {
      throw Exception('Plugin source location is empty.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'file') {
      return File.fromUri(uri);
    }
    return File(trimmed);
  }
}

PluginTextLoader createPlatformPluginTextLoader() => FilePluginTextLoader();
