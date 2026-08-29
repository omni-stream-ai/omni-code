import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/sentry_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('SentryConfiguration', () {
    test('is disabled without a DSN', () {
      final configuration = SentryConfiguration.parse(
        dsn: '  ',
        environment: '',
        tracesSampleRate: 'invalid',
        profilesSampleRate: 'invalid',
        memoryThresholdMb: 'invalid',
      );

      expect(configuration.enabled, isFalse);
      expect(configuration.environment, 'production');
      expect(configuration.tracesSampleRate, 0.1);
      expect(configuration.profilesSampleRate, 0.1);
      expect(configuration.memoryThresholdMb, 1024);
    });

    test('accepts a valid performance sample rate', () {
      final configuration = SentryConfiguration.parse(
        dsn: ' https://public@example.com/1 ',
        environment: ' staging ',
        tracesSampleRate: '0.25',
        profilesSampleRate: '0.05',
        memoryThresholdMb: '768',
      );

      expect(configuration.enabled, isTrue);
      expect(configuration.dsn, 'https://public@example.com/1');
      expect(configuration.environment, 'staging');
      expect(configuration.tracesSampleRate, 0.25);
      expect(configuration.profilesSampleRate, 0.05);
      expect(configuration.memoryThresholdMb, 768);
    });

    test('rejects a performance sample rate outside zero to one', () {
      final configuration = SentryConfiguration.parse(
        dsn: 'dsn',
        environment: 'production',
        tracesSampleRate: '2',
        profilesSampleRate: '-1',
        memoryThresholdMb: '0',
      );

      expect(configuration.tracesSampleRate, 0.1);
      expect(configuration.profilesSampleRate, 0.1);
      expect(configuration.memoryThresholdMb, 1024);
    });
  });

  test('sanitizes URL credentials, query data, and resource identifiers', () {
    expect(
      sanitizeSentryUrl(
        'https://user:password@example.com/projects/private-project/'
        'sessions/private-session/messages?token=secret#fragment',
      ),
      'https://example.com/projects/%7Bid%7D/sessions/%7Bid%7D/messages',
    );
    expect(
      sanitizeSentryUrl('/projects/project-1/sessions/session-1'),
      '/projects/%7Bid%7D/sessions/%7Bid%7D',
    );
  });

  test('sanitizes request and breadcrumb data before sending', () {
    final event = SentryEvent(
      request: SentryRequest(
        url: 'https://example.com/sessions/session-1/messages?token=secret',
        method: 'POST',
        data: {'prompt': 'private prompt'},
        headers: {'Authorization': 'Bearer secret'},
      ),
      breadcrumbs: [
        Breadcrumb(
          category: 'http',
          data: {
            'url': 'https://example.com/projects/project-1?token=secret',
            'status_code': 500,
            'payload': {'content': 'private message'},
          },
        ),
      ],
    );

    final sanitized = sanitizeSentryEvent(event, Hint());

    expect(sanitized.request!.url,
        'https://example.com/sessions/%7Bid%7D/messages');
    expect(sanitized.request!.method, 'POST');
    expect(sanitized.request!.data, isNull);
    expect(sanitized.request!.headers, isEmpty);
    expect(
      sanitized.breadcrumbs!.single.data,
      {
        'url': 'https://example.com/projects/%7Bid%7D',
        'status_code': 500,
        'payload': '[Filtered]',
      },
    );
  });

  test('redacts credentials and URL query strings in exception text', () {
    expect(
      redactSensitiveText(
        'token=abc failed at https://example.com/path?secret=value',
      ),
      'token=[Filtered] failed at https://example.com/path',
    );
  });
}
