import 'desktop_window_service_stub.dart'
    if (dart.library.io) 'desktop_window_service_io.dart'
    if (dart.library.html) 'desktop_window_service_web.dart' as platform;

Future<void> openDesktopWindow() => platform.openDesktopWindow();
