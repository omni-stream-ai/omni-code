import 'plugin_text_loader.dart';

class UnsupportedPluginTextLoader implements PluginTextLoader {
  @override
  Future<String> load(String location) async {
    throw UnsupportedError(
      'Local plugin sources are not supported on this platform: $location',
    );
  }
}

PluginTextLoader createPlatformPluginTextLoader() =>
    UnsupportedPluginTextLoader();
