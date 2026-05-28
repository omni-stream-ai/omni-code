import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/kws_model_download_service.dart';

void main() {
  group('KwsModelDownloadService', () {
    late Directory tempDir;
    late KwsModelDownloadService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kws-model-test-');
      service = KwsModelDownloadService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('installs model from archive root into target directory', () async {
      final extractRoot = Directory('${tempDir.path}/extract');
      final target = Directory('${tempDir.path}/model');
      await _createModelFiles(extractRoot);

      await service.installExtractedModelForTest(extractRoot.path, target.path);

      expect(await File('${target.path}/tokens.txt').exists(), isTrue);
      expect(await extractRoot.exists(), isFalse);
    });

    test('installs model from top-level archive directory', () async {
      final extractRoot = Directory('${tempDir.path}/extract');
      final archiveModelDir = Directory('${extractRoot.path}/archive-model');
      final target = Directory('${tempDir.path}/model');
      await _createModelFiles(archiveModelDir);

      await service.installExtractedModelForTest(extractRoot.path, target.path);

      expect(await File('${target.path}/tokens.txt').exists(), isTrue);
      expect(await Directory('${target.path}/archive-model').exists(), isFalse);
    });
  });
}

Future<void> _createModelFiles(Directory dir) async {
  await dir.create(recursive: true);
  for (final fileName in [
    'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
    'decoder-epoch-13-avg-2-chunk-16-left-64.onnx',
    'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
    'tokens.txt',
  ]) {
    await File('${dir.path}/$fileName').writeAsString('test');
  }
}
