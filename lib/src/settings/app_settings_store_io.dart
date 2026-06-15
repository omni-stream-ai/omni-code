import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_settings_store.dart';

class FileAppSettingsStore implements AppSettingsStore {
  @override
  Future<String?> read() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final file = await _settingsFile();
    await file.writeAsString(value, flush: true);
  }

  Future<File> _settingsFile() async {
    final directory = await _settingsDirectory();
    return File('${directory.path}/omni-code-settings.json');
  }

  Future<Directory> _settingsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      return directory;
    } on MissingPlatformDirectoryException {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        rethrow;
      }
      final fallback = Directory('$home/.config/omni-code');
      await fallback.create(recursive: true);
      return fallback;
    }
  }
}

AppSettingsStore createPlatformAppSettingsStore() => FileAppSettingsStore();
