import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'performance_monitoring_service.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);
const _sentryTracesSampleRate = String.fromEnvironment(
  'SENTRY_TRACES_SAMPLE_RATE',
  defaultValue: '0.1',
);
const _sentryProfilesSampleRate = String.fromEnvironment(
  'SENTRY_PROFILES_SAMPLE_RATE',
  defaultValue: '0.1',
);
const _sentryMemoryThresholdMb = String.fromEnvironment(
  'SENTRY_MEMORY_THRESHOLD_MB',
  defaultValue: '1024',
);

class SentryConfiguration {
  const SentryConfiguration({
    required this.dsn,
    required this.environment,
    required this.tracesSampleRate,
    required this.profilesSampleRate,
    required this.memoryThresholdMb,
  });

  factory SentryConfiguration.fromEnvironment() => SentryConfiguration.parse(
        dsn: _sentryDsn,
        environment: _sentryEnvironment,
        tracesSampleRate: _sentryTracesSampleRate,
        profilesSampleRate: _sentryProfilesSampleRate,
        memoryThresholdMb: _sentryMemoryThresholdMb,
      );

  factory SentryConfiguration.parse({
    required String dsn,
    required String environment,
    required String tracesSampleRate,
    String profilesSampleRate = '0.1',
    String memoryThresholdMb = '1024',
  }) {
    final parsedSampleRate = double.tryParse(tracesSampleRate);
    final parsedProfilesSampleRate = double.tryParse(profilesSampleRate);
    final parsedMemoryThresholdMb = int.tryParse(memoryThresholdMb);
    return SentryConfiguration(
      dsn: dsn.trim(),
      environment:
          environment.trim().isEmpty ? 'production' : environment.trim(),
      tracesSampleRate: parsedSampleRate != null &&
              parsedSampleRate >= 0 &&
              parsedSampleRate <= 1
          ? parsedSampleRate
          : 0.1,
      profilesSampleRate: parsedProfilesSampleRate != null &&
              parsedProfilesSampleRate >= 0 &&
              parsedProfilesSampleRate <= 1
          ? parsedProfilesSampleRate
          : 0.1,
      memoryThresholdMb:
          parsedMemoryThresholdMb != null && parsedMemoryThresholdMb > 0
              ? parsedMemoryThresholdMb
              : 1024,
    );
  }

  final String dsn;
  final String environment;
  final double tracesSampleRate;
  final double profilesSampleRate;
  final int memoryThresholdMb;

  bool get enabled => dsn.isNotEmpty;
}

Future<void> runWithSentry(
  AppRunner appRunner, {
  bool reportingEnabled = true,
}) async {
  final configuration = SentryConfiguration.fromEnvironment();
  if (!reportingEnabled || !configuration.enabled) {
    await appRunner();
    return;
  }

  await SentryFlutter.init(
    (options) => _configureSentryOptions(options, configuration),
    appRunner: appRunner,
  );
  performanceMonitoringService.start(
    memoryThresholdBytes: configuration.memoryThresholdMb * 1024 * 1024,
  );
}

Future<void> setSentryReportingEnabled(bool enabled) async {
  if (!enabled) {
    performanceMonitoringService.stop();
    await Sentry.close();
    return;
  }
  if (Sentry.isEnabled) return;
  final configuration = SentryConfiguration.fromEnvironment();
  if (!configuration.enabled) return;
  await SentryFlutter.init(
    (options) => _configureSentryOptions(options, configuration),
  );
  performanceMonitoringService.start(
    memoryThresholdBytes: configuration.memoryThresholdMb * 1024 * 1024,
  );
}

void _configureSentryOptions(
  SentryFlutterOptions options,
  SentryConfiguration configuration,
) {
  options
    ..dsn = configuration.dsn
    ..environment = configuration.environment
    ..tracesSampleRate = configuration.tracesSampleRate
    // ignore: experimental_member_use
    ..profilesSampleRate = configuration.profilesSampleRate
    ..sendDefaultPii = false
    ..maxRequestBodySize = MaxRequestBodySize.never
    ..enablePrintBreadcrumbs = false
    ..enableUserInteractionBreadcrumbs = false
    ..beforeSend = sanitizeSentryEvent
    ..beforeSendTransaction = sanitizeSentryTransaction
    ..beforeBreadcrumb = sanitizeSentryBreadcrumb;
}

Future<T> traceSentryOperation<T>(
  String name,
  String operation,
  Future<T> Function() action, {
  Map<String, num> measurements = const {},
}) async {
  if (!Sentry.isEnabled) return action();
  final parent = Sentry.getSpan();
  final span = parent?.startChild(operation, description: name) ??
      Sentry.startTransaction(name, operation, bindToScope: false);
  for (final entry in measurements.entries) {
    span.setMeasurement(entry.key, entry.value);
  }
  try {
    final result = await action();
    await span.finish(status: const SpanStatus.ok());
    return result;
  } catch (_) {
    await span.finish(status: const SpanStatus.internalError());
    rethrow;
  }
}

Future<void> captureHandledException(
  Object error,
  StackTrace stackTrace, {
  required String service,
}) async {
  if (!Sentry.isEnabled) return;
  await Sentry.captureException(
    error,
    stackTrace: stackTrace,
    withScope: (scope) => scope.setTag('service', service),
  );
}

SentryEvent sanitizeSentryEvent(SentryEvent event, Hint _) {
  final request = event.request;
  event.request = request == null
      ? null
      : SentryRequest(
          url: sanitizeSentryUrl(request.url),
          method: request.method,
        );
  event.breadcrumbs = event.breadcrumbs
      ?.map((breadcrumb) => sanitizeSentryBreadcrumb(breadcrumb, Hint())!)
      .toList(growable: false);
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception.value = redactSensitiveText(exception.value);
  }
  return event;
}

SentryTransaction sanitizeSentryTransaction(
  SentryTransaction transaction,
  Hint _,
) {
  transaction.transaction = sanitizeSentryUrl(transaction.transaction);
  return transaction;
}

Breadcrumb? sanitizeSentryBreadcrumb(Breadcrumb? breadcrumb, Hint _) {
  if (breadcrumb == null) return null;
  final data = breadcrumb.data;
  if (data == null) return breadcrumb;
  breadcrumb.data = <String, dynamic>{
    for (final entry in data.entries)
      entry.key: _sanitizeBreadcrumbValue(entry.key, entry.value),
  };
  return breadcrumb;
}

dynamic _sanitizeBreadcrumbValue(String key, dynamic value) {
  if (_isSensitiveKey(key)) return '[Filtered]';
  if (key.toLowerCase() == 'url' && value is String) {
    return sanitizeSentryUrl(value);
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _sanitizeBreadcrumbValue(
          entry.key.toString(),
          entry.value,
        ),
    };
  }
  if (value is List) {
    return value
        .map((item) => _sanitizeBreadcrumbValue(key, item))
        .toList(growable: false);
  }
  return value;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return const <String>{
    'authorization',
    'body',
    'content',
    'cookie',
    'message',
    'payload',
    'prompt',
    'secret',
    'text',
    'token',
  }.any(normalized.contains);
}

String? sanitizeSentryUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.isEmpty) return rawUrl;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return '[Filtered URL]';
  final segments = <String>[];
  var redactNextSegment = false;
  for (final segment in uri.pathSegments) {
    if (redactNextSegment) {
      segments.add('{id}');
      redactNextSegment = false;
      continue;
    }
    segments.add(segment);
    redactNextSegment = segment == 'projects' || segment == 'sessions';
  }
  final sanitized = uri
      .replace(
        pathSegments: segments,
        query: '',
        fragment: '',
        userInfo: '',
      )
      .toString()
      .replaceFirst(RegExp(r'[?#]+$'), '');
  return rawUrl.startsWith('/') && !sanitized.startsWith('/')
      ? '/$sanitized'
      : sanitized;
}

String? redactSensitiveText(String? value) {
  if (value == null) return null;
  return value
      .replaceAllMapped(
        RegExp(
          r'(authorization|cookie|password|prompt|secret|token)\s*[:=]\s*[^\s,;]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=[Filtered]',
      )
      .replaceAllMapped(
        RegExp(r'https?://[^\s]+'),
        (match) => sanitizeSentryUrl(match.group(0)) ?? '[Filtered URL]',
      );
}
