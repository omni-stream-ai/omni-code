// Use a separate service name to preserve independently installed services.
class LocalBridgeStartup {
  const LocalBridgeStartup({
    required this.home,
    required this.executable,
    required this.directory,
    required this.path,
  });

  static const serviceName = 'omni-code-desktop-bridge';
  static const launchAgentLabel = 'ai.omnistream.omni-code.bridge';
  final String home;
  final String executable;
  final String directory;
  final String path;

  Map<String, String> get environment => {
        'OMNI_CODE_HOME': '$home/.omni-code',
        'PATH': path,
      };

  String get systemdUnit => '''
[Unit]
Description=Omni Code desktop Bridge
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/sh -c ${_systemd('exec ${_shell(executable)} serve --port 8787', command: true)}
WorkingDirectory=${directory.replaceAll('%', '%%').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}
${environment.entries.map((entry) => 'Environment=${_systemd('${entry.key}=${entry.value}')}').join('\n')}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
''';

  String get launchAgent => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$launchAgentLabel</string>
<key>ProgramArguments</key><array><string>${_xml(executable)}</string><string>serve</string><string>--port</string><string>8787</string></array>
<key>WorkingDirectory</key><string>${_xml(directory)}</string>
<key>EnvironmentVariables</key><dict>
${environment.entries.map((entry) => '<key>${_xml(entry.key)}</key><string>${_xml(entry.value)}</string>').join('\n')}
</dict>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>3</integer>
<key>StandardOutPath</key><string>${_xml('$directory/bridge.log')}</string>
<key>StandardErrorPath</key><string>${_xml('$directory/bridge-error.log')}</string>
</dict></plist>
''';

  String get shellLauncher => '''
#!/bin/sh
${environment.entries.map((entry) => 'export ${entry.key}=${_shell(entry.value)}').join('\n')}
cd ${_shell(directory)} || exit 1
exec ${_shell(executable)} serve --port 8787 >>${_shell('$directory/bridge.log')} 2>&1
''';

  String desktopEntry(String launcher) => '''
[Desktop Entry]
Type=Application
Name=Omni Code Bridge
Exec=/bin/sh ${_desktop(launcher)}
Terminal=false
X-GNOME-Autostart-enabled=true
''';

  String get powershellLauncher => '''
\$ErrorActionPreference = 'Stop'
\$mutex = New-Object System.Threading.Mutex(\$false, 'Local\\OmniCodeDesktopBridge')
if (-not \$mutex.WaitOne(0)) { exit 0 }
try {
  ${environment.entries.map((entry) => '\$env:${entry.key} = ${_powershell(entry.value)}').join('\n  ')}
  while (\$true) {
    \$process = Start-Process -FilePath ${_powershell(executable)} -ArgumentList @('serve', '--port', '8787') -WorkingDirectory ${_powershell(directory)} -WindowStyle Hidden -RedirectStandardOutput ${_powershell('$directory/bridge.log')} -RedirectStandardError ${_powershell('$directory/bridge-error.log')} -PassThru
    \$process.WaitForExit()
    if (\$process.ExitCode -eq 0) { break }
    Start-Sleep -Seconds 3
  }
} finally {
  \$mutex.ReleaseMutex()
  \$mutex.Dispose()
}
''';

  String windowsStartup(String launcher) {
    final command =
        'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "$launcher"';
    return 'CreateObject("WScript.Shell").Run "${command.replaceAll('"', '""')}", 0, False\r\n';
  }

  static String _shell(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
  static String _powershell(String value) => "'${value.replaceAll("'", "''")}'";
  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  static String _systemd(String value, {bool command = false}) {
    var escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('%', '%%')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    if (command) escaped = escaped.replaceAll(r'$', r'$$');
    return '"$escaped"';
  }

  static String _desktop(String value) =>
      '"${value.replaceAll('\\', r'\\\\').replaceAll('"', r'\\\"').replaceAll(r'$', r'\\$').replaceAll(String.fromCharCode(96), '\\\\${String.fromCharCode(96)}').replaceAll('%', '%%')}"';
}
