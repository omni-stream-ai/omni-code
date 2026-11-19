import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

bool isUsableBridgeSetupModel(ModelProviderConfig provider) {
  final uri = Uri.tryParse(provider.baseUrl.trim());
  return provider.enabled &&
      (provider.model?.trim().isNotEmpty ?? false) &&
      uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

class BridgeAgentToolCall {
  const BridgeAgentToolCall(
      {required this.id, required this.name, required this.arguments});
  final String id, name;
  final Map<String, dynamic> arguments;
}

class BridgeAgentMessage {
  const BridgeAgentMessage(
    this.role,
    this.text, {
    this.calls = const [],
    this.callId,
    this.nativeAssistant,
    this.hidden = false,
  });
  final String role, text;
  final List<BridgeAgentToolCall> calls;
  final String? callId;
  final bool hidden;
  // Preserve provider reasoning/signatures alongside tool calls on follow-ups.
  final Map<String, dynamic>? nativeAssistant;
}

class BridgeAgentModelException implements Exception {
  const BridgeAgentModelException({this.statusCode});
  final int? statusCode;
}

abstract class BridgeSetupAgentModel {
  Future<BridgeAgentMessage> next(
      ModelProviderConfig provider, List<BridgeAgentMessage> messages);
  void close();
}

class HttpBridgeSetupAgentModel implements BridgeSetupAgentModel {
  HttpBridgeSetupAgentModel({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;

  static const _tools = [
    {
      'name': 'run_command',
      'description':
          'Propose one local shell command to diagnose or repair the Bridge installation. The user must approve the exact command before it runs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {'type': 'string'},
          'reason': {
            'type': 'string',
            'description':
                'Explain what this command changes or checks, in the user language.'
          },
        },
        'required': ['command', 'reason'],
        'additionalProperties': false
      }
    },
    {
      'name': 'retry_install',
      'description':
          'Retry the built-in verified Bridge installer after fixing its environment. A successful installation also connects this client.',
      'parameters': {
        'type': 'object',
        'properties': {},
        'required': [],
        'additionalProperties': false
      }
    },
    {
      'name': 'connect_bridge',
      'description':
          'Verify that the local Bridge is healthy, authorize only this desktop client using the installed CLI, and finish setup. Call after installing or starting Bridge by another supported method.',
      'parameters': {
        'type': 'object',
        'properties': {},
        'required': [],
        'additionalProperties': false
      }
    },
  ];

  @override
  Future<BridgeAgentMessage> next(
      ModelProviderConfig provider, List<BridgeAgentMessage> messages) async {
    if (!isUsableBridgeSetupModel(provider)) {
      throw const BridgeAgentModelException();
    }
    final base = provider.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final suffix = switch (provider.format) {
      ApiFormat.openaiCompatible => '/chat/completions',
      ApiFormat.anthropicMessages => '/messages',
      ApiFormat.codex => '/responses',
    };
    final request = http.Request(
        'POST', Uri.parse(base.endsWith(suffix) ? base : '$base$suffix'))
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (provider.apiKey.isNotEmpty &&
            provider.format != ApiFormat.anthropicMessages)
          'Authorization': 'Bearer ${provider.apiKey}',
        if (provider.format == ApiFormat.anthropicMessages) ...{
          'anthropic-version': '2023-06-01',
          if (provider.apiKey.isNotEmpty) 'x-api-key': provider.apiKey,
        },
      })
      ..body = jsonEncode(_body(provider, messages));
    try {
      final response =
          await http.Response.fromStream(await _client.send(request))
              .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BridgeAgentModelException(statusCode: response.statusCode);
      }
      return _parse(provider.format,
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
    } on BridgeAgentModelException {
      rethrow;
    } catch (_) {
      // Never surface provider response bodies, headers, URLs, or API keys.
      throw const BridgeAgentModelException();
    }
  }

  Map<String, dynamic> _body(
      ModelProviderConfig provider, List<BridgeAgentMessage> messages) {
    final system = messages
        .where((message) => message.role == 'system')
        .map((message) => message.text)
        .join('\n');
    final turns = messages.where((message) => message.role != 'system');
    if (provider.format == ApiFormat.anthropicMessages) {
      final anthropicMessages = <Map<String, dynamic>>[];
      var collectingToolResults = false;
      for (final message in turns) {
        if (message.role == 'tool') {
          final content = {
            'type': 'tool_result',
            'tool_use_id': message.callId,
            'content': message.text
          };
          if (collectingToolResults) {
            (anthropicMessages.last['content'] as List).add(content);
          } else {
            anthropicMessages.add({
              'role': 'user',
              'content': [content]
            });
          }
          collectingToolResults = true;
        } else {
          collectingToolResults = false;
          anthropicMessages.add(message.nativeAssistant ??
              {'role': message.role, 'content': message.text});
        }
      }
      return {
        'model': provider.model,
        'max_tokens': 4096,
        'system': system,
        'tools': [
          for (final tool in _tools)
            {
              'name': tool['name'],
              'description': tool['description'],
              'input_schema': tool['parameters']
            }
        ],
        'messages': anthropicMessages,
      };
    }
    if (provider.format == ApiFormat.codex) {
      final input = <dynamic>[];
      for (final message in turns) {
        if (message.role == 'tool') {
          input.add({
            'type': 'function_call_output',
            'call_id': message.callId,
            'output': message.text
          });
        } else if (message.nativeAssistant != null) {
          input.addAll(message.nativeAssistant!['output'] as List);
        } else {
          input.add({'role': message.role, 'content': message.text});
        }
      }
      return {
        'model': provider.model,
        'instructions': system,
        'store': false,
        'include': ['reasoning.encrypted_content'],
        'tools': [
          for (final tool in _tools)
            {'type': 'function', ...tool, 'strict': true}
        ],
        'input': input,
      };
    }
    return {
      'model': provider.model,
      'stream': false,
      'tools': [
        for (final tool in _tools) {'type': 'function', 'function': tool}
      ],
      'messages': [
        for (final message in messages)
          if (message.role == 'tool')
            {
              'role': 'tool',
              'tool_call_id': message.callId,
              'content': message.text
            }
          else if (message.nativeAssistant != null)
            message.nativeAssistant
          else
            {'role': message.role, 'content': message.text}
      ],
    };
  }

  BridgeAgentMessage _parse(ApiFormat format, Map<String, dynamic> body) {
    final calls = <BridgeAgentToolCall>[];
    final text = <String>[];
    Map<String, dynamic> native;
    if (format == ApiFormat.openaiCompatible) {
      native = ((body['choices'] as List).first as Map)['message']
          as Map<String, dynamic>;
      final content = native['content'];
      if (content is String) text.add(content);
      if (content is List) {
        text.addAll(content
            .whereType<Map>()
            .map((item) => item['text'])
            .whereType<String>());
      }
      for (final raw in (native['tool_calls'] as List? ?? const [])) {
        final function = raw['function'] as Map;
        calls.add(BridgeAgentToolCall(
            id: raw['id'] as String,
            name: function['name'] as String,
            arguments: jsonDecode(function['arguments'] as String)
                as Map<String, dynamic>));
      }
    } else if (format == ApiFormat.anthropicMessages) {
      final content = body['content'] as List;
      native = {'role': 'assistant', 'content': content};
      for (final item in content) {
        if (item['type'] == 'text') text.add(item['text'] as String);
        if (item['type'] == 'tool_use') {
          calls.add(BridgeAgentToolCall(
              id: item['id'] as String,
              name: item['name'] as String,
              arguments: item['input'] as Map<String, dynamic>));
        }
      }
    } else {
      final output = body['output'] as List;
      native = {'output': output};
      for (final item in output) {
        if (item['type'] == 'message') {
          for (final content in item['content'] as List) {
            if (content['type'] == 'output_text') {
              text.add(content['text'] as String);
            }
          }
        }
        if (item['type'] == 'function_call') {
          calls.add(BridgeAgentToolCall(
              id: item['call_id'] as String,
              name: item['name'] as String,
              arguments: jsonDecode(item['arguments'] as String)
                  as Map<String, dynamic>));
        }
      }
    }
    if (calls.length > 8 ||
        calls.any((call) => call.id.isEmpty) ||
        calls.map((call) => call.id).toSet().length != calls.length ||
        (calls.isEmpty && text.join().trim().isEmpty)) {
      throw const BridgeAgentModelException();
    }
    return BridgeAgentMessage('assistant', text.join('\n'),
        calls: calls, nativeAssistant: native);
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
