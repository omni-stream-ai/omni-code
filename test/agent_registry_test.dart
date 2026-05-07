import 'package:flutter_test/flutter_test.dart';

import 'package:omni_code/src/models.dart';

void main() {
  group('Agent registry', () {
    test('selectable values expose the supported agents', () {
      expect(
        AgentKind.selectableValues.map((agent) => agent.id).toList(),
        ['codex', 'claude_code', 'open_code'],
      );
    });

    test('parseAgentKind accepts supported aliases', () {
      expect(parseAgentKind('codex'), AgentKind.codex);
      expect(parseAgentKind('claude_code'), AgentKind.claudecode);
      expect(parseAgentKind('claudecode'), AgentKind.claudecode);
      expect(parseAgentKind('open_code'), AgentKind.opencode);
      expect(parseAgentKind('opencode'), AgentKind.custom);
      expect(parseAgentKind('unknown-agent'), AgentKind.custom);
    });
  });
}
