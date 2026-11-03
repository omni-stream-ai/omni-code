import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/services/session_file_access.dart';
import 'package:omni_code/src/widgets/session_file_preview.dart';

void main() {
  test(
      'file classification distinguishes HTML, source and unsupported binaries',
      () {
    expect(isHtmlFile('/tmp/design.HTML'), isTrue);
    expect(isHtmlFile('/tmp/design.htm'), isTrue);
    expect(isPreviewTextFile('/tmp/config.toml'), isTrue);
    expect(isPreviewTextFile('/tmp/app.apk'), isFalse);
    expect(isPreviewTextFile('/tmp/archive.zip'), isFalse);
    expect(
        sessionFileMime('app.apk'), 'application/vnd.android.package-archive');
  });
  test('HTML serves relative assets and rejects traversal and symlinks',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final dir = await Directory.systemTemp.createTemp('omni-html-test-');
      final outside = await Directory.systemTemp.createTemp('omni-outside-');
      final file = File('${dir.path}/index.html');
      await file.writeAsString('<link href="assets/theme.css">');
      await Directory('${dir.path}/assets').create();
      await File('${dir.path}/assets/theme.css')
          .writeAsString('body{color:red}');
      await File('${outside.path}/secret.txt').writeAsString('secret');
      await Link('${dir.path}/escape').create(outside.path);
      final access = SessionFileAccess(
          file: file, client: BridgeClient(), sessionId: 'chat');
      final browser = HttpClient();
      try {
        final url = await access.htmlUrl();
        expect(await access.htmlUrl(), url);
        final css =
            await (await browser.getUrl(url.resolve('assets/theme.css')))
                .close();
        expect(css.headers.contentType?.mimeType, 'text/css');
        expect(await css.transform(const SystemEncoding().decoder).join(),
            'body{color:red}');
        final denied =
            await (await browser.getUrl(url.resolve('escape/secret.txt')))
                .close();
        expect(denied.statusCode, 403);
        await denied.drain<void>();
        final traversal =
            await (await browser.getUrl(url.resolve('../secret.txt'))).close();
        expect(traversal.statusCode, 403);
        await traversal.drain<void>();
      } finally {
        browser.close(force: true);
        await access.close();
        await dir.delete(recursive: true);
        await outside.delete(recursive: true);
      }
    }, _RealHttp());
  });
  test('remote file metadata and downloads retain session authorization',
      () async {
    final requests = <Uri>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      requests.add(request.url);
      expect(request.headers.containsKey('X-Omni-Code-Client-Id'), isTrue);
      expect(request.url.queryParameters['session_id'], 'chat');
      return request.url.path.endsWith('/info')
          ? http.Response(
              '{"data":{"name":"app.apk","size":4,"path":"/missing/app.apk"}}',
              200)
          : http.Response.bytes([0, 1, 2, 3], 200);
    }));
    final dir = await Directory.systemTemp.createTemp('omni-save-test-');
    final access = SessionFileAccess(
        file: File('/missing/app.apk'), client: client, sessionId: 'chat');
    try {
      expect((await access.info())['size'], 4);
      await access.saveTo('${dir.path}/saved.apk');
      expect(await File('${dir.path}/saved.apk').readAsBytes(), [0, 1, 2, 3]);
      expect(requests.map((uri) => uri.path), ['/files/info', '/files']);
    } finally {
      await access.close();
      await dir.delete(recursive: true);
    }
  });
  testWidgets(
      'APK shows file information and download without reading binary as text',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('omni-apk-widget-');
    final file = File('${dir.path}/app.apk');
    file.writeAsBytesSync([0, 1, 2, 3]);
    await tester.pumpWidget(MaterialApp(
        home: SessionFilePreview(
      access: _WidgetAccess(file, 'binary'),
      onOpenLink: (_) {},
      sourceBuilder: (_, text) => Text(text),
    )));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.text('File information'), findsOneWidget);
    expect(find.textContaining('4 bytes'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    dir.deleteSync(recursive: true);
  });
  testWidgets('HTML defaults to native WebView and can switch to exact source',
      (tester) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    final dir = Directory.systemTemp.createTempSync('omni-html-widget-');
    const source = '<!doctype html><h1>Hello HTML</h1>';
    final file = File('${dir.path}/index.html');
    file.writeAsStringSync(source);
    await tester.pumpWidget(MaterialApp(
        home: SessionFilePreview(
      access: _WidgetAccess(file, source),
      onOpenLink: (_) {},
      sourceBuilder: (_, text) => SelectableText(text),
    )));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Native WebView'), findsOneWidget);
    expect(platform.controller.url?.host, '127.0.0.1');
    await tester.tap(find.text('Source'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.text(source), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    dir.deleteSync(recursive: true);
  });
}

class _WebPlatform extends WebViewPlatform {
  late _Controller controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  Uri? url;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    url = params.uri;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('Native WebView');
}

class _RealHttp extends HttpOverrides {}

class _WidgetAccess extends SessionFileAccess {
  _WidgetAccess(File file, this.source)
      : super(file: file, client: BridgeClient(), sessionId: 'chat');
  final String source;
  @override
  Future<Map<String, dynamic>> info() async => {
        'name': file.uri.pathSegments.last,
        'path': file.path,
        'size': isHtmlFile(file.path) ? source.length : 4,
      };
  @override
  Future<String> text() async => source;
  @override
  Future<Uri> htmlUrl() async =>
      Uri.parse('http://127.0.0.1:1234/preview/index.html');
}
