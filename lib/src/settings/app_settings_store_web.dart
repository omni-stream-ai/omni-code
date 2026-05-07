import 'dart:html' as html;

import 'app_settings_store.dart';

class WebAppSettingsStore implements AppSettingsStore {
  static const _storageKey = 'omni-code-settings';

  @override
  Future<String?> read() async {
    return html.window.localStorage[_storageKey];
  }

  @override
  Future<void> write(String value) async {
    html.window.localStorage[_storageKey] = value;
  }
}

AppSettingsStore createPlatformAppSettingsStore() => WebAppSettingsStore();
