import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/workspace_agent_models.dart';

WorkspaceTask item(String id, String status,
        {String project = 'p',
        String session = 's',
        String? group,
        String? start = '2026-11-14T08:00:00Z',
        String update = '2026-11-14T10:00:00Z'}) =>
    WorkspaceTask.fromJson({
      'session_id': session,
      'project_id': project,
      'task': {
        'id': id,
        'title': 'Original $id',
        'summary': 'Original progress',
        'status': status,
        'created_at': start,
        'updated_at': update,
        if (status == 'completed' || status == 'cancelled')
          'completed_at': update,
        if (group != null)
          'group': {
            'id': group,
            'title': 'Workspace improvements',
            'summary': 'Review the delivered changes.'
          },
      }
    });

void main() {
  test(
      'task search matches case-insensitive terms across child and group metadata',
      () {
    final task = item('Login', 'completed', group: 'workspace');
    expect(task.matchesQuery('LOGIN progress'), isTrue);
    expect(task.matchesQuery('workspace improvements'), isTrue);
    expect(task.matchesQuery('ALPHA review', projectName: 'Alpha'), isTrue);
    expect(task.matchesQuery('missing'), isFalse);
    expect(task.matchesQuery('  '), isTrue);
  });

  test('group navigation follows session activity rather than task updates',
      () {
    final first = WorkspaceTask.fromJson({
      ...item('first', 'blocked',
              session: 'older', update: '2026-11-14T15:00:00Z')
          .toJson(),
      'updated_at': '2026-11-14T10:00:00Z',
    });
    final second = WorkspaceTask.fromJson({
      ...item('second', 'awaiting_review', session: 'newer').toJson(),
      'updated_at': '2026-11-14T12:00:00Z',
    });
    expect(WorkspaceTaskBundle([first, second]).latestSessionTask.sessionId,
        'newer');
    expect(WorkspaceTaskBundle([second, first]).latestSessionTask.sessionId,
        'newer');
    expect(WorkspaceTaskBundle([first]).latestSessionTask, first);
  });

  test('grouping retains original tasks, joins sessions and isolates projects',
      () {
    final first = item('first', 'awaiting_review', group: 'workspace');
    final second =
        item('second', 'blocked', group: 'workspace', session: 'other');
    final unrelated =
        item('other', 'awaiting_review', group: 'workspace', project: 'other');
    final bundles = WorkspaceTaskBundle.fromTasks([first, second, unrelated]);
    expect(bundles.length, 2);
    final merged = bundles.first;
    expect(merged.isGroup, isTrue);
    expect(merged.members, [first, second]);
    expect(merged.displayTask.title, 'Workspace improvements');
    expect(merged.displayTask.status, 'blocked');
    expect(first.title, 'Original first');
    expect(first.status, 'awaiting_review');
    expect(second.status, 'blocked');
    expect(bundles.last.isGroup, isFalse);
  });

  test('accepting one child preserves siblings and aggregate review state', () {
    final first = item('first', 'awaiting_review', group: 'workspace');
    final second = item('second', 'awaiting_review', group: 'workspace');
    final clock = DateTime.utc(2026, 11, 14, 12);
    final accepted = first.withState('completed', clock);
    final mixed = WorkspaceTaskBundle([accepted, second]);
    expect(mixed.displayTask.status, 'awaiting_review');
    expect(second.status, 'awaiting_review');
    expect(accepted.group!.id, first.group!.id);
    expect(accepted.createdAt, first.createdAt);
    expect(accepted.elapsedAt(clock.add(const Duration(days: 1))),
        const Duration(hours: 4));
    expect(second.elapsedAt(clock), const Duration(hours: 4));
    final finished =
        WorkspaceTaskBundle([accepted, second.withState('cancelled', clock)]);
    expect(finished.displayTask.status, 'completed');
    expect(finished.displayTask.elapsedAt(clock.add(const Duration(days: 1))),
        const Duration(hours: 4));
  });

  test('group timing starts at the earliest known task and omits unknown age',
      () {
    final first = item('first', 'awaiting_review',
        group: 'workspace', start: '2026-11-14T07:00:00Z');
    final second = item('second', 'in_progress',
        group: 'workspace',
        start: '2026-11-14T09:00:00Z',
        update: '2026-11-14T11:00:00Z');
    final bundle = WorkspaceTaskBundle([first, second]);
    expect(bundle.displayTask.createdAt, first.createdAt);
    expect(bundle.displayTask.lastUpdatedAt, second.lastUpdatedAt);
    expect(bundle.displayTask.elapsedAt(DateTime.utc(2026, 11, 14, 12)),
        const Duration(hours: 5));
    final unknown =
        item('unknown', 'awaiting_review', group: 'workspace', start: null);
    expect(
        WorkspaceTaskBundle([first, unknown])
            .displayTask
            .elapsedAt(DateTime.utc(2026, 11, 14, 12)),
        isNull);
  });
}
