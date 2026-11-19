import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'bridge_setup_agent_host.dart';
import 'local_bridge_setup.dart';
import 'local_bridge_setup_io.dart';

BridgeSetupAgentHost createBridgeSetupAgentHost() =>
    NativeBridgeSetupAgentHost();

class NativeBridgeSetupAgentHost implements BridgeSetupAgentHost {
  NativeBridgeSetupAgentHost(
      {Map<String, String>? environment,
      this.commandTimeout = const Duration(seconds: 120)})
      : _environment = environment ?? Platform.environment;
  final Map<String, String> _environment;
  final Duration commandTimeout;
  Process? _process;
  bool _closed = false;
  String? get _home =>
      _environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];

  @override
  bool get isSupported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  Future<List<ModelProviderConfig>> discoverProviders() async {
    final home = _home;
    if (!isSupported || home == null) return [];
    final path = _environment['OMNI_CODE_SETTINGS_PATH'] ??
        '${_environment['OMNI_CODE_HOME'] ?? '$home/.omni-code'}/settings.json';
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() > 4 * 1024 * 1024) {
        return [];
      }
      final data = jsonDecode(await file.readAsString()) as Map;
      return (data['model_providers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ModelProviderConfig.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> diagnostics() async {
    final home = _home;
    if (!isSupported || home == null) {
      return {'platform': Platform.operatingSystem};
    }
    final result = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'home': home,
      'shell': Platform.isWindows ? 'PowerShell' : '/bin/sh',
      'installation_directory': '$home/.omni-code-bridge',
      'bridge_data_directory': '$home/.omni-code',
      'bridge_url': 'http://127.0.0.1:8787',
      'automatic_startup': 'current user sign-in',
    };
    if (Platform.isLinux) {
      final release = File('/etc/os-release');
      if (await release.exists()) {
        result['os_release'] = await release.readAsString();
      }
    }
    for (final name in ['bridge.log', 'bridge-error.log']) {
      final file = File('$home/.omni-code-bridge/$name');
      if (!await file.exists()) continue;
      final input = await file.open();
      try {
        final length = await input.length();
        await input.setPosition((length - 6000).clamp(0, length));
        result[name] =
            utf8.decode(await input.read(6000), allowMalformed: true);
      } finally {
        await input.close();
      }
    }
    return result;
  }

  @override
  Future<BridgeAgentCommandResult> runCommand(String command) async {
    if (_closed ||
        !isSupported ||
        _process != null ||
        command.trim().isEmpty ||
        command.length > 16000) {
      throw StateError('Command unavailable');
    }
    final home = _home;
    if (home == null) throw StateError('User directory unavailable');
    // UTF-16LE EncodedCommand preserves PowerShell syntax and Unicode paths.
    final encoded = base64Encode([
      for (final unit in command.codeUnits) ...[unit & 0xff, unit >> 8]
    ]);
    final process = await Process.start(
      Platform.isWindows ? 'powershell.exe' : '/bin/sh',
      Platform.isWindows
          ? ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded]
          : ['-c', command],
      workingDirectory: home,
      environment: {
        'PATH': [
          '$home/.omni-code-bridge/bin',
          '$home/.cargo/bin',
          '$home/.local/bin',
          if (Platform.isMacOS) '/opt/homebrew/bin',
          _environment['PATH'] ?? _environment['Path'] ?? '',
        ].join(Platform.isWindows ? ';' : ':')
      },
    );
    _process = process;
    if (_closed) unawaited(_terminate(process));
    final output = StringBuffer();
    var size = 0;
    void capture(String text) {
      final available = (24000 - size).clamp(0, 24000);
      if (available > 0) {
        output.write(text.substring(0, text.length.clamp(0, available)));
      }
      size += text.length;
    }

    final outDone = Completer<void>();
    final errDone = Completer<void>();
    final out = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(capture, onDone: outDone.complete, onError: (Object _) {
      if (!outDone.isCompleted) outDone.complete();
    });
    final err = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(capture, onDone: errDone.complete, onError: (Object _) {
      if (!errDone.isCompleted) errDone.complete();
    });
    try {
      final code = await process.exitCode.timeout(commandTimeout);
      // Drain buffered output, without waiting on pipes inherited by a service
      // that a successful command intentionally started in the background.
      try {
        await Future.wait([outDone.future, errDone.future])
            .timeout(const Duration(seconds: 1));
      } on TimeoutException {
        /* Closing the subscriptions releases the pipes. */
      }
      return BridgeAgentCommandResult(
          exitCode: code, output: output.toString());
    } on TimeoutException {
      await _terminate(process);
      return BridgeAgentCommandResult(
          exitCode: -1, output: 'Command timed out.\n$output');
    } finally {
      await out.cancel();
      await err.cancel();
      _process = null;
    }
  }

  @override
  Future<LocalBridgeSetupResult> connect(String clientId) =>
      NativeLocalBridgeSetupService(environment: _environment)
          .connectToRunningBridge(clientId: clientId);

  Future<void> _terminate(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run(
                'taskkill.exe', ['/PID', '${process.pid}', '/T', '/F'])
            .timeout(const Duration(seconds: 2));
      } else {
        // Inspect PIDs only, keeping process arguments and credentials private.
        final listing = await Process.run('ps', ['-A', '-o', 'pid=,ppid='])
            .timeout(const Duration(seconds: 2));
        final children = <int, List<int>>{};
        for (final line in listing.stdout.toString().split('\n')) {
          final fields = line.trim().split(RegExp(r'\s+'));
          if (fields.length != 2) continue;
          final pid = int.tryParse(fields[0]), parent = int.tryParse(fields[1]);
          if (pid != null && parent != null) {
            (children[parent] ??= []).add(pid);
          }
        }
        final descendants = <int>[process.pid];
        for (var index = 0;
            index < descendants.length && index < 1024;
            index++) {
          descendants.addAll(children[descendants[index]] ?? const []);
        }
        for (final pid in descendants.reversed) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
      }
    } catch (_) {
      // Inspection can be denied, or the process may already have exited.
    } finally {
      process.kill(ProcessSignal.sigkill);
    }
  }

  @override
  void close() {
    _closed = true;
    final process = _process;
    if (process != null) unawaited(_terminate(process));
  }
}
