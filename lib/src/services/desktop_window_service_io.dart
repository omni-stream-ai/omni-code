import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> openDesktopWindow() async {
  if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
    throw UnsupportedError(
        'Desktop windows are not supported on this platform');
  }
  final executable = File(Platform.resolvedExecutable);
  if (Platform.isMacOS) {
    final bundle = executable.parent.parent.parent;
    if (bundle.path.endsWith('.app')) {
      final result = await Process.run('/usr/bin/open', ['-n', bundle.path]);
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      return;
    }
  }
  if (Platform.isLinux) {
    String? logPath;
    try {
      final support = await getApplicationSupportDirectory();
      final directory =
          await Directory('${support.path}/logs').create(recursive: true);
      final log = File('${directory.path}/desktop-window.log');
      if (await log.exists() && await log.length() > 1024 * 1024) {
        await log.rename('${log.path}.previous');
      }
      await (await log.open(mode: FileMode.append)).close();
      logPath = log.path;
    } on FileSystemException {
      // A log directory failure must not prevent opening a window.
    } on MissingPlatformDirectoryException {
      // Minimal desktop sessions may not expose a support directory.
    }
    if (logPath != null) {
      // Pass paths as positional arguments so spaces and shell characters keep
      // their literal meaning. Detached mode otherwise discards startup errors.
      await Process.start(
        '/bin/sh',
        [
          '-c',
          r'''exec >>"$1" 2>&1
shift
printf '\nOmni Code window startup (pid %s)\n' "$$"
exec "$@"''',
          'omni-code-window',
          logPath,
          executable.path,
        ],
        workingDirectory: executable.parent.path,
        mode: ProcessStartMode.detached,
      );
      return;
    }
  }
  // Each process owns a window and its Flutter engine. Windows resolves the
  // application's data directory relative to the working directory.
  await Process.start(
    executable.path,
    const [],
    workingDirectory: executable.parent.path,
    mode: ProcessStartMode.detached,
  );
}
