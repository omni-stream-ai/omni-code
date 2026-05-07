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
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/omni-code-settings.json');
  }
}

AppSettingsStore createPlatformAppSettingsStore() => FileAppSettingsStore();
