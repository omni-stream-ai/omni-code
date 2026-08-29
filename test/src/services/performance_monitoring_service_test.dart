import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/performance_monitoring_service.dart';
import 'package:omni_code/src/services/process_performance_sampler.dart';

void main() {
  test('calculates process CPU percentage from CPU and wall time deltas', () {
    final start = DateTime(2026, 1, 1);
    final percent = calculateCpuPercent(
      ProcessPerformanceSnapshot(
        timestamp: start,
        cpuTime: const Duration(seconds: 2),
      ),
      ProcessPerformanceSnapshot(
        timestamp: start.add(const Duration(seconds: 10)),
        cpuTime: const Duration(seconds: 5),
      ),
    );

    expect(percent, 30);
  });

  test('returns null for unavailable or invalid CPU deltas', () {
    final now = DateTime(2026, 1, 1);
    const cpu = Duration(seconds: 1);
    expect(
      calculateCpuPercent(
        ProcessPerformanceSnapshot(timestamp: now),
        ProcessPerformanceSnapshot(timestamp: now, cpuTime: cpu),
      ),
      isNull,
    );
    expect(
      calculateCpuPercent(
        ProcessPerformanceSnapshot(timestamp: now, cpuTime: cpu),
        ProcessPerformanceSnapshot(timestamp: now, cpuTime: cpu),
      ),
      isNull,
    );
  });

  group('PerformanceAlertEvaluator', () {
    late DateTime now;
    late PerformanceAlertEvaluator evaluator;

    setUp(() {
      now = DateTime(2026, 1, 1);
      evaluator = PerformanceAlertEvaluator(memoryThresholdBytes: 1000);
    });

    test('alerts after three consecutive high-memory samples', () {
      expect(evaluator.evaluate(now: now, rssBytes: 1000), isEmpty);
      expect(evaluator.evaluate(now: now, rssBytes: 1200), isEmpty);
      expect(
        evaluator.evaluate(now: now, rssBytes: 1100),
        {PerformanceAlert.highMemory},
      );
    });

    test('normal sample resets consecutive high-memory count', () {
      evaluator.evaluate(now: now, rssBytes: 1200);
      evaluator.evaluate(now: now, rssBytes: 900);
      evaluator.evaluate(now: now, rssBytes: 1200);
      expect(evaluator.evaluate(now: now, rssBytes: 1200), isEmpty);
    });

    test('cooldown suppresses repeated alerts', () {
      for (var i = 0; i < 3; i++) {
        evaluator.evaluate(now: now, rssBytes: 1200);
      }
      expect(
        evaluator.evaluate(
          now: now.add(const Duration(minutes: 29)),
          rssBytes: 1200,
        ),
        isEmpty,
      );
      expect(
        evaluator.evaluate(
          now: now.add(const Duration(minutes: 30)),
          rssBytes: 1200,
        ),
        {PerformanceAlert.highMemory},
      );
    });

    test('CPU alert is evaluated independently from memory', () {
      for (var i = 0; i < 2; i++) {
        expect(
          evaluator.evaluate(now: now, rssBytes: 100, cpuPercent: 95),
          isEmpty,
        );
      }
      expect(
        evaluator.evaluate(now: now, rssBytes: 100, cpuPercent: 95),
        {PerformanceAlert.highCpu},
      );
    });
  });
}
