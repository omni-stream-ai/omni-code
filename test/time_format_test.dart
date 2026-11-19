import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/utils/time_format.dart';
import 'package:omni_code/src/workspace_agent_models.dart';

void main() {
  final now = DateTime(2026, 11, 13, 12);

  test('relative update times use compact units then a local calendar date',
      () {
    for (final item in [
      (const Duration(seconds: -60), '刚刚', 'just now'),
      (const Duration(seconds: 59), '刚刚', 'just now'),
      (const Duration(minutes: 1), '1分钟前', '1 min ago'),
      (const Duration(minutes: 59), '59分钟前', '59 min ago'),
      (const Duration(hours: 1), '1小时前', '1 hr ago'),
      (const Duration(hours: 23), '23小时前', '23 hr ago'),
      (const Duration(days: 1), '1天前', '1 day ago'),
      (const Duration(days: 6), '6天前', '6 days ago'),
      (const Duration(days: 7), '2026年11月6日', '2026-11-06'),
      (const Duration(days: 365), '2025年11月13日', '2025-11-13'),
    ]) {
      final value = now.subtract(item.$1);
      expect(formatRelativeTime(value, now: now, languageCode: 'zh'), item.$2);
      expect(formatRelativeTime(value, now: now), item.$3);
    }
    final local = DateTime(2026, 1, 2, 1);
    expect(formatRelativeTime(local.toUtc(), now: now), '2026-01-02');
    expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)),
            now: now, relativeWindow: const Duration(days: 1)),
        '2026-11-11');
  });

  test('task durations use at most two meaningful units', () {
    for (final item in [
      (Duration.zero, '不足1分钟', '<1 min'),
      (const Duration(seconds: 59), '不足1分钟', '<1 min'),
      (const Duration(minutes: 1), '1分钟', '1 min'),
      (const Duration(minutes: 59), '59分钟', '59 min'),
      (const Duration(hours: 1), '1小时', '1 hr'),
      (const Duration(hours: 2, minutes: 12), '2小时12分钟', '2 hr 12 min'),
      (const Duration(days: 1), '1天', '1 d'),
      (const Duration(days: 2, hours: 3, minutes: 40), '2天3小时', '2 d 3 hr'),
    ]) {
      expect(formatElapsedDuration(item.$1, languageCode: 'zh'), item.$2);
      expect(formatElapsedDuration(item.$1), item.$3);
    }
  });

  Map<String, dynamic> entry(String id, String status,
          {String? created, String? ended}) =>
      {
        'session_id': 'same-conversation',
        'project_id': 'p',
        'updated_at': '2026-11-13T12:00:00Z',
        'task': {
          'id': id,
          'title': id,
          'summary': 'Progress',
          'status': status,
          if (created != null) 'created_at': created,
          if (ended != null) 'updated_at': ended,
          if (ended != null) 'completed_at': ended
        },
      };

  test('each task has its own start and terminal duration stops advancing', () {
    final clock = DateTime.utc(2026, 11, 13, 12);
    final first = WorkspaceTask.fromJson(
        entry('first', 'in_progress', created: '2026-11-13T08:00:00Z'));
    final second = WorkspaceTask.fromJson(
        entry('second', 'blocked', created: '2026-11-13T11:00:00Z'));
    expect(first.elapsedAt(clock), const Duration(hours: 4));
    expect(second.elapsedAt(clock), const Duration(hours: 1));
    for (final status in ['completed', 'cancelled']) {
      final done = WorkspaceTask.fromJson(entry('done', status,
          created: '2026-11-13T08:00:00Z', ended: '2026-11-13T09:15:00Z'));
      expect(done.elapsedAt(clock), const Duration(hours: 1, minutes: 15));
      expect(done.elapsedAt(clock.add(const Duration(days: 2))),
          done.elapsedAt(clock));
    }
    final archived = WorkspaceTask.fromJson({
      ...entry('second', 'blocked', created: '2026-11-13T11:00:00Z'),
      'archived': true
    });
    expect(archived.archived, isTrue);
    expect(archived.isOpen, isTrue);
    expect(archived.elapsedAt(clock), second.elapsedAt(clock));
  });

  test('legacy and invalid task dates do not invent an elapsed duration', () {
    final old = WorkspaceTask.fromJson(entry('old', 'pending'));
    expect(old.createdAt, isNull);
    expect(old.taskUpdatedAt, isNull);
    expect(old.archived, isFalse);
    expect(old.elapsedAt(now), isNull);
    final invalid = WorkspaceTask.fromJson(
        entry('invalid', 'completed', created: 'bad', ended: 'bad'));
    expect(invalid.elapsedAt(now), isNull);
    final backwards = WorkspaceTask.fromJson(entry('backwards', 'completed',
        created: '2026-11-13T12:00:00Z', ended: '2026-11-13T11:00:00Z'));
    expect(backwards.elapsedAt(now), isNull);
  });
}
