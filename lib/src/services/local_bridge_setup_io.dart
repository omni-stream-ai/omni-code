import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'local_bridge_setup.dart';
import 'local_bridge_startup.dart';

typedef BridgeCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

LocalBridgeSetupService createLocalBridgeSetupService() => _sharedSetupService;

final LocalBridgeSetupService _sharedSetupService =
    NativeLocalBridgeSetupService();

class NativeLocalBridgeSetupService implements LocalBridgeSetupService {
  NativeLocalBridgeSetupService({
    http.Client? httpClient,
    String? operatingSystem,
    Map<String, String>? environment,
    BridgeCommandRunner? runCommand,
    Future<void> Function(String, List<String>)? startDetached,
    this.readinessTimeout = const Duration(seconds: 45),
    this.pollInterval = const Duration(milliseconds: 500),
  })  : _providedClient = httpClient,
        _os = operatingSystem ?? Platform.operatingSystem,
        _environment = environment ?? Platform.environment,
        _run = runCommand ?? _runCommand,
        _startDetached = startDetached ?? _detach;

  static const _repository = 'omni-stream-ai/omni-code-bridge';
  static const _origin = 'http://127.0.0.1:8787';
  static const _requestTimeout = Duration(seconds: 30);
  // This client is validated against the workspace-agent API in this release.
  static final _minimumVersion = Version.parse('0.8.0-beta.3');
  final http.Client? _providedClient;
  final String _os;
  final Map<String, String> _environment;
  final BridgeCommandRunner _run;
  final Future<void> Function(String, List<String>) _startDetached;
  final Duration readinessTimeout;
  final Duration pollInterval;
  bool _busy = false;

  @override
  bool get isSupported => const ['linux', 'macos', 'windows'].contains(_os);

  @override
  Future<LocalBridgeSetupResult> installAndStart({
    required String clientId,
    required void Function(LocalBridgeSetupProgress) onProgress,
  }) async {
    if (!isSupported) {
      throw const LocalBridgeSetupException(
        LocalBridgeSetupFailure.unsupportedPlatform,
      );
    }
    if (_busy) {
      throw const LocalBridgeSetupException(LocalBridgeSetupFailure.busy);
    }
    _busy = true;
    final client = _providedClient ?? http.Client();
    RandomAccessFile? lock;
    Directory? temporary;
    var failure = LocalBridgeSetupFailure.installFailed;
    void report(LocalBridgeSetupStage stage, [double? fraction]) =>
        onProgress(LocalBridgeSetupProgress(stage, fraction: fraction));
    try {
      report(LocalBridgeSetupStage.checking);
      final home = _environment[_os == 'windows' ? 'USERPROFILE' : 'HOME'];
      if (home == null || home.isEmpty || clientId.trim().isEmpty) {
        throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.installFailed,
        );
      }
      final directory = Directory('$home/.omni-code-bridge');
      await directory.create(recursive: true);
      lock = await File('${directory.path}/desktop-setup.lock')
          .open(mode: FileMode.append);
      try {
        // A second window must not install or configure the service concurrently.
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const LocalBridgeSetupException(LocalBridgeSetupFailure.busy);
      }
      var executable = File(
        '${directory.path}/bin/omni-code-bridge${_os == 'windows' ? '.exe' : ''}',
      );
      final marker = File('${directory.path}/desktop-managed.json');
      final running = await _healthy(client);
      if (running && !await marker.exists()) {
        throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.existingBridge,
        );
      }
      if (!await executable.exists()) {
        executable = await _installedExecutable(home) ?? executable;
      }
      temporary = await directory.createTemp('desktop-install-');
      if (!await executable.exists()) {
        failure = LocalBridgeSetupFailure.downloadFailed;
        report(LocalBridgeSetupStage.downloading);
        final assetName = await _assetName();
        final asset = await _resolveRelease(client, assetName);
        final archive = File('${temporary.path}/$assetName');
        await _download(client, asset, archive, (value) {
          report(LocalBridgeSetupStage.downloading, value);
        });
        failure = LocalBridgeSetupFailure.verificationFailed;
        final expected = asset['digest'] as String?;
        if (expected == null ||
            !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(expected)) {
          throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.verificationFailed,
          );
        }
        final actual = await sha256.bind(archive.openRead()).first;
        if ('sha256:$actual' != expected.toLowerCase()) {
          throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.verificationFailed,
          );
        }
        failure = LocalBridgeSetupFailure.installFailed;
        report(LocalBridgeSetupStage.installing);
        final extracted = await _extract(archive, temporary);
        if (_os != 'windows') {
          await _checked('chmod', ['700', extracted.path]);
        }
        await _checkExecutableVersion(extracted.path, directory.path);
        await _checked(extracted.path, ['serve', '--help'],
            workingDirectory: directory.path);
        await executable.parent.create(recursive: true);
        await extracted.rename(executable.path);
      } else {
        await _checkExecutableVersion(executable.path, directory.path);
        await _checked(executable.path, ['serve', '--help'],
            workingDirectory: directory.path);
      }
      final separator = _os == 'windows' ? ';' : ':';
      final path = [
        executable.parent.path,
        '$home/.local/bin',
        '$home/.cargo/bin',
        if (_os == 'macos') '/opt/homebrew/bin',
        if (_os != 'windows') '/usr/local/bin',
        _environment['PATH'] ?? _environment['Path'] ?? '',
      ].join(separator);
      final startup = LocalBridgeStartup(
        home: home,
        executable: executable.path,
        directory: directory.path,
        path: path,
      );
      failure = LocalBridgeSetupFailure.startupFailed;
      report(LocalBridgeSetupStage.configuringStartup);
      // Retain ownership on partial failure, allowing a safe retry without
      // downloading again or mistaking our own running service for another one.
      await marker.writeAsString(jsonEncode({'executable': executable.path}),
          flush: true);
      await _configureStartup(startup, alreadyRunning: running);
      report(LocalBridgeSetupStage.starting);
      final deadline = DateTime.now().add(readinessTimeout);
      while (!await _healthy(client)) {
        if (DateTime.now().isAfter(deadline)) {
          throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.startupFailed,
          );
        }
        await Future<void>.delayed(pollInterval);
      }
      failure = LocalBridgeSetupFailure.authorizationFailed;
      report(LocalBridgeSetupStage.authorizing);
      return await _authorize(client,
          clientId: clientId,
          executable: executable.path,
          workingDirectory: directory.path,
          environment: startup.environment);
    } on LocalBridgeSetupException {
      rethrow;
    } catch (error) {
      // Process output can contain authorization tokens. Surface a localized
      // stage-specific message instead of including command output in the UI.
      throw LocalBridgeSetupException(failure,
          diagnostic: error is ProcessException
              ? 'Process failed (exit ${error.errorCode}): ${error.message}'
              : '${error.runtimeType}');
    } finally {
      try {
        if (temporary != null) await temporary.delete(recursive: true);
      } finally {
        await lock?.close();
        if (_providedClient == null) client.close();
        _busy = false;
      }
    }
  }

  Future<LocalBridgeSetupResult> connectToRunningBridge(
      {required String clientId}) async {
    final home = _environment[_os == 'windows' ? 'USERPROFILE' : 'HOME'];
    if (!isSupported || home == null) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.unsupportedPlatform);
    }
    final directory = Directory('$home/.omni-code-bridge');
    await directory.create(recursive: true);
    var executable = File(
        '${directory.path}/bin/omni-code-bridge${_os == 'windows' ? '.exe' : ''}');
    if (!await executable.exists()) {
      executable = await _installedExecutable(home) ?? executable;
    }
    final client = _providedClient ?? http.Client();
    try {
      if (!await _healthy(client)) {
        throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.startupFailed);
      }
      return await _authorize(client,
          clientId: clientId,
          executable: executable.path,
          workingDirectory: directory.path,
          environment: {'OMNI_CODE_HOME': '$home/.omni-code'});
    } on LocalBridgeSetupException {
      rethrow;
    } catch (_) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.authorizationFailed);
    } finally {
      if (_providedClient == null) client.close();
    }
  }

  Future<LocalBridgeSetupResult> _authorize(
    http.Client client, {
    required String clientId,
    required String executable,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final response = await client
        .post(
          Uri.parse('$_origin/client-auth/requests'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_id': clientId,
            'device_name': Platform.localHostname,
            'platform': _os,
          }),
        )
        .timeout(_requestTimeout);
    final request = _responseData(response);
    final requestId = request['request_id'] as String?;
    if (requestId == null || requestId.isEmpty) {
      throw const LocalBridgeSetupException(
        LocalBridgeSetupFailure.authorizationFailed,
      );
    }
    if (request['status'] != 'approved') {
      // Approve only the request created for this desktop client. Remote
      // devices retain the existing host approval flow.
      await _checked(
        executable,
        ['client-auth', 'approve', '--request-id', requestId],
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    final status = _responseData(await client
        .get(
          Uri.parse(
              '$_origin/client-auth/requests/${Uri.encodeComponent(requestId)}'),
        )
        .timeout(_requestTimeout));
    final token = status['token'] as String?;
    if (status['status'] != 'approved' || token == null || token.isEmpty) {
      throw const LocalBridgeSetupException(
        LocalBridgeSetupFailure.authorizationFailed,
      );
    }
    // A running old service can differ from the executable on disk. Verify the
    // authenticated API before persisting this connection or opening the home.
    final workspace = await client.get(
      Uri.parse('$_origin/workspace-agent'),
      headers: {
        'X-Omni-Code-Client-Id': clientId,
        'Authorization': 'Bearer $token',
      },
    ).timeout(_requestTimeout);
    if (workspace.statusCode == 404 || workspace.statusCode == 405) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.incompatibleVersion);
    }
    _responseData(workspace);
    return LocalBridgeSetupResult(url: _origin, token: token);
  }

  Future<void> _checkExecutableVersion(
      String executable, String directory) async {
    final result =
        await _run(executable, ['--version'], workingDirectory: directory);
    final text = result.stdout.toString().trim().split(RegExp(r'\s+')).last;
    final version = _releaseVersion(text);
    if (result.exitCode != 0 || version == null || version < _minimumVersion) {
      throw LocalBridgeSetupException(
          LocalBridgeSetupFailure.incompatibleVersion,
          diagnostic: 'Bridge must be at least $_minimumVersion.');
    }
  }

  static Version? _releaseVersion(Object? tag) {
    if (tag is! String) return null;
    try {
      return Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
    } on FormatException {
      return null;
    }
  }

  Future<String> _assetName() async {
    final machine = _os == 'windows'
        ? _environment['PROCESSOR_ARCHITEW6432'] ??
            _environment['PROCESSOR_ARCHITECTURE'] ??
            ''
        : (await _checked('uname', ['-m'])).stdout.toString().trim();
    final architecture = switch (machine.toLowerCase()) {
      'x86_64' || 'amd64' => 'x64',
      'aarch64' || 'arm64' when _os != 'windows' => 'arm64',
      _ => throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.unsupportedPlatform,
        ),
    };
    return 'omni-code-bridge-$_os-$architecture.${_os == 'windows' ? 'zip' : 'tar.gz'}';
  }

  Future<File?> _installedExecutable(String home) async {
    final separator = _os == 'windows' ? ';' : ':';
    final directories = [
      '$home/.cargo/bin',
      '$home/.local/bin',
      if (_os == 'macos') '/opt/homebrew/bin',
      ...(_environment['PATH'] ?? _environment['Path'] ?? '').split(separator),
    ];
    for (final directory in directories) {
      if (directory.isEmpty) continue;
      final candidate =
          File('$directory/omni-code-bridge${_os == 'windows' ? '.exe' : ''}');
      if (await candidate.exists()) return candidate;
    }
    return null;
  }

  Future<Map<String, dynamic>> _resolveRelease(
      http.Client client, String name) async {
    final response = await client.get(
      Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(_requestTimeout);
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.downloadFailed);
    }
    var hasCompatibleRelease = false;
    Map<String, dynamic>? assetFor(Map<String, dynamic> release) {
      final version = _releaseVersion(release['tag_name']);
      if (release['draft'] == true ||
          version == null ||
          version < _minimumVersion) {
        return null;
      }
      hasCompatibleRelease = true;
      for (final asset in (release['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        if (asset['name'] == name) return asset;
      }
      return null;
    }

    if (response.statusCode == 200) {
      final asset = assetFor(jsonDecode(response.body) as Map<String, dynamic>);
      if (asset != null) return asset;
    }
    // A stable release can exist while being too old for this client. In that
    // case prefer a compatible stable release, then a compatible prerelease.
    final fallback = await client.get(
      Uri.https('api.github.com', '/repos/$_repository/releases',
          {'per_page': '100'}),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(_requestTimeout);
    if (fallback.statusCode != 200) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.downloadFailed);
    }
    final releases = (jsonDecode(fallback.body) as List)
        .whereType<Map<String, dynamic>>()
        .where((release) => _releaseVersion(release['tag_name']) != null)
        .toList()
      ..sort((a, b) {
        final av = _releaseVersion(a['tag_name'])!;
        final bv = _releaseVersion(b['tag_name'])!;
        final ap = a['prerelease'] == true || av.isPreRelease;
        final bp = b['prerelease'] == true || bv.isPreRelease;
        return ap != bp ? (ap ? 1 : -1) : bv.compareTo(av);
      });
    for (final release in releases) {
      final asset = assetFor(release);
      if (asset != null) return asset;
    }
    throw LocalBridgeSetupException(
        hasCompatibleRelease
            ? LocalBridgeSetupFailure.downloadFailed
            : LocalBridgeSetupFailure.incompatibleVersion,
        diagnostic:
            'No matching release for $name at or above $_minimumVersion.');
  }

  Future<void> _download(http.Client client, Map<String, dynamic> asset,
      File file, void Function(double?) onProgress) async {
    final url = Uri.parse(asset['browser_download_url'] as String);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/$_repository/releases/download/')) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.downloadFailed);
    }
    final response =
        await client.send(http.Request('GET', url)).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.downloadFailed);
    }
    final sink = file.openWrite();
    var received = 0;
    final length = response.contentLength;
    try {
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 60))) {
        received += chunk.length;
        if (received > 512 * 1024 * 1024) {
          throw const LocalBridgeSetupException(
              LocalBridgeSetupFailure.downloadFailed);
        }
        sink.add(chunk);
        onProgress(length == null || length == 0
            ? null
            : (received / length).clamp(0, 1));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (length != null && received != length) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.downloadFailed);
    }
  }

  Future<File> _extract(File archive, Directory temporary) async {
    final output = await Directory('${temporary.path}/extracted').create();
    if (_os == 'windows') {
      final script = File('${temporary.path}/extract.ps1');
      await script.writeAsString(r'''
param([string]$Archive, [string]$Destination)
$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
''');
      await _checked('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        archive.path,
        output.path
      ]);
    } else {
      await _checked('tar', ['-xzf', archive.path, '-C', output.path]);
    }
    final name = 'omni-code-bridge${_os == 'windows' ? '.exe' : ''}';
    final files = await output
        .list(recursive: true, followLinks: false)
        .where((file) => file is File && file.uri.pathSegments.last == name)
        .toList();
    if (files.length != 1) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.installFailed);
    }
    return files.single as File;
  }

  Future<bool> _healthy(http.Client client) async {
    try {
      final response = await client
          .get(Uri.parse('$_origin/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map &&
            body['ok'] == true &&
            body['service'] == 'omni-code-bridge') {
          return true;
        }
      }
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.existingBridge);
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } on TimeoutException {
      return false;
    } on FormatException {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.existingBridge);
    }
  }

  Future<void> _configureStartup(LocalBridgeStartup startup,
      {required bool alreadyRunning}) async {
    if (_os == 'linux') {
      var systemd = false;
      try {
        systemd = (await _run('systemctl', ['--user', 'show-environment']))
                .exitCode ==
            0;
      } on ProcessException {
        /* Use XDG autostart on desktops without systemd. */
      }
      final config =
          _environment['XDG_CONFIG_HOME'] ?? '${startup.home}/.config';
      if (systemd) {
        await _write(
            '$config/systemd/user/${LocalBridgeStartup.serviceName}.service',
            startup.systemdUnit);
        await _checked('systemctl', ['--user', 'daemon-reload']);
        await _checked('systemctl', [
          '--user',
          'enable',
          '--now',
          '${LocalBridgeStartup.serviceName}.service'
        ]);
      } else {
        final launcher = '${startup.directory}/start-bridge.sh';
        await _write(launcher, startup.shellLauncher);
        await _write(
            '$config/autostart/${LocalBridgeStartup.serviceName}.desktop',
            startup.desktopEntry(launcher));
        if (!alreadyRunning) await _startDetached('/bin/sh', [launcher]);
      }
    } else if (_os == 'macos') {
      final plist =
          '${startup.home}/Library/LaunchAgents/${LocalBridgeStartup.launchAgentLabel}.plist';
      await _write(plist, startup.launchAgent);
      final uid =
          (await _checked('/usr/bin/id', ['-u'])).stdout.toString().trim();
      final target = 'gui/$uid/${LocalBridgeStartup.launchAgentLabel}';
      final loaded = await _run('/bin/launchctl', ['print', target]);
      await _checked('/bin/launchctl', ['enable', target]);
      if (loaded.exitCode != 0) {
        await _checked('/bin/launchctl', ['bootstrap', 'gui/$uid', plist]);
      }
      if (!alreadyRunning) {
        await _checked('/bin/launchctl', ['kickstart', target]);
      }
    } else {
      final appData = _environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.startupFailed);
      }
      final launcher = '${startup.directory}/start-bridge.ps1';
      final entry =
          '$appData/Microsoft/Windows/Start Menu/Programs/Startup/Omni Code Bridge.vbs';
      // Windows PowerShell 5 and Windows Script Host need explicit encodings
      // for paths containing characters outside the current system codepage.
      await File(launcher).writeAsBytes(
          [0xef, 0xbb, 0xbf, ...utf8.encode(startup.powershellLauncher)],
          flush: true);
      final startupFile = File(entry);
      await startupFile.parent.create(recursive: true);
      await startupFile.writeAsBytes([
        0xff,
        0xfe,
        for (final unit in startup.windowsStartup(launcher).codeUnits) ...[
          unit & 0xff,
          unit >> 8
        ]
      ], flush: true);
      if (!alreadyRunning) {
        await _startDetached('wscript.exe', ['//B', '//Nologo', entry]);
      }
    }
  }

  Future<ProcessResult> _checked(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await _run(executable, arguments,
        workingDirectory: workingDirectory, environment: environment);
    if (result.exitCode != 0) {
      throw ProcessException(
          executable,
          arguments,
          result.stderr
              .toString()
              .substring(0, result.stderr.toString().length.clamp(0, 4000)),
          result.exitCode);
    }
    return result;
  }

  static Map<String, dynamic> _responseData(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.authorizationFailed);
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  static Future<void> _write(String path, String value) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  static Future<ProcessResult> _runCommand(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(executable, arguments,
        workingDirectory: workingDirectory, environment: environment);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 45));
      return ProcessResult(process.pid, code, await stdout, await stderr);
    } on TimeoutException {
      process.kill();
      await Future.wait([stdout, stderr]);
      rethrow;
    }
  }

  static Future<void> _detach(String executable, List<String> arguments) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }
}
