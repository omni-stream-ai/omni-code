import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_windows/webview_windows.dart' as windows;
import '../services/session_file_access.dart';

class SessionFilePreview extends StatefulWidget {
  const SessionFilePreview(
      {super.key,
      required this.access,
      required this.onOpenLink,
      required this.sourceBuilder});
  final SessionFileAccess access;
  final void Function(String) onOpenLink;
  final Widget Function(BuildContext, String) sourceBuilder;
  @override
  State<SessionFilePreview> createState() => _SessionFilePreviewState();
}

class _SessionFilePreviewState extends State<SessionFilePreview> {
  late final Future<Map<String, dynamic>> _info = widget.access.info();
  Future<String>? _text;
  bool _saving = false;
  String? _saveError;
  String t(String en, String zh) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  @override
  void dispose() {
    unawaited(widget.access.close());
    super.dispose();
  }

  Future<void> _download(String name) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    File? temporary;
    try {
      String? target;
      if (Platform.isAndroid) {
        final dir = await Directory((await getTemporaryDirectory()).path)
            .createTemp('omni-download-');
        temporary = File('${dir.path}/$name');
        await widget.access.saveTo(temporary.path);
        await const MethodChannel('omni_code/app_update')
            .invokeMethod<String>('saveDocument', {
          'path': temporary.path,
          'name': name,
          'mime': sessionFileMime(name),
        });
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        target = '${dir.path}/$name';
        var number = 1;
        while (await File(target!).exists()) {
          target = '${dir.path}/${number++}-$name';
        }
        await widget.access.saveTo(target);
      } else {
        target = (await getSaveLocation(suggestedName: name))?.path;
        if (target != null) await widget.access.saveTo(target);
      }
      if (mounted && target != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${t('Saved to', '已保存到')} $target')));
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = '$error');
    } finally {
      if (temporary != null) {
        await temporary.parent.delete(recursive: true);
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _source() => FutureBuilder<String>(
      future: _text ??= widget.access.text(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText('${snapshot.error}')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: widget.sourceBuilder(context, snapshot.data!)));
      });

  Widget _details(Map<String, dynamic> info) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.insert_drive_file_outlined, size: 56),
        const SizedBox(height: 20),
        Text(t('File information', '文件信息'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(t(
            'Preview is unavailable for this file. You can download it to your device.',
            '此文件暂不支持预览，可下载到设备后打开。')),
        const SizedBox(height: 20),
        for (final entry in {
          t('Name', '名称'): info['name'],
          t('Type', '类型'):
              info['content_type'] ?? sessionFileMime(widget.access.file.path),
          t('Size', '大小'): '${info['size']} bytes',
          t('Modified', '修改时间'): info['modified'],
          t('Path', '路径'): info['path'],
        }.entries)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText('${entry.key}: ${entry.value ?? '—'}')),
      ]));

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: SafeArea(
            child: FutureBuilder<Map<String, dynamic>>(
          future: _info,
          builder: (context, snapshot) {
            final path = widget.access.file.path;
            final name =
                snapshot.data?['name'] as String? ?? path.split('/').last;
            final html = isHtmlFile(path);
            final markdown = isMarkdownFile(path);
            final text = snapshot.hasData &&
                isPreviewTextFile(path) &&
                (snapshot.data!['size'] as num? ?? 0) <= 2 * 1024 * 1024;
            final preview = html || (text && markdown);
            return DefaultTabController(
                length: preview ? 2 : 1,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(children: [
                        Icon(html
                            ? Icons.html_rounded
                            : Icons.description_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(name,
                                key: const ValueKey(
                                    'markdown-file-preview-title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        IconButton(
                            tooltip: t('Close', '关闭'),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ])),
                  if (preview)
                    TabBar(tabs: [
                      Tab(text: t('Preview', '预览')),
                      Tab(text: t('Source', '原文'))
                    ]),
                  Expanded(
                      child: snapshot.hasError
                          ? Center(child: SelectableText('${snapshot.error}'))
                          : !snapshot.hasData
                              ? const Center(child: CircularProgressIndicator())
                              : TabBarView(children: [
                                  if (html)
                                    SessionHtmlPreview(
                                        access: widget.access,
                                        onOpenLink: widget.onOpenLink),
                                  if (text && markdown)
                                    FutureBuilder<String>(
                                        future: _text ??= widget.access.text(),
                                        builder: (context, data) => data
                                                .hasError
                                            ? Center(
                                                child: Text('${data.error}'))
                                            : !data.hasData
                                                ? const Center(
                                                    child:
                                                        CircularProgressIndicator())
                                                : SingleChildScrollView(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    child: MarkdownBody(
                                                        key: const ValueKey(
                                                            'markdown-file-preview-rendered'),
                                                        data: data.data!,
                                                        selectable: true,
                                                        onTapLink:
                                                            (_, href, __) {
                                                          if (href != null) {
                                                            widget.onOpenLink(
                                                                href);
                                                          }
                                                        }))),
                                  if (text || html)
                                    _source()
                                  else
                                    _details(snapshot.data!),
                                ])),
                  if (_saveError != null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(_saveError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: const ValueKey('file-preview-download'),
                            onPressed: snapshot.hasData && !_saving
                                ? () => _download(name)
                                : null,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.download_rounded),
                            label: Text(_saving
                                ? t('Downloading…', '下载中…')
                                : t('Download', '下载')),
                          ))),
                ]));
          },
        )),
      );
}

class SessionHtmlPreview extends StatefulWidget {
  const SessionHtmlPreview(
      {super.key, required this.access, required this.onOpenLink});
  final SessionFileAccess access;
  final void Function(String) onOpenLink;
  @override
  State<SessionHtmlPreview> createState() => _SessionHtmlPreviewState();
}

class _SessionHtmlPreviewState extends State<SessionHtmlPreview> {
  WebViewController? _controller;
  windows.WebviewController? _windows;
  StreamSubscription<dynamic>? _windowsMessages;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final uri = await widget.access.htmlUrl();
      if (!mounted) return;
      if (Platform.isWindows) {
        final controller = windows.WebviewController();
        _windows = controller;
        await controller.initialize();
        if (!mounted) return;
        await controller
            .setPopupWindowPolicy(windows.WebviewPopupWindowPolicy.deny);
        await controller.addScriptToExecuteOnDocumentCreated(
            r'''document.addEventListener('click', function(e) {
          var a=e.target.closest && e.target.closest('a[href]');
          if(a) { e.preventDefault(); window.chrome.webview.postMessage({omniLink:a.href}); }
        }, true);''');
        _windowsMessages = controller.webMessage.listen((message) async {
          if (message is Map && message['omniLink'] is String) {
            final href = message['omniLink'] as String;
            if (_allowNavigation(href)) await controller.loadUrl(href);
          }
        });
        await controller.loadUrl(uri.toString());
      } else {
        final controller = WebViewController();
        _controller = controller;
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) =>
              _allowNavigation(request.url, mainFrame: request.isMainFrame)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = error.description);
            }
          },
        ));
        await controller.loadRequest(uri);
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  bool _allowNavigation(String url, {bool mainFrame = true}) {
    final destination = Uri.tryParse(url);
    if (destination == null) return false;
    final file = widget.access.fileForPreviewUrl(destination);
    if (file != null) {
      if (isHtmlFile(file.path)) return true;
      widget.onOpenLink(file.uri.toString());
      return false;
    }
    if (destination.scheme == 'about' || destination.scheme == 'data') {
      return true;
    }
    if (mainFrame) {
      if ({'http', 'https', 'mailto'}.contains(destination.scheme)) {
        unawaited(launchUrl(destination, mode: LaunchMode.externalApplication));
      }
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    unawaited(_windowsMessages?.cancel());
    unawaited(_windows?.dispose());
    final platform = _controller?.platform;
    if (platform is LinuxWebViewController) {
      // The plugin widget and render object hide their native frame during
      // teardown. Keep the controller alive until those calls have completed.
      unawaited(
          WidgetsBinding.instance.endOfFrame.then((_) => platform.dispose()));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(_error!)));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return KeyedSubtree(
        key: const ValueKey('html-file-preview-rendered'),
        child: _windows != null
            ? windows.Webview(_windows!)
            : WebViewWidget(controller: _controller!));
  }
}
