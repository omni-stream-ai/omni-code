class ProcessPerformanceSnapshot {
  const ProcessPerformanceSnapshot({
    required this.timestamp,
    this.rssBytes,
    this.maxRssBytes,
    this.cpuTime,
  });

  final DateTime timestamp;
  final int? rssBytes;
  final int? maxRssBytes;
  final Duration? cpuTime;
}

class ProcessPerformanceSampler {
  ProcessPerformanceSnapshot sample() =>
      ProcessPerformanceSnapshot(timestamp: DateTime.now());
}
