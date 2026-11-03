import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mcp_elicitation_dialog.dart';

class McpContentView extends StatelessWidget {
  const McpContentView({super.key, required this.value, this.onReadResource});
  final Object? value;
  final Future<void> Function(String uri)? onReadResource;
  @override
  Widget build(BuildContext context) {
    final result =
        value is Map ? value as Map : {'content': value is List ? value : []};
    final contents = (result['content'] ?? result['contents']) as List? ?? [];
    final structured =
        result['structuredContent'] ?? result['structured_content'];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result['isError'] == true || result['is_error'] == true)
            Text(mcpText(context, 'MCP tool returned an error', 'MCP 工具返回错误'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ...contents.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _block(context, item))),
          if (structured != null) _json(structured),
          if (contents.isEmpty && structured == null) _json(value),
        ]);
  }

  Widget _json(Object? object) =>
      SelectableText(const JsonEncoder.withIndent('  ').convert(object),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12));
  Widget _block(BuildContext context, Object? value) {
    if (value is! Map) return _json(value);
    final type = value['type'];
    if (type == 'text' || value['text'] is String && type == null) {
      return MarkdownBody(
          data: '${value['text'] ?? ''}',
          selectable: true,
          onTapLink: (_, href, __) async {
            final uri = Uri.tryParse(href ?? '');
            if (uri == null ||
                !['http', 'https', 'mailto'].contains(uri.scheme)) {
              return;
            }
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {/* OS may have no URL handler. */}
          });
    }
    if (type == 'image' || type == 'audio' || value['blob'] is String) {
      try {
        final data = '${value['data'] ?? value['blob'] ?? ''}';
        if (data.length > 24 * 1024 * 1024) {
          return Text(
              mcpText(context, 'Content exceeds preview limit', '内容超出预览大小限制'));
        }
        final bytes = base64Decode(data);
        final mime = '${value['mimeType'] ?? 'application/octet-stream'}';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (type == 'image' || mime.startsWith('image/'))
                Image.memory(bytes,
                    fit: BoxFit.contain,
                    height: 280,
                    errorBuilder: (_, __, ___) =>
                        _json({'mimeType': mime, 'bytes': bytes.length})),
              if (type == 'audio' || mime.startsWith('audio/'))
                _McpAudio(bytes: bytes),
              OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: Text(mcpText(context, 'Save attachment', '保存附件')),
                  onPressed: () async {
                    try {
                      final extension = mime
                          .split('/')
                          .last
                          .replaceAll(RegExp('[^a-zA-Z0-9]'), '');
                      final target = await getSaveLocation(
                          suggestedName:
                              'mcp-result.${extension.isEmpty ? 'bin' : extension}');
                      if (target != null) {
                        await XFile.fromData(bytes, mimeType: mime)
                            .saveTo(target.path);
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$error')));
                      }
                    }
                  }),
            ]);
      } catch (_) {
        return Text(mcpText(context, 'Invalid attachment encoding', '附件编码无效'));
      }
    }
    if (type == 'resource') return _block(context, value['resource']);
    if (type == 'resource_link' || value['uri'] != null) {
      final uri = '${value['uri'] ?? ''}';
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${value['title'] ?? value['name'] ?? uri}'),
                subtitle: Text('${value['description'] ?? uri}'),
                trailing: onReadResource == null
                    ? null
                    : const Icon(Icons.open_in_new),
                onTap:
                    onReadResource == null ? null : () => onReadResource!(uri)),
            if (value['text'] != null)
              _block(context, {'type': 'text', 'text': value['text']}),
          ]);
    }
    return _json(value);
  }
}

class _McpAudio extends StatefulWidget {
  const _McpAudio({required this.bytes});
  final Uint8List bytes;
  @override
  State<_McpAudio> createState() => _McpAudioState();
}

class _McpAudioState extends State<_McpAudio> {
  AudioSource? _source;
  SoundHandle? _handle;
  StreamSubscription<dynamic>? _finished;
  bool _busy = false;
  bool _playing = false;
  String? _error;
  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_playing) {
        if (_handle != null) await SoLoud.instance.stop(_handle!);
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
      final source = _source ??
          await SoLoud.instance
              .loadMem('mcp-${identityHashCode(this)}', widget.bytes);
      if (!mounted) {
        await SoLoud.instance.disposeSource(source);
        return;
      }
      _source = source;
      _finished ??= source.allInstancesFinished.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      _handle = SoLoud.instance.play(source);
      if (mounted) setState(() => _playing = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_finished?.cancel());
    if (_source != null && SoLoud.instance.isInitialized) {
      unawaited(SoLoud.instance.disposeSource(_source!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
            onPressed: _busy ? null : _toggle,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(mcpText(context, _playing ? 'Stop audio' : 'Play audio',
                _playing ? '停止音频' : '播放音频'))),
        if (_error != null) Text(_error!),
      ]);
}
