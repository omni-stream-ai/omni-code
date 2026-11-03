import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../bridge_client.dart';

String sessionFileExtension(String path) =>
    path.split('/').last.split('.').last.toLowerCase();
bool isHtmlFile(String path) =>
    {'html', 'htm'}.contains(sessionFileExtension(path));
bool isMarkdownFile(String path) =>
    {'md', 'markdown', 'mdown'}.contains(sessionFileExtension(path));
bool isPreviewTextFile(String path) =>
    isHtmlFile(path) ||
    isMarkdownFile(path) ||
    {
      'txt',
      'json',
      'yaml',
      'yml',
      'toml',
      'xml',
      'csv',
      'log',
      'dart',
      'rs',
      'py',
      'js',
      'mjs',
      'cjs',
      'ts',
      'tsx',
      'jsx',
      'css',
      'scss',
      'java',
      'kt',
      'swift',
      'go',
      'c',
      'cc',
      'cpp',
      'h',
      'hpp',
      'sh',
      'bash',
      'zsh',
      'fish',
      'sql',
      'ini',
      'conf',
      'env',
      'gradle',
      'cmake',
      'properties',
    }.contains(sessionFileExtension(path)) ||
    {'Dockerfile', 'Makefile', 'LICENSE', '.gitignore'}
        .contains(path.split('/').last);

String sessionFileMime(String path) => switch (sessionFileExtension(path)) {
      'html' || 'htm' => 'text/html; charset=utf-8',
      'css' => 'text/css',
      'js' || 'mjs' => 'application/javascript',
      'json' => 'application/json',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'svg' => 'image/svg+xml',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'ico' => 'image/x-icon',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'apk' => 'application/vnd.android.package-archive',
      _ => isPreviewTextFile(path) ? 'text/plain' : 'application/octet-stream',
    };

class SessionFileAccess {
  SessionFileAccess(
      {required this.file,
      required this.client,
      required this.sessionId,
      String? rootPath})
      : root = rootPath != null && file.absolute.path.startsWith('$rootPath/')
            ? Directory(rootPath)
            : file.parent;
  final File file;
  final Directory root;
  final BridgeClient client;
  final String sessionId;
  HttpServer? _server;
  Future<Uri>? _htmlUri;
  bool _closed = false;
  final String _token = List.generate(24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();

  Future<Map<String, dynamic>> info() async {
    if (await file.exists()) {
      final stat = await file.stat();
      return {
        'name': file.uri.pathSegments.last,
        'path': file.path,
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
        'content_type': sessionFileMime(file.path)
      };
    }
    return client.fileInfo(file.path, sessionId: sessionId);
  }

  Future<Stream<List<int>>> open([File? target]) async {
    final source = target ?? file;
    if (await source.exists()) return source.openRead();
    return (await client.openFileStream(source.path, sessionId: sessionId))
        .stream;
  }

  Future<String> text() async {
    final bytes = <int>[];
    await for (final chunk in await open()) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('File is too large for source preview');
      }
    }
    if (bytes.contains(0)) throw const FormatException('Binary file');
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> saveTo(String path) async {
    if (File(path).absolute.path == file.absolute.path && await file.exists()) {
      return;
    }
    await (await open()).pipe(File(path).openWrite());
  }

  // A private, per-preview loopback origin serves HTML and relative assets.
  // Bridge credentials remain in Dart and are never sent into the WebView.
  Future<Uri> htmlUrl() => _htmlUri ??= _startHtmlServer();
  Future<Uri> _startHtmlServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Preview closed');
    }
    _server = server;
    server.listen((request) async {
      try {
        if (!{'GET', 'HEAD'}.contains(request.method) ||
            !request.uri.path.startsWith('/$_token/')) {
          request.response.statusCode = HttpStatus.forbidden;
          return;
        }
        final relative = request.uri.path.substring(_token.length + 2);
        final resolved = root.absolute.uri.resolveUri(Uri(path: relative));
        if (!resolved.path.startsWith(root.absolute.uri.path)) {
          request.response.statusCode = HttpStatus.forbidden;
          return;
        }
        final target = File.fromUri(resolved);
        if (await target.exists()) {
          final realRoot = await root.resolveSymbolicLinks();
          final realFile = await target.resolveSymbolicLinks();
          if (!realFile.startsWith('$realRoot${Platform.pathSeparator}')) {
            request.response.statusCode = HttpStatus.forbidden;
            return;
          }
        }
        request.response.headers
            .set(HttpHeaders.contentTypeHeader, sessionFileMime(target.path));
        request.response.headers
            .set(HttpHeaders.cacheControlHeader, 'no-store');
        if (request.method == 'GET') {
          await request.response.addStream(await open(target));
        }
      } catch (_) {
        request.response.statusCode = HttpStatus.notFound;
      } finally {
        await request.response.close();
      }
    });
    final relative = file.absolute.path
        .substring(root.absolute.path.length)
        .replaceFirst(RegExp(r'^/'), '');
    return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/$_token/$relative');
  }

  File? fileForPreviewUrl(Uri uri) {
    final server = _server;
    if (server == null ||
        uri.host != '127.0.0.1' ||
        uri.port != server.port ||
        !uri.path.startsWith('/$_token/')) {
      return null;
    }
    final resolved = root.absolute.uri
        .resolveUri(Uri(path: uri.path.substring(_token.length + 2)));
    if (!resolved.path.startsWith(root.absolute.uri.path)) return null;
    return File.fromUri(resolved);
  }

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
  }
}
