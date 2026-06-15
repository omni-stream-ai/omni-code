import 'package:flutter_test/flutter_test.dart';

import 'package:omni_code/src/models.dart';

void main() {
  group('Agent registry', () {
    test('fallback agent descriptors degrade to raw ids', () {
      expect(fallbackAgentDescriptor('codex').id, 'codex');
      expect(fallbackAgentDescriptor('claudecode').id, 'claudecode');
      expect(fallbackAgentDescriptor('open_code').id, 'open_code');
      expect(fallbackAgentDescriptor('unknown-agent').id, 'unknown-agent');
      expect(fallbackAgentDescriptor('unknown-agent').label, 'unknown-agent');
      expect(fallbackAgentDescriptor(null).label, 'Agent');
    });

    test('agent descriptor decodes server metadata', () {
      final summary = AgentSummary.fromJson({
        'id': 'claude_code',
        'label': 'Claude Code',
        'aliases': ['claude_code', 'claudecode'],
        'selectable': true,
        'default_selected': false,
        'compatible_formats': ['anthropic-messages'],
        'installed': true,
        'installed_path': '/usr/local/bin/claude',
        'install_hint': 'manual',
      });

      expect(summary.id, 'claude_code');
      expect(summary.label, 'Claude Code');
      expect(summary.aliases, ['claude_code', 'claudecode']);
      expect(summary.selectable, isTrue);
      expect(summary.defaultSelected, isFalse);
      expect(summary.compatibleFormats, [ApiFormat.anthropicMessages]);
    });

    test('unknown descriptor falls back to custom and remains unselectable', () {
      final summary = AgentSummary.fromJson({
        'id': 'custom',
        'aliases': ['fallback'],
        'installed': false,
        'install_hint': 'n/a',
      });

      expect(summary.label, 'custom');
      expect(summary.selectable, isTrue);
      expect(summary.compatibleFormats, isEmpty);
    });
  });
}
