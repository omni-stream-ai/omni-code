import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'process_performance_sampler.dart';

enum PerformanceAlert { highMemory, highCpu }

double? calculateCpuPercent(
  ProcessPerformanceSnapshot previous,
  ProcessPerformanceSnapshot current,
) {
  final previousCpu = previous.cpuTime;
  final currentCpu = current.cpuTime;
  if (previousCpu == null || currentCpu == null) return null;
  final wallMicros =
      current.timestamp.difference(previous.timestamp).inMicroseconds;
  final cpuMicros = currentCpu.inMicroseconds - previousCpu.inMicroseconds;
  if (wallMicros <= 0 || cpuMicros < 0) return null;
  return cpuMicros / wallMicros * 100;
}

class PerformanceAlertEvaluator {
  PerformanceAlertEvaluator({
    required this.memoryThresholdBytes,
    this.cpuThresholdPercent = 90,
    this.consecutiveSamples = 3,
    this.cooldown = const Duration(minutes: 30),
  });

  final int memoryThresholdBytes;
  final double cpuThresholdPercent;
  final int consecutiveSamples;
  final Duration cooldown;

  int _highMemorySamples = 0;
  int _highCpuSamples = 0;
  final Map<PerformanceAlert, DateTime> _lastAlerts = {};

  Set<PerformanceAlert> evaluate({
    required DateTime now,
    int? rssBytes,
    double? cpuPercent,
  }) {
    _highMemorySamples = rssBytes != null && rssBytes >= memoryThresholdBytes
        ? _highMemorySamples + 1
        : 0;
    _highCpuSamples = cpuPercent != null && cpuPercent >= cpuThresholdPercent
        ? _highCpuSamples + 1
        : 0;

    final alerts = <PerformanceAlert>{};
    if (_highMemorySamples >= consecutiveSamples &&
        _cooldownElapsed(PerformanceAlert.highMemory, now)) {
      alerts.add(PerformanceAlert.highMemory);
    }
    if (_highCpuSamples >= consecutiveSamples &&
        _cooldownElapsed(PerformanceAlert.highCpu, now)) {
      alerts.add(PerformanceAlert.highCpu);
    }
    for (final alert in alerts) {
      _lastAlerts[alert] = now;
    }
    return alerts;
  }

  bool _cooldownElapsed(PerformanceAlert alert, DateTime now) {
    final previous = _lastAlerts[alert];
    return previous == null || now.difference(previous) >= cooldown;
  }
}

class PerformanceMonitoringService with WidgetsBindingObserver {
  PerformanceMonitoringService({ProcessPerformanceSampler? sampler})
      : _sampler = sampler ?? ProcessPerformanceSampler();

  static const _sampleInterval = Duration(minutes: 1);
  static const _heartbeatInterval = Duration(seconds: 2);
  static const _hangThreshold = Duration(seconds: 8);
  static const _hangCooldown = Duration(minutes: 30);

  final ProcessPerformanceSampler _sampler;
  Timer? _sampleTimer;
  Timer? _heartbeatTimer;
  ProcessPerformanceSnapshot? _previousSnapshot;
  DateTime? _lastHeartbeat;
  DateTime? _lastHangAlert;
  PerformanceAlertEvaluator? _evaluator;
  bool _foreground = true;

  void start({required int memoryThresholdBytes}) {
    if (_sampleTimer != null) return;
    _evaluator = PerformanceAlertEvaluator(
      memoryThresholdBytes: memoryThresholdBytes,
    );
    WidgetsBinding.instance.addObserver(this);
    _sample();
    _lastHeartbeat = DateTime.now();
    _sampleTimer = Timer.periodic(_sampleInterval, (_) => _sample());
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  void stop() {
    _sampleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sampleTimer = null;
    _heartbeatTimer = null;
    _previousSnapshot = null;
    _lastHeartbeat = null;
    _evaluator = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _lastHeartbeat = _foreground ? DateTime.now() : null;
    if (!_foreground) _previousSnapshot = null;
  }

  void _sample() {
    if (!_foreground || !Sentry.isEnabled) return;
    final current = _sampler.sample();
    final cpuPercent = _previousSnapshot == null
        ? null
        : calculateCpuPercent(_previousSnapshot!, current);
    _previousSnapshot = current;
    final context = <String, dynamic>{
      if (current.rssBytes != null) 'rss_bytes': current.rssBytes,
      if (current.maxRssBytes != null) 'max_rss_bytes': current.maxRssBytes,
      if (cpuPercent != null) 'cpu_percent': cpuPercent,
      'sample_interval_seconds': _sampleInterval.inSeconds,
    };
    unawaited(Future.sync(() => Sentry.configureScope(
          (scope) => scope.setContexts('process_performance', context),
        )));

    final alerts = _evaluator?.evaluate(
          now: current.timestamp,
          rssBytes: current.rssBytes,
          cpuPercent: cpuPercent,
        ) ??
        const <PerformanceAlert>{};
    for (final alert in alerts) {
      final message = switch (alert) {
        PerformanceAlert.highMemory => 'Sustained high memory usage',
        PerformanceAlert.highCpu => 'Sustained high CPU usage',
      };
      unawaited(_captureWarning(message, context));
    }
  }

  void _heartbeat() {
    if (!_foreground || !Sentry.isEnabled) return;
    final now = DateTime.now();
    final previous = _lastHeartbeat;
    _lastHeartbeat = now;
    if (previous == null) return;
    final delay = now.difference(previous) - _heartbeatInterval;
    if (delay < _hangThreshold) return;
    if (_lastHangAlert != null &&
        now.difference(_lastHangAlert!) < _hangCooldown) {
      return;
    }
    _lastHangAlert = now;
    unawaited(_captureWarning(
      'Main isolate recovered after being unresponsive',
      {'delay_milliseconds': delay.inMilliseconds},
    ));
  }

  Future<void> _captureWarning(
    String message,
    Map<String, dynamic> context,
  ) {
    return Sentry.captureMessage(
      message,
      level: SentryLevel.warning,
      withScope: (scope) => scope.setContexts('performance_alert', context),
    );
  }
}

final performanceMonitoringService = PerformanceMonitoringService();
