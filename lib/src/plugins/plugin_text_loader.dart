import 'plugin_text_loader_stub.dart'
    if (dart.library.io) 'plugin_text_loader_io.dart';

abstract class PluginTextLoader {
  Future<String> load(String location);
}

PluginTextLoader createPluginTextLoader() => createPlatformPluginTextLoader();
