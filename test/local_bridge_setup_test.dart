import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/services/local_bridge_setup.dart';
import 'package:omni_code/src/services/local_bridge_setup_io.dart';
import 'package:omni_code/src/services/local_bridge_startup.dart';

void main() {
  late _SetupFixture fixture;
  setUp(() async => fixture = await _SetupFixture.create());
  tearDown(() async => fixture.root.delete(recursive: true));

  test(
      'downloads, verifies, installs, enables startup and authorizes only this client',
      () async {
    final stages = <LocalBridgeSetupStage>[];
    final result = await fixture.service().installAndStart(
        clientId: 'desktop-client',
        onProgress: (progress) => stages.add(progress.stage));

    expect(result.url, 'http://127.0.0.1:8787');
    expect(result.token, 'local-token');
    expect(fixture.downloads, 1);
    expect(await fixture.binary.readAsString(), fixture.binaryContents);
    expect(fixture.approvals, [
      ['client-auth', 'approve', '--request-id', 'desktop-request']
    ]);
    expect(fixture.requestedClientId, 'desktop-client');
    final unit = await File(
            '${fixture.home}/.config/systemd/user/omni-code-desktop-bridge.service')
        .readAsString();
    expect(unit, contains('WantedBy=default.target'));
    expect(unit, contains('OMNI_CODE_HOME=${fixture.home}/.omni-code'));
    expect(
        fixture.commands,
        contains(
            'systemctl --user enable --now omni-code-desktop-bridge.service'));
    expect(stages.toSet(), containsAll(LocalBridgeSetupStage.values));
    expect(
        await Directory('${fixture.home}/.omni-code-bridge')
            .list()
            .where((file) => file.path.contains('desktop-install-'))
            .length,
        0);
  });

  test('retry reuses installed binary and an approved request', () async {
    final service = fixture.service();
    await service.installAndStart(
        clientId: 'desktop-client', onProgress: (_) {});
    await service.installAndStart(
        clientId: 'desktop-client', onProgress: (_) {});
    expect(fixture.downloads, 1);
    expect(fixture.approvals, hasLength(1));
  });

  test('Agent can authorize a separately repaired healthy local Bridge',
      () async {
    await fixture.seedBinary();
    fixture.ready = true;
    final result = await fixture
        .service()
        .connectToRunningBridge(clientId: 'desktop-client');
    expect(result.token, 'local-token');
    expect(fixture.downloads, 0);
    expect(fixture.approvals.single,
        ['client-auth', 'approve', '--request-id', 'desktop-request']);
    expect(fixture.commands.any((command) => command.startsWith('systemctl')),
        isFalse);
  });

  test(
      'reuses a Bridge installed by another package manager without downloading',
      () async {
    final installed = File('${fixture.home}/.cargo/bin/omni-code-bridge');
    await installed.parent.create(recursive: true);
    await installed.writeAsString(fixture.binaryContents);
    final result = await fixture
        .service()
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    expect(result.token, 'local-token');
    expect(fixture.downloads, 0);
    expect(await fixture.binary.exists(), isFalse);
    final unit = await File(
            '${fixture.home}/.config/systemd/user/omni-code-desktop-bridge.service')
        .readAsString();
    expect(unit, contains(installed.path));
  });

  test('leaves an existing running Bridge untouched', () async {
    fixture.ready = true;
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.existingBridge)));
    expect(fixture.downloads, 0);
    expect(fixture.commands, isEmpty);
    expect(await fixture.binary.exists(), isFalse);
  });

  test('checksum mismatch never executes the download and can be retried',
      () async {
    fixture.badChecksum = true;
    final service = fixture.service();
    await expectLater(
        service.installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.verificationFailed)));
    expect(await fixture.binary.exists(), isFalse);
    expect(
        fixture.commands.where((command) =>
            command.contains('serve') || command.contains('systemctl')),
        isEmpty);
    fixture.badChecksum = false;
    final result = await service.installAndStart(
        clientId: 'desktop-client', onProgress: (_) {});
    expect(result.token, 'local-token');
  });

  test(
      'startup failure is reported before authorization and retry skips download',
      () async {
    fixture.failStartup = true;
    final service = fixture.service();
    await expectLater(
        service.installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.startupFailed)));
    expect(fixture.requestedClientId, isNull);
    fixture.failStartup = false;
    await service.installAndStart(
        clientId: 'desktop-client', onProgress: (_) {});
    expect(fixture.downloads, 1);
  });

  test('a service that never becomes healthy does not authorize a client',
      () async {
    fixture.neverReady = true;
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.startupFailed)));
    expect(fixture.requestedClientId, isNull);
  });

  test('uses prereleases when the repository has no stable release', () async {
    fixture.onlyPrereleases = true;
    final result = await fixture
        .service()
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    expect(result.token, 'local-token');
    expect(fixture.downloads, 1);
  });

  test('skips an old stable release and installs a compatible prerelease',
      () async {
    fixture.stableVersion = '0.7.1';
    fixture.listedVersions = ['0.7.1', '0.8.0-beta.3'];
    await fixture
        .service()
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    expect(fixture.downloadedVersions, ['0.8.0-beta.3']);
  });

  test('old or invalid releases are rejected before any download or execution',
      () async {
    fixture.stableVersion = '0.7.1';
    fixture.listedVersions = ['0.7.1', '0.8.0-beta.2', 'not-a-version'];
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.incompatibleVersion)));
    expect(fixture.downloads, 0);
    expect(await fixture.binary.exists(), isFalse);
    expect(fixture.approvals, isEmpty);
  });

  test('an old installed binary is left untouched and is not started',
      () async {
    await fixture.seedBinary();
    fixture.binaryVersion = '0.7.1';
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.incompatibleVersion)));
    expect(await fixture.binary.readAsString(), fixture.binaryContents);
    expect(fixture.downloads, 0);
    expect(fixture.commands.any((command) => command.contains('systemctl')),
        isFalse);
    expect(fixture.approvals, isEmpty);
  });

  test('a stale running service cannot complete setup with a newer binary',
      () async {
    fixture.workspaceStatus = 404;
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.incompatibleVersion)));
    expect(fixture.workspaceClientId, 'desktop-client');
  });

  test('an executable without version support is rejected before startup',
      () async {
    await fixture.seedBinary();
    fixture.versionFlagSupported = false;
    await expectLater(
        fixture
            .service()
            .installAndStart(clientId: 'desktop-client', onProgress: (_) {}),
        throwsA(_failure(LocalBridgeSetupFailure.incompatibleVersion)));
    expect(fixture.commands.any((command) => command.contains('systemctl')),
        isFalse);
    expect(fixture.approvals, isEmpty);
  });

  test('uses XDG autostart when systemd user services are unavailable',
      () async {
    fixture.systemd = false;
    await fixture
        .service()
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    final entry = File(
        '${fixture.home}/.config/autostart/omni-code-desktop-bridge.desktop');
    expect(await entry.exists(), isTrue);
    expect(fixture.detached, hasLength(1));
    expect(fixture.detached.single.first, '/bin/sh');
    expect(fixture.commands.any((command) => command.contains('daemon-reload')),
        isFalse);
  });

  test('macOS registers a user LaunchAgent and enables it', () async {
    await fixture.seedBinary();
    await fixture
        .service(os: 'macos')
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    final plist = File(
        '${fixture.home}/Library/LaunchAgents/ai.omnistream.omni-code.bridge.plist');
    final parsed = await Process.run('python3', [
      '-c',
      'import plistlib,sys; p=plistlib.load(open(sys.argv[1],"rb")); assert p["RunAtLoad"]; assert p["ProgramArguments"][1:] == ["serve","--port","8787"]',
      plist.path
    ]);
    expect(parsed.exitCode, 0, reason: parsed.stderr.toString());
    expect(
        fixture.commands,
        contains(
            '/bin/launchctl enable gui/501/ai.omnistream.omni-code.bridge'));
  });

  test('Windows registers a hidden startup launcher with Unicode-safe scripts',
      () async {
    await fixture.seedBinary(windows: true);
    await fixture
        .service(os: 'windows')
        .installAndStart(clientId: 'desktop-client', onProgress: (_) {});
    final entry = File(
        '${fixture.home}/AppData/Microsoft/Windows/Start Menu/Programs/Startup/Omni Code Bridge.vbs');
    final bytes = await entry.readAsBytes();
    expect(bytes.take(2), [0xff, 0xfe]);
    final text = String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8
    ]);
    expect(text, contains('-WindowStyle Hidden'));
    expect(fixture.detached.single.take(3), ['wscript.exe', '//B', '//Nologo']);
    final script =
        await File('${fixture.home}/.omni-code-bridge/start-bridge.ps1')
            .readAsBytes();
    expect(script.take(3), [0xef, 0xbb, 0xbf]);
  });

  test('shell launcher handles spaces, quotes, dollars and Unicode in paths',
      () async {
    final home = '${fixture.root.path}/用户 home \' \$dollar %';
    final directory = await Directory('$home/bridge').create(recursive: true);
    final binary = File('${directory.path}/fake bridge');
    await binary.writeAsString(
        '#!/bin/sh\nprintf \'%s\\n\' "\$OMNI_CODE_HOME" "\$@"\n');
    await Process.run('chmod', ['700', binary.path]);
    final startup = LocalBridgeStartup(
        home: home,
        executable: binary.path,
        directory: directory.path,
        path: Platform.environment['PATH']!);
    final launcher = File('${directory.path}/start.sh');
    await launcher.writeAsString(startup.shellLauncher);
    final result = await Process.run('/bin/sh', [launcher.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await File('${directory.path}/bridge.log').readAsLines(),
        ['$home/.omni-code', 'serve', '--port', '8787']);
  });

  test(
      'systemd accepts the generated unit with special characters in user paths',
      () async {
    final directory =
        await Directory('${fixture.root.path}/user home \$ % " quote').create();
    final startup = LocalBridgeStartup(
      home: directory.path,
      executable: '${directory.path}/bridge executable',
      directory: directory.path,
      path: '/usr/bin:/bin',
    );
    final unit = File('${fixture.root.path}/omni-code-desktop-bridge.service');
    await unit.writeAsString(startup.systemdUnit);
    final result =
        await Process.run('systemd-analyze', ['verify', '--man=no', unit.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }, skip: !Platform.isLinux);
}

Matcher _failure(LocalBridgeSetupFailure failure) =>
    isA<LocalBridgeSetupException>()
        .having((error) => error.failure, 'failure', failure);

class _SetupFixture {
  _SetupFixture(this.root, this.home, this.archive);
  final Directory root;
  final String home;
  final List<int> archive;
  static const _asset = 'omni-code-bridge-linux-x64.tar.gz';
  final binaryContents = '#!/bin/sh\nexit 0\n';
  final commands = <String>[];
  final approvals = <List<String>>[];
  final detached = <List<String>>[];
  var downloads = 0;
  var ready = false;
  var approved = false;
  var badChecksum = false;
  var failStartup = false;
  var neverReady = false;
  var onlyPrereleases = false;
  var stableVersion = '1.0.0';
  var binaryVersion = '1.0.0';
  var versionFlagSupported = true;
  List<String> listedVersions = ['1.0.0'];
  final downloadedVersions = <String>[];
  var workspaceStatus = 200;
  String? workspaceClientId;
  var systemd = true;
  String? requestedClientId;

  File get binary => File('$home/.omni-code-bridge/bin/omni-code-bridge');

  static Future<_SetupFixture> create() async {
    final root = await Directory.systemTemp.createTemp('bridge-setup-test-');
    final source =
        await Directory('${root.path}/source/omni-code-bridge-linux-x64')
            .create(recursive: true);
    await File('${source.path}/omni-code-bridge')
        .writeAsString('#!/bin/sh\nexit 0\n');
    final archive = File('${root.path}/release.tar.gz');
    final result = await Process.run('tar', [
      '-czf',
      archive.path,
      '-C',
      source.parent.path,
      'omni-code-bridge-linux-x64'
    ]);
    if (result.exitCode != 0) throw StateError('Could not create test archive');
    return _SetupFixture(
        root, '${root.path}/home', await archive.readAsBytes());
  }

  Future<void> seedBinary({bool windows = false}) async {
    final file = File('${binary.path}${windows ? '.exe' : ''}');
    await file.parent.create(recursive: true);
    await file.writeAsString(binaryContents);
  }

  NativeLocalBridgeSetupService service({String os = 'linux'}) =>
      NativeLocalBridgeSetupService(
        operatingSystem: os,
        environment: {
          'HOME': home,
          'USERPROFILE': home,
          'APPDATA': '$home/AppData',
          'PATH': '/usr/bin:/bin'
        },
        readinessTimeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 1),
        httpClient: MockClient(_http),
        runCommand: _run,
        startDetached: (exe, args) async {
          detached.add([exe, ...args]);
          ready = !neverReady;
        },
      );

  Future<http.Response> _http(http.Request request) async {
    if (request.url.path == '/health') {
      if (!ready) throw http.ClientException('Connection refused');
      return http.Response(
          jsonEncode({'ok': true, 'service': 'omni-code-bridge'}), 200);
    }
    Map<String, dynamic> release(String version) => {
          'tag_name': 'v$version',
          'prerelease': version.contains('-'),
          'draft': false,
          'assets': [
            {
              'name': _asset,
              'browser_download_url':
                  'https://github.com/omni-stream-ai/omni-code-bridge/releases/download/v$version/$_asset',
              'digest':
                  'sha256:${badChecksum ? '0' * 64 : sha256.convert(archive)}',
            }
          ]
        };
    if (request.url.path.endsWith('/releases/latest')) {
      return http.Response(
          jsonEncode(release(stableVersion)), onlyPrereleases ? 404 : 200);
    }
    if (request.url.path.endsWith('/releases')) {
      return http.Response(
          jsonEncode(listedVersions.map(release).toList()), 200);
    }
    if (request.url.path.endsWith(_asset)) {
      downloads++;
      downloadedVersions.add(request.url.pathSegments[4].substring(1));
      return http.Response.bytes(archive, 200);
    }
    if (request.url.path == '/workspace-agent') {
      workspaceClientId = request.headers['X-Omni-Code-Client-Id'];
      expect(request.headers['Authorization'], 'Bearer local-token');
      return http.Response(
          jsonEncode({'data': <String, dynamic>{}}), workspaceStatus);
    }
    if (request.method == 'POST' &&
        request.url.path == '/client-auth/requests') {
      requestedClientId =
          (jsonDecode(request.body) as Map)['client_id'] as String;
      return http.Response(
          jsonEncode({
            'data': {
              'request_id': 'desktop-request',
              'status': approved ? 'approved' : 'pending'
            }
          }),
          201);
    }
    if (request.url.path == '/client-auth/requests/desktop-request') {
      return http.Response(
          jsonEncode({
            'data': {
              'status': approved ? 'approved' : 'pending',
              if (approved) 'token': 'local-token'
            }
          }),
          200);
    }
    return http.Response('Not found', 404);
  }

  Future<ProcessResult> _run(String exe, List<String> args,
      {String? workingDirectory, Map<String, String>? environment}) async {
    commands.add('$exe ${args.join(' ')}');
    if (args.first == '--version') {
      return ProcessResult(1, versionFlagSupported ? 0 : 2,
          versionFlagSupported ? 'omni-code-bridge $binaryVersion\n' : '', '');
    }
    if (exe == 'tar' || exe == 'chmod') return Process.run(exe, args);
    if (exe == 'uname') return ProcessResult(1, 0, 'x86_64\n', '');
    if (exe == '/usr/bin/id') return ProcessResult(1, 0, '501\n', '');
    if (args.first == 'client-auth') {
      approvals.add(args);
      expect(environment?['OMNI_CODE_HOME'], '$home/.omni-code');
      approved = true;
    }
    if (exe == 'systemctl') {
      if (!systemd) return ProcessResult(1, 1, '', 'Unavailable');
      if (args.contains('enable')) {
        if (failStartup) return ProcessResult(1, 1, '', 'Failed');
        ready = !neverReady;
      }
    }
    if (exe == '/bin/launchctl') {
      if (args.first == 'print') return ProcessResult(1, 1, '', 'Not loaded');
      if (args.first == 'bootstrap') ready = !neverReady;
    }
    return ProcessResult(1, 0, '', '');
  }
}
