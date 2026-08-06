import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/tts_service.dart';

void main() {
  group('shouldStopFlutterTts', () {
    test('does not use flutter_tts to stop Linux system speech', () {
      expect(
        shouldStopFlutterTts(isWeb: false, isLinux: true),
        isFalse,
      );
    });

    test('uses flutter_tts on its supported native platforms', () {
      expect(
        shouldStopFlutterTts(isWeb: false, isLinux: false),
        isTrue,
      );
    });

    test('uses flutter_tts on web', () {
      expect(
        shouldStopFlutterTts(isWeb: true, isLinux: false),
        isTrue,
      );
    });
  });
}
