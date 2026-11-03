import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

String mcpText(BuildContext context, String en, String zh) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// Validate MCP's JSON-schema form subset before sending typed answers.
String? validateMcpValue(Object? value, Map<String, dynamic> schema,
    [String path = '']) {
  final type = schema['type'];
  if (type is List) {
    if (type.every((entry) =>
        validateMcpValue(value, {...schema, 'type': entry}, path) != null)) {
      return '$path: Invalid value';
    }
    return null;
  }
  final valid = switch (type) {
    'string' => value is String,
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    'boolean' => value is bool,
    'array' => value is List,
    'object' => value is Map,
    'null' => value == null,
    _ => true,
  };
  if (!valid) return '$path: Expected $type';
  if (schema['enum'] is List &&
      !(schema['enum'] as List)
          .any((v) => jsonEncode(v) == jsonEncode(value))) {
    return '$path: Select an allowed value';
  }
  if (schema.containsKey('const') && value != schema['const']) {
    return '$path: Invalid value';
  }
  for (final keyword in ['oneOf', 'anyOf']) {
    if (schema[keyword] is List) {
      final matches = (schema[keyword] as List)
          .whereType<Map>()
          .where((entry) =>
              validateMcpValue(value, Map<String, dynamic>.from(entry), path) ==
              null)
          .length;
      if (matches == 0 || (keyword == 'oneOf' && matches != 1)) {
        return '$path: Invalid option';
      }
    }
  }
  if (value is Map) {
    final properties = (schema['properties'] as Map?) ?? {};
    for (final key in (schema['required'] as List?) ?? []) {
      if (!value.containsKey(key)) return '$key: Required';
    }
    for (final entry in value.entries) {
      if (properties[entry.key] is Map) {
        final error = validateMcpValue(
            entry.value,
            Map<String, dynamic>.from(properties[entry.key] as Map),
            '${entry.key}');
        if (error != null) return error;
      } else if (schema['additionalProperties'] == false) {
        return '${entry.key}: Unknown field';
      }
    }
  }
  if (value is String) {
    if (schema['minLength'] is num &&
        value.runes.length < (schema['minLength'] as num)) {
      return '$path: Too short';
    }
    if (schema['maxLength'] is num &&
        value.runes.length > (schema['maxLength'] as num)) {
      return '$path: Too long';
    }
    if (schema['pattern'] is String) {
      try {
        if (!RegExp(schema['pattern'] as String).hasMatch(value)) {
          return '$path: Invalid format';
        }
      } on FormatException {
        return '$path: Unsupported pattern';
      }
    }
    if (schema['format'] == 'email' &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return '$path: Invalid email';
    }
    if (schema['format'] == 'uri' &&
        !(Uri.tryParse(value)?.hasScheme ?? false)) {
      return '$path: Invalid URL';
    }
    if (schema['format'] == 'date' &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return '$path: Invalid date';
    }
    if (['date', 'date-time'].contains(schema['format']) &&
        DateTime.tryParse(value) == null) {
      return '$path: Invalid date';
    }
  }
  if (value is num) {
    if (schema['minimum'] is num && value < (schema['minimum'] as num)) {
      return '$path: Below minimum';
    }
    if (schema['maximum'] is num && value > (schema['maximum'] as num)) {
      return '$path: Above maximum';
    }
  }
  if (value is List) {
    if (schema['minItems'] is num &&
        value.length < (schema['minItems'] as num)) {
      return '$path: Too few items';
    }
    if (schema['maxItems'] is num &&
        value.length > (schema['maxItems'] as num)) {
      return '$path: Too many items';
    }
    if (schema['uniqueItems'] == true &&
        value.map(jsonEncode).toSet().length != value.length) {
      return '$path: Duplicate items';
    }
    if (schema['items'] is Map) {
      for (var i = 0; i < value.length; i++) {
        final error = validateMcpValue(value[i],
            Map<String, dynamic>.from(schema['items'] as Map), '$path[$i]');
        if (error != null) return error;
      }
    }
  }
  return null;
}

Future<Map<String, dynamic>?> showMcpElicitation(
        BuildContext context, Map<String, dynamic> params) =>
    showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => McpElicitationDialog(params: params));

class McpElicitationDialog extends StatefulWidget {
  const McpElicitationDialog({super.key, required this.params});
  final Map<String, dynamic> params;
  @override
  State<McpElicitationDialog> createState() => _McpElicitationDialogState();
}

class _McpElicitationDialogState extends State<McpElicitationDialog> {
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  String? _error;

  Map<String, dynamic> get _schema => Map<String, dynamic>.from(
      (widget.params['requestedSchema'] as Map?) ?? {});
  Map<String, dynamic> get _properties =>
      Map<String, dynamic>.from((_schema['properties'] as Map?) ?? {});
  @override
  void initState() {
    super.initState();
    for (final entry in _properties.entries) {
      final field = Map<String, dynamic>.from(entry.value as Map);
      final value = field['default'] ??
          (field['type'] == 'boolean' &&
                  (_schema['required'] as List? ?? []).contains(entry.key)
              ? false
              : null);
      if (value != null) _values[entry.key] = value;
      _controllers[entry.key] = TextEditingController(
          text: value == null
              ? ''
              : value is String
                  ? value
                  : jsonEncode(value));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _finish(String action, [Object? content]) => Navigator.pop(context,
      <String, dynamic>{'action': action, 'content': content, '_meta': null});
  List<dynamic>? _choices(Map<String, dynamic> field) {
    if (field['enum'] is List) return field['enum'] as List;
    final alternatives = field['oneOf'] ?? field['anyOf'];
    if (alternatives is List &&
        alternatives.every((v) => v is Map && v.containsKey('const'))) {
      return alternatives.map((v) => (v as Map)['const']).toList();
    }
    return null;
  }

  void _submit() {
    final mode = widget.params['mode'] ?? 'form';
    if (mode == 'url') {
      _finish('accept');
      return;
    }
    try {
      final answers = <String, dynamic>{};
      for (final entry in _properties.entries) {
        final field = Map<String, dynamic>.from(entry.value as Map);
        if (field['type'] == 'boolean' ||
            field['enum'] is List ||
            field['oneOf'] is List ||
            (field['type'] == 'array' &&
                field['items'] is Map &&
                _choices(Map<String, dynamic>.from(field['items'] as Map)) !=
                    null)) {
          if (_values.containsKey(entry.key)) {
            answers[entry.key] = _values[entry.key];
          }
          continue;
        }
        final text = _controllers[entry.key]!.text;
        if (text.isEmpty) continue;
        answers[entry.key] = field['type'] == 'string' || field['type'] == null
            ? text
            : jsonDecode(text);
      }
      final error = validateMcpValue(answers, _schema);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      _finish('accept', answers);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = '${widget.params['mode'] ?? 'form'}';
    final isForm = ['form', 'openai/form', 'openaiForm'].contains(mode);
    final url = Uri.tryParse('${widget.params['url'] ?? ''}');
    return AlertDialog(
      title: Text(
          'MCP · ${widget.params['serverName'] ?? widget.params['title'] ?? ''}'),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                SelectableText(
                    '${widget.params['message'] ?? widget.params['description'] ?? ''}'),
                if (isForm)
                  ..._properties.entries.map((entry) {
                    final field = Map<String, dynamic>.from(entry.value as Map);
                    final required = (_schema['required'] as List? ?? [])
                        .contains(entry.key);
                    final label =
                        '${field['title'] ?? entry.key}${required ? ' *' : ''}';
                    Widget input;
                    if (field['type'] == 'array' &&
                        field['items'] is Map &&
                        _choices(Map<String, dynamic>.from(
                                field['items'] as Map)) !=
                            null) {
                      final items =
                          Map<String, dynamic>.from(field['items'] as Map);
                      final choices = _choices(items)!;
                      final options = items['anyOf'] ?? items['oneOf'];
                      final selected = (_values[entry.key] as List?) ?? [];
                      input = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label),
                            Wrap(spacing: 8, children: [
                              for (var i = 0; i < choices.length; i++)
                                FilterChip(
                                  label: Text(
                                      '${options is List ? (options[i] as Map)['title'] ?? choices[i] : choices[i]}'),
                                  selected: selected.contains(choices[i]),
                                  onSelected: (checked) => setState(() =>
                                      _values[entry.key] = checked
                                          ? [...selected, choices[i]]
                                          : selected
                                              .where((v) => v != choices[i])
                                              .toList()),
                                )
                            ]),
                          ]);
                    } else if (field['type'] == 'boolean') {
                      input = CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          value: _values[entry.key] == true,
                          onChanged: (value) =>
                              setState(() => _values[entry.key] = value));
                    } else if (field['enum'] is List ||
                        field['oneOf'] is List) {
                      final choices = field['enum'] as List? ??
                          (field['oneOf'] as List)
                              .map((v) => (v as Map)['const'])
                              .toList();
                      final labels = field['enumNames'] as List? ??
                          (field['oneOf'] as List?)
                              ?.map((v) => (v as Map)['title'])
                              .toList();
                      input = DropdownButtonFormField<int>(
                          initialValue: choices.contains(_values[entry.key])
                              ? choices.indexOf(_values[entry.key])
                              : null,
                          decoration: InputDecoration(labelText: label),
                          items: [
                            for (var i = 0; i < choices.length; i++)
                              DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                      '${labels != null && i < labels.length ? labels[i] ?? choices[i] : choices[i]}'))
                          ],
                          onChanged: (i) => setState(() {
                                if (i != null) _values[entry.key] = choices[i];
                              }));
                    } else {
                      input = TextField(
                          key: ValueKey('mcp-field-${entry.key}'),
                          controller: _controllers[entry.key],
                          obscureText: field['format'] == 'password',
                          maxLines: ['array', 'object'].contains(field['type'])
                              ? 4
                              : 1,
                          decoration: InputDecoration(
                              labelText: label,
                              helperText: field['description'] as String?,
                              helperMaxLines: 4));
                    }
                    return Padding(
                        padding: const EdgeInsets.only(top: 16), child: input);
                  }),
                if (mode == 'url') ...[
                  const SizedBox(height: 16),
                  SelectableText('$url'),
                  FilledButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: Text(mcpText(
                          context, 'Open authorization page', '打开授权页面')),
                      onPressed: url != null &&
                              ['http', 'https'].contains(url.scheme)
                          ? () async {
                              try {
                                final opened = await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                                if (mounted) {
                                  setState(() {
                                    if (!opened) {
                                      _error =
                                          'Could not open authorization page';
                                    }
                                  });
                                }
                              } catch (error) {
                                if (mounted) setState(() => _error = '$error');
                              }
                            }
                          : null),
                ],
                if (!isForm && mode != 'url')
                  Text(mcpText(
                      context,
                      'This verification requires a device capability this client does not provide. You can decline or cancel.',
                      '此验证需要当前客户端未提供的设备能力，可拒绝或取消。')),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]))),
      actions: [
        TextButton(
            onPressed: () => _finish('cancel'),
            child: Text(mcpText(context, 'Cancel', '取消'))),
        TextButton(
            onPressed: () => _finish('decline'),
            child: Text(mcpText(context, 'Decline', '拒绝'))),
        if (isForm || mode == 'url')
          FilledButton(
              onPressed: mode == 'url' &&
                      (url == null || !['http', 'https'].contains(url.scheme))
                  ? null
                  : _submit,
              child: Text(mcpText(
                  context,
                  mode == 'url' ? 'Authorization completed' : 'Submit',
                  mode == 'url' ? '已完成授权' : '提交'))),
      ],
    );
  }
}
