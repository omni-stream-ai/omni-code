import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/kws_wake_word_normalizer.dart';

void main() {
  group('KwsWakeWordNormalizer', () {
    final normalizer = KwsWakeWordNormalizer();

    test('converts known English phrase to model tokens', () {
      final result = normalizer.normalize('hey omni');

      expect(result.isSupported, isTrue);
      expect(result.normalized, 'HH EY1 OW1 M N IY0');
    });

    test('passes through model token sequences', () {
      final result = normalizer.normalize('HH EY1 OW1 M N IY0');

      expect(result.isSupported, isTrue);
      expect(result.normalized, 'HH EY1 OW1 M N IY0');
    });

    test('converts numbered pinyin to model tokens', () {
      final result = normalizer.normalize('ou1 mi3');

      expect(result.isSupported, isTrue);
      expect(result.normalized, 'ōu m ǐ');
    });

    test('rejects direct Chinese characters', () {
      final result = normalizer.normalize('欧米');

      expect(result.isSupported, isFalse);
      expect(result.unsupportedTokens, ['欧米']);
    });
  });
}
