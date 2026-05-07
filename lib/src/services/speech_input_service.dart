import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechInputService {
  SpeechInputService({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  bool get isListening => _speech.isListening;

  Future<List<LocaleName>> availableLocales() {
    return _speech.locales();
  }

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error, bool permanent)? onError,
  }) {
    return _speech.initialize(
      debugLogging: true,
      onStatus: onStatus,
      onError: (SpeechRecognitionError error) {
        onError?.call(error.errorMsg, error.permanent);
      },
    );
  }

  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {
    await _speech.listen(
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.confirmation,
      ),
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
      },
    );
  }

  Future<void> stopListening() {
    return _speech.stop();
  }

  Future<void> cancel() {
    return _speech.cancel();
  }
}
