import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/message_image_paths.dart';

void main() {
  group('extractMessageImageReferences', () {
    test('extracts relative image paths from plain text', () {
      final references = extractMessageImageReferences(
        'Here is the output: assets/screenshot.png',
      );

      expect(references.map((item) => item.path).toList(), [
        'assets/screenshot.png',
      ]);
    });

    test('extracts svg paths', () {
      final references = extractMessageImageReferences(
        'Generated vector: assets/diagram.svg',
      );

      expect(references.map((item) => item.path).toList(), [
        'assets/diagram.svg',
      ]);
    });

    test('extracts absolute image paths and remote urls', () {
      final references = extractMessageImageReferences(
        'Open `/tmp/report.jpg` and https://example.com/photo.webp',
      );

      expect(references.map((item) => item.path).toList(), [
        '/tmp/report.jpg',
        'https://example.com/photo.webp',
      ]);
      expect(references[0].isAbsoluteLocalPath, isTrue);
      expect(references[1].isRemoteUrl, isTrue);
    });

    test('extracts base64 image data uris from markdown', () {
      const dataUri = 'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQImWP4z8AA'
          'AAMBAQAY3Y2xAAAAAElFTkSuQmCC';
      final references = extractMessageImageReferences(
        'Inline image ![preview]($dataUri)',
      );

      expect(references, hasLength(1));
      expect(references.single.path, dataUri);
      expect(references.single.isDataUri, isTrue);
      expect(references.single.displayPath, 'data:image/png;base64,...');
    });

    test('ignores non-image file paths', () {
      final references = extractMessageImageReferences(
        'Use lib/main.dart and docs/spec.pdf',
      );

      expect(references, isEmpty);
    });

    test('deduplicates repeated image paths', () {
      final references = extractMessageImageReferences(
        'assets/logo.png and `assets/logo.png`',
      );

      expect(references.map((item) => item.path).toList(), [
        'assets/logo.png',
      ]);
    });
  });
}
