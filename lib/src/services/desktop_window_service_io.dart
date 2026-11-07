import 'dart:io';

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
  // Each process owns a window and its Flutter engine. Windows resolves the
  // application's data directory relative to the working directory.
  await Process.start(
    executable.path,
    const [],
    workingDirectory: executable.parent.path,
    mode: ProcessStartMode.detached,
  );
}
