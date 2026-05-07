import 'app_settings_store_stub.dart'
    if (dart.library.io) 'app_settings_store_io.dart'
    if (dart.library.html) 'app_settings_store_web.dart';

abstract class AppSettingsStore {
  Future<String?> read();
  Future<void> write(String value);
}

AppSettingsStore createAppSettingsStore() => createPlatformAppSettingsStore();
