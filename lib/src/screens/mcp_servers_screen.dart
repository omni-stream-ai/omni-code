import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bridge_client.dart';
import '../models.dart';
import '../widgets/mcp_content_view.dart';
import '../widgets/mcp_elicitation_dialog.dart';

class McpServersScreen extends StatefulWidget {
  const McpServersScreen(
      {super.key,
      required this.client,
      this.profileId = 'default',
      this.sessionId});
  final BridgeClient client;
  final String profileId;
  final String? sessionId;
  @override
  State<McpServersScreen> createState() => _McpServersScreenState();
}

class _McpServersScreenState extends State<McpServersScreen> {
  late String _profile;
  List<CodexProfileSummary> _profiles = [];
  Map<String, dynamic> _servers = {};
  Map<String, dynamic> _statuses = {};
  Map<String, dynamic>? _sessionRuntime;
  bool _statusLoading = false;
  final Set<String> _inventoryLoading = {};

  void _applyStatus(Map<String, dynamic> status) {
    _statuses = {
      for (final entry in status['servers'] as List? ?? [])
        '${entry['name']}': {
          ...?_statuses['${entry['name']}'] as Map?,
          ...(Map.from(entry as Map)
            ..removeWhere((key, _) =>
                status['inventoryComplete'] != true &&
                (key == 'resources' || key == 'resourceTemplates') &&
                (_statuses['${entry['name']}'] as Map?)?.containsKey(key) ==
                    true)),
        }
    };
    _sessionRuntime = status['sessionRuntime'] as Map<String, dynamic>?;
  }

  Future<void> _loadInventory(String name) async {
    if (!_inventoryLoading.add(name)) return;
    final generation = _generation;
    try {
      final result = await _request('inventory');
      if (!mounted || generation != _generation) return;
      setState(() => _applyStatus(result));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _runtimeError = '$error');
      }
    } finally {
      _inventoryLoading.remove(name);
    }
  }

  List<dynamic> _events = [];
  String _revision = '';
  Set<String> _inherited = {};
  String? _error, _runtimeError;
  bool _busy = false, _polling = false, _connected = false;
  int _generation = 0;
  int _pollCount = 0;
  Timer? _timer;
  final _handled = <String>{};
  @override
  void initState() {
    super.initState();
    _profile = widget.profileId;
    unawaited(_load());
    unawaited(widget.client.listCodexProfiles().then((profiles) {
      if (mounted) setState(() => _profiles = profiles);
    }).catchError((Object error) {
      if (mounted) setState(() => _error = '$error');
    }));
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String path,
          {String method = 'GET', Map<String, dynamic>? body}) =>
      widget.client.mcpRequest(path,
          method: method,
          body: body,
          profileId: _profile,
          sessionId: widget.sessionId);
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _runtimeError = null;
      _connected = false;
      _statuses = {};
      _events = [];
    });
    try {
      final config = await _request('config');
      if (!mounted || generation != _generation) return;
      setState(() {
        _servers = Map<String, dynamic>.from(config['servers'] as Map);
        _revision = config['revision'] as String;
        _busy = false;
        _statusLoading = true;
        _inherited =
            ((config['inherited'] as List?) ?? []).whereType<String>().toSet();
      });
      _connected = true;
      try {
        final status = await _request('status');
        if (!mounted || generation != _generation) return;
        setState(() {
          _applyStatus(status);
        });
        _connection(status['connection'] as Map? ?? {});
      } catch (error) {
        if (mounted && generation == _generation) {
          setState(() => _runtimeError = '$error');
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _statusLoading = false;
        });
      }
    }
  }

  void _connection(Map data) {
    if (!mounted) return;
    setState(() {
      _events = data['events'] as List? ?? [];
      if (_statusLoading) {
        for (final event in _events) {
          if (event['method'] != 'mcpServer/startupStatus/updated') continue;
          final params = event['params'] as Map? ?? {};
          final name = params['name'] as String?;
          if (name == null) continue;
          _statuses[name] = {
            ...?_statuses[name] as Map?,
            'runtimeStatus':
                params['status'] == 'ready' ? 'connected' : params['status'],
            if (params['error'] != null) 'toolsError': params['error'],
          };
        }
      }
    });
  }

  Future<void> _poll() async {
    if (!mounted || !_connected || _polling) return;
    _polling = true;
    final generation = _generation;
    try {
      final connection = await _request('requests');
      if (!mounted || generation != _generation) return;
      _connection(connection);
      if (!_busy && !_statusLoading && ++_pollCount % 5 == 0) {
        final status = await _request('status');
        if (!mounted || generation != _generation) return;
        setState(() {
          _applyStatus(status);
          _runtimeError = null;
        });
        _connection(status['connection'] as Map? ?? {});
      }
      for (final request in connection['requests'] as List? ?? []) {
        if (!mounted || generation != _generation) return;
        final id = '${request['request_id']}';
        if (!_handled.add(id)) continue;
        final result = await showMcpElicitation(
            context, Map<String, dynamic>.from(request['params'] as Map));
        if (!mounted || generation != _generation) return;
        try {
          await _request('requests/${Uri.encodeComponent(id)}',
              method: 'POST',
              body: result ??
                  {'action': 'cancel', 'content': null, '_meta': null});
        } catch (error) {
          _handled.remove(id);
          rethrow;
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _runtimeError = '$error');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _rpc(String method,
          [Map<String, dynamic> params = const {}]) =>
      _request('rpc',
          method: 'POST', body: {'method': method, 'params': params});
  Future<void> _save(String name, Map<String, dynamic> config) async {
    await _request('servers/${Uri.encodeComponent(name)}',
        method: 'PUT',
        body: {'config': config, 'expected_revision': _revision});
    await _load();
  }

  Future<void> _edit([String? name]) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _McpServerEditor(
            name: name,
            config: name == null
                ? null
                : Map<String, dynamic>.from(_servers[name] as Map)));
    if (result == null || !mounted) return;
    await _run(() => _save(result['name'] as String,
        Map<String, dynamic>.from(result['config'] as Map)));
  }

  Future<void> _delete(String name) async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(mcpText(context, 'Remove $name?', '删除 $name？')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(mcpText(context, 'Cancel', '取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(mcpText(context, 'Remove', '删除')))
                ]));
    if (approved != true || !mounted) return;
    await _run(() async {
      await _request('servers/${Uri.encodeComponent(name)}',
          method: 'DELETE', body: {'expected_revision': _revision});
      await _load();
    });
  }

  Future<void> _login(String name) async {
    await _run(() async {
      final result = await _rpc('mcpServer/oauth/login', {'name': name});
      final url = Uri.tryParse('${result['authorizationUrl'] ?? ''}');
      if (url == null || !['http', 'https'].contains(url.scheme)) {
        throw StateError('Invalid authorization URL');
      }
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (_) => _McpLoginDialog(
                name: name,
                url: url,
                onComplete: (callback) async {
                  await _request('oauth/complete',
                      method: 'POST', body: {'callback_url': callback});
                },
              ));
    });
  }

  Future<void> _showResult(Object? result, {String? server}) async {
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(mcpText(context, 'MCP result', 'MCP 结果')),
                content: SizedBox(
                    width: 640,
                    child: SingleChildScrollView(
                        child: McpContentView(
                            value: result,
                            onReadResource: server == null
                                ? null
                                : (uri) async {
                                    try {
                                      final next = await _rpc(
                                          'mcpServer/resource/read',
                                          {'server': server, 'uri': uri});
                                      await _showResult(next, server: server);
                                    } catch (error) {
                                      if (mounted) {
                                        setState(() => _error = '$error');
                                      }
                                    }
                                  }))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(mcpText(context, 'Close', '关闭')))
                ]));
  }

  Future<void> _callTool(String server, String name, Map tool) async {
    final controller = TextEditingController(text: '{}');
    String? validationError;
    final arguments = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: Text('$server / $name'),
                    content: SizedBox(
                        width: 560,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Text('${tool['description'] ?? ''}'),
                              const SizedBox(height: 12),
                              Text(mcpText(context, 'Input schema', '输入结构')),
                              SelectableText(const JsonEncoder.withIndent('  ')
                                  .convert(tool['inputSchema'] ??
                                      tool['input_schema'] ??
                                      {})),
                              const SizedBox(height: 12),
                              TextField(
                                  key: const Key('mcp-tool-arguments'),
                                  controller: controller,
                                  maxLines: 8,
                                  decoration: InputDecoration(
                                      labelText: mcpText(context,
                                          'Arguments (JSON)', '参数（JSON）'),
                                      errorText: validationError)),
                              const SizedBox(height: 12),
                              Text(mcpText(
                                  context,
                                  'Running this tool may change data in the connected service.',
                                  '运行此工具可能修改所连接服务中的数据。')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(mcpText(context, 'Cancel', '取消'))),
                      FilledButton(
                          onPressed: () {
                            try {
                              final args = jsonDecode(controller.text);
                              if (args is! Map<String, dynamic>) {
                                throw const FormatException(
                                    'Arguments must be an object');
                              }
                              final schema =
                                  tool['inputSchema'] ?? tool['input_schema'];
                              final error = schema is Map
                                  ? validateMcpValue(
                                      args, Map<String, dynamic>.from(schema))
                                  : null;
                              if (error != null) throw FormatException(error);
                              Navigator.pop(context, args);
                            } catch (error) {
                              setDialogState(() => validationError = '$error');
                            }
                          },
                          child: Text(mcpText(context, 'Run tool', '运行工具')))
                    ])));
    // The dialog may still be animating out; its controller is disposed after the route finishes.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (arguments == null || !mounted) return;
    await _run(() async {
      final result = await _rpc('mcpServer/tool/call',
          {'server': server, 'tool': name, 'arguments': arguments});
      await _showResult(result, server: server);
    });
  }

  String _sessionRuntimeLabel(String name) {
    final servers = _sessionRuntime?['servers'] as List?;
    if (servers == null) {
      return mcpText(
          context,
          'Chat tools not yet verified. Send a new message to check the actual runtime.',
          '尚未确认会话工具；下一轮对话将记录实际加载状态。');
    }
    final matches = servers.where((server) => server['name'] == name);
    if (matches.isEmpty) {
      return mcpText(
          context, 'Not loaded in the latest chat turn', '最近一轮对话未加载此服务');
    }
    final server = matches.first as Map;
    final count = (server['tools'] as Map?)?.length ?? 0;
    final error = server['toolsError'];
    return '${mcpText(context, 'Latest chat turn', '最近一轮对话')}: ${server['runtimeStatus'] ?? 'unknown'} · $count ${mcpText(context, 'tools', '个工具')}'
        '${error == null ? '' : '\n$error'}';
  }

  Widget _server(String name) {
    final config = Map<String, dynamic>.from((_servers[name] as Map?) ?? {});
    final status = Map<String, dynamic>.from((_statuses[name] as Map?) ?? {});
    final enabled = config['enabled'] != false;
    final tools = Map<String, dynamic>.from((status['tools'] as Map?) ?? {});
    final resources = status['resources'] as List? ?? [];
    final templates = status['resourceTemplates'] as List? ?? [];
    final colors = Theme.of(context).colorScheme;
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.outlineVariant)),
        child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    config['url'] == null
                        ? Icons.terminal_rounded
                        : Icons.language_rounded,
                    color: colors.primary,
                    size: 22)),
            key: ValueKey('mcp-server-$name'),
            onExpansionChanged: (expanded) {
              if (expanded) unawaited(_loadInventory(name));
            },
            title: Text(name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text([
              config['command'] ?? config['url'] ?? '',
              (status['runtimeStatus'] == null
                      ? null
                      : '${mcpText(context, 'Test connection', '测试连接')}: ${status['runtimeStatus']}') ??
                  (enabled
                      ? (_statusLoading
                          ? mcpText(context, 'Checking connection…', '正在检查连接…')
                          : mcpText(context, 'Not checked', '尚未检查'))
                      : mcpText(context, 'Disabled', '已停用')),
              if (status['authStatus'] != null) '${status['authStatus']}',
            ].where((v) => '$v'.isNotEmpty).join(' · ')),
            childrenPadding: const EdgeInsets.all(16),
            children: [
              if (widget.sessionId != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_sessionRuntimeLabel(name))),
              if (_inherited.contains(name))
                Text(mcpText(
                    context,
                    'Inherited from the default profile. Editing saves an override in this profile.',
                    '继承自默认 Profile，编辑后保存为当前 Profile 的覆盖配置。')),
              Row(children: [
                Expanded(
                    child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(mcpText(context, 'Enabled', '启用')),
                        value: enabled,
                        onChanged: _busy || !_servers.containsKey(name)
                            ? null
                            : (value) => _run(() =>
                                _save(name, {...config, 'enabled': value})))),
                IconButton(
                    tooltip: mcpText(context, 'Edit', '编辑'),
                    onPressed: _busy || !_servers.containsKey(name)
                        ? null
                        : () => _edit(name),
                    icon: const Icon(Icons.edit_outlined)),
                IconButton(
                    tooltip: mcpText(context, 'Remove', '删除'),
                    onPressed: _busy ||
                            !_servers.containsKey(name) ||
                            _inherited.contains(name)
                        ? null
                        : () => _delete(name),
                    icon: const Icon(Icons.delete_outline))
              ]),
              if (status['toolsError'] != null)
                SelectableText('${status['toolsError']}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _busy || !enabled ? null : () => _login(name),
                    icon: const Icon(Icons.login),
                    label: Text(mcpText(context, 'OAuth login', 'OAuth 登录'))),
                OutlinedButton.icon(
                    onPressed: _busy || !enabled
                        ? null
                        : () => _run(() async {
                              await _rpc('config/mcpServer/reload');
                              await _load();
                            }),
                    icon: const Icon(Icons.refresh),
                    label: Text(mcpText(context, 'Reconnect', '重新连接'))),
              ]),
              const SizedBox(height: 12),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${mcpText(context, 'Tools', '工具')} (${tools.length})',
                      style: Theme.of(context).textTheme.titleSmall)),
              ...tools.entries.map((entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${(entry.value as Map)['title'] ?? entry.key}'),
                  subtitle: Text('${(entry.value as Map)['description'] ?? ''}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: _busy || !enabled
                      ? null
                      : () => _callTool(name, entry.key, entry.value as Map))),
              if (resources.isNotEmpty)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(mcpText(context, 'Resources', '资源'),
                        style: Theme.of(context).textTheme.titleSmall)),
              ...resources.map((resource) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${resource['title'] ?? resource['name'] ?? resource['uri']}'),
                  subtitle: Text('${resource['uri']}'),
                  trailing: const Icon(Icons.description_outlined),
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            final result = await _rpc('mcpServer/resource/read',
                                {'server': name, 'uri': resource['uri']});
                            await _showResult(result, server: name);
                          }))),
              if (templates.isNotEmpty)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(mcpText(context, 'Resource templates', '资源模板'),
                        style: Theme.of(context).textTheme.titleSmall)),
              ...templates.map((template) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${template['name']}'),
                  subtitle: Text('${template['uriTemplate']}'),
                  onTap: _busy
                      ? null
                      : () => _readTemplate(name, template as Map))),
            ]));
  }

  Future<void> _readTemplate(String server, Map template) async {
    final controller =
        TextEditingController(text: '${template['uriTemplate']}');
    final uri = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('${template['name']}'),
                content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                        labelText: mcpText(context, 'Resource URI', '资源 URI'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(mcpText(context, 'Cancel', '取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: Text(mcpText(context, 'Read', '读取')))
                ]));
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (uri == null || !mounted) return;
    await _run(() async {
      final result =
          await _rpc('mcpServer/resource/read', {'server': server, 'uri': uri});
      await _showResult(result, server: server);
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = {..._servers.keys, ..._statuses.keys}.toList()..sort();
    return Scaffold(
        appBar: AppBar(title: const Text('MCP · Codex'), actions: [
          IconButton(
              tooltip: mcpText(context, 'Refresh', '刷新'),
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        bottomNavigationBar: SafeArea(
            child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                        top: BorderSide(
                            color:
                                Theme.of(context).colorScheme.outlineVariant))),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FilledButton.icon(
                      key: const Key('mcp-add-server'),
                      onPressed: _revision.isEmpty ? null : () => _edit(),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(mcpText(context, 'Add service', '添加服务')),
                      style: FilledButton.styleFrom(
                          iconColor: Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16))),
                ]))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    children: [
                      Text(mcpText(context, 'MCP services', 'MCP 服务'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                          mcpText(
                              context,
                              'Manage connections, tools and authorization',
                              '管理服务连接、工具与授权'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      const SizedBox(height: 24),
                      if (widget.sessionId == null)
                        DropdownButtonFormField<String>(
                            key: const Key('mcp-profile'),
                            initialValue: _profile,
                            decoration:
                                const InputDecoration(labelText: 'Profile'),
                            items: {
                              for (final profile in _profiles)
                                profile.id: profile.name,
                              if (!_profiles.any((p) => p.id == _profile))
                                _profile: _profile
                            }
                                .entries
                                .map((entry) => DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value)))
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _profile = value);
                                      unawaited(_load());
                                    }
                                  })
                      else
                        Chip(
                            avatar: const Icon(Icons.account_circle_outlined,
                                size: 18),
                            label: Text('Profile: $_profile')),
                      const SizedBox(height: 12),
                      Text(mcpText(
                          context,
                          'Changes apply to subsequent turns. Services run on the connected Bridge host.',
                          '配置变更在后续对话轮次生效，服务在连接的 Bridge 主机上运行。')),
                      if (_busy || _statusLoading)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator()),
                      if (_error != null) _errorPanel(_error!),
                      if (_runtimeError != null) _errorPanel(_runtimeError!),
                      if (names.isEmpty && !_busy && _error == null)
                        Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(mcpText(
                                context,
                                'No MCP services. Add a stdio or HTTP service to get started.',
                                '暂无 MCP 服务，可添加 stdio 或 HTTP 服务。'))),
                      const SizedBox(height: 20),
                      Text(
                          mcpText(
                              context,
                              'Connection checks use a separate test runtime. Chat availability is reported from the latest chat turn.',
                              '连接测试使用独立运行实例；会话可用性以最近一轮对话实际加载的工具为准。'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      ...names.map(_server),
                      if (_events.isNotEmpty)
                        ExpansionTile(
                            title: Text(mcpText(
                                context,
                                'Connection and authorization events',
                                '连接与授权事件')),
                            children: [
                              for (final event in _events.reversed.take(20))
                                ListTile(
                                    dense: true,
                                    title: Text('${event['method']}'),
                                    subtitle: SelectableText(
                                        const JsonEncoder.withIndent('  ')
                                            .convert(event['params']))),
                            ]),
                    ]))));
  }

  Widget _errorPanel(String error) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error))));
}

class _McpServerEditor extends StatefulWidget {
  const _McpServerEditor({this.name, this.config});
  final String? name;
  final Map<String, dynamic>? config;
  @override
  State<_McpServerEditor> createState() => _McpServerEditorState();
}

class _McpServerEditorState extends State<_McpServerEditor> {
  late final TextEditingController _name, _config;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _config = TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(widget.config ??
            {'command': '', 'args': <String>[], 'enabled': true}));
  }

  @override
  void dispose() {
    _name.dispose();
    _config.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final name = _name.text.trim();
      if (name.isEmpty) throw const FormatException('Server name is required');
      final config = jsonDecode(_config.text);
      if (config is! Map<String, dynamic>) {
        throw const FormatException('Configuration must be an object');
      }
      Navigator.pop(context, <String, dynamic>{'name': name, 'config': config});
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(mcpText(
              context,
              widget.name == null ? 'Add MCP service' : 'Edit MCP service',
              widget.name == null ? '添加 MCP 服务' : '编辑 MCP 服务')),
          content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    TextField(
                        key: const Key('mcp-server-name'),
                        controller: _name,
                        enabled: widget.name == null,
                        decoration: InputDecoration(
                            labelText:
                                mcpText(context, 'Server name', '服务名称'))),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      TextButton(
                          onPressed: () => _config.text =
                                  const JsonEncoder.withIndent('  ').convert({
                                'command': 'npx',
                                'args': ['-y', 'your-mcp-package'],
                                'env': <String, String>{},
                                'enabled': true
                              }),
                          child: const Text('stdio')),
                      TextButton(
                          onPressed: () => _config.text =
                                  const JsonEncoder.withIndent('  ').convert({
                                'url': 'https://example.com/mcp',
                                'enabled': true
                              }),
                          child: const Text('HTTP'))
                    ]),
                    TextField(
                        key: const Key('mcp-server-config'),
                        controller: _config,
                        maxLines: 14,
                        minLines: 8,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                            labelText: mcpText(
                                context, 'Configuration (JSON)', '配置（JSON）'),
                            border: const OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Text(mcpText(
                        context,
                        'Supports args, env, cwd, env_vars, http_headers, env_http_headers, bearer_token_env_var, enabled_tools, disabled_tools, startup_timeout_sec and tool_timeout_sec.',
                        '支持 args、env、cwd、env_vars、HTTP 请求头、bearer_token_env_var、工具白名单/黑名单及启动/调用超时。')),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(mcpText(context, 'Cancel', '取消'))),
            FilledButton(
                key: const Key('mcp-save-server'),
                onPressed: _save,
                child: Text(mcpText(context, 'Save', '保存')))
          ]);
}

class _McpLoginDialog extends StatefulWidget {
  const _McpLoginDialog(
      {required this.name, required this.url, required this.onComplete});
  final String name;
  final Uri url;
  final Future<void> Function(String) onComplete;
  @override
  State<_McpLoginDialog> createState() => _McpLoginDialogState();
}

class _McpLoginDialogState extends State<_McpLoginDialog> {
  final _callback = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _callback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            mcpText(context, 'Authorize ${widget.name}', '授权 ${widget.name}')),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(mcpText(
                      context,
                      'Open the authorization link and sign in, then return here.',
                      '打开授权链接并登录，完成后返回。')),
                  const SizedBox(height: 12),
                  SelectableText('${widget.url}'),
                  TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: Text(mcpText(context, 'Copy link', '复制链接')),
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: '${widget.url}'))),
                  const Divider(),
                  Text(mcpText(
                      context,
                      'Using a phone or another computer? If the browser ends on a localhost error page, copy its full address below to complete the callback on the Bridge host.',
                      '使用手机或另一台电脑时，如果浏览器最后停在 localhost 连接失败页面，请复制其完整地址到下方，由 Bridge 主机完成回调。')),
                  const SizedBox(height: 12),
                  TextField(
                      key: const Key('mcp-oauth-callback'),
                      controller: _callback,
                      decoration: InputDecoration(
                          labelText: mcpText(context, 'Callback URL', '回调地址'),
                          errorText: _error),
                      maxLines: 3),
                  OutlinedButton(
                      key: const Key('mcp-complete-oauth'),
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                                _error = null;
                              });
                              try {
                                await widget.onComplete(_callback.text.trim());
                                if (context.mounted) Navigator.pop(context);
                              } catch (error) {
                                if (mounted) setState(() => _error = '$error');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: Text(mcpText(
                          context, 'Complete remote authorization', '完成远程授权'))),
                ]))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(mcpText(context, 'Close', '关闭'))),
          FilledButton(
              onPressed: () async {
                try {
                  if (!await launchUrl(widget.url,
                      mode: LaunchMode.externalApplication)) {
                    throw StateError('Could not open authorization page');
                  }
                } catch (error) {
                  if (mounted) setState(() => _error = '$error');
                }
              },
              child: Text(mcpText(context, 'Open browser', '打开浏览器')))
        ],
      );
}
