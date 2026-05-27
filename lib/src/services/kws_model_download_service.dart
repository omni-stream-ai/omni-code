import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class KwsModelDownloadService {
  static const String _modelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2';
  static const String _modelDirName = 'sherpa-onnx-kws-zipformer-zh-en-3M';

  Future<String> get modelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelDirName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await modelPath;
    final dir = Directory(path);
    return _isValidModelDirectory(dir);
  }

  Future<double?> get downloadProgress async {
    // TODO: Implement progress tracking
    return null;
  }

  Future<void> downloadModel({
    void Function(double progress)? onProgress,
    void Function(String error)? onError,
    void Function()? onComplete,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadPath = '${dir.path}/kws-model.tar.bz2';
      final extractPath = '${dir.path}/$_modelDirName';
      final extractRootPath = '${dir.path}/kws-model-extract';

      debugPrint('[kws-download] starting download from $_modelUrl');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_modelUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      var downloadedBytes = 0;

      final file = File(downloadPath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(downloadedBytes / contentLength);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      debugPrint('[kws-download] download complete, extracting...');

      final extractRoot = Directory(extractRootPath);
      if (await extractRoot.exists()) {
        await extractRoot.delete(recursive: true);
      }
      await extractRoot.create(recursive: true);

      await _extractArchive(downloadPath, extractRootPath);
      await _installExtractedModel(extractRootPath, extractPath);

      await file.delete();
      if (await extractRoot.exists()) {
        await extractRoot.delete(recursive: true);
      }

      debugPrint('[kws-download] extraction complete');
      onComplete?.call();
    } catch (e) {
      debugPrint('[kws-download] error: $e');
      onError?.call(e.toString());
    }
  }

  Future<void> _extractArchive(String archivePath, String outputDir) async {
    final result = await Process.run(
      'tar',
      ['-xjf', archivePath, '-C', outputDir],
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to extract archive: ${result.stderr}');
    }
  }

  @visibleForTesting
  Future<void> installExtractedModelForTest(
    String extractRootPath,
    String targetPath,
  ) {
    return _installExtractedModel(extractRootPath, targetPath);
  }

  Future<void> _installExtractedModel(
    String extractRootPath,
    String targetPath,
  ) async {
    final sourceDir = await _findExtractedModelDirectory(
      Directory(extractRootPath),
    );
    final targetDir = Directory(targetPath);
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    try {
      await sourceDir.rename(targetPath);
    } on FileSystemException {
      await _copyDirectory(sourceDir, targetDir);
      await sourceDir.delete(recursive: true);
    }
    if (!await _isValidModelDirectory(targetDir)) {
      throw Exception('Extracted KWS model is missing required files');
    }
  }

  Future<Directory> _findExtractedModelDirectory(Directory root) async {
    if (await _isValidModelDirectory(root)) {
      return root;
    }
    await for (final entity in root.list()) {
      if (entity is Directory && await _isValidModelDirectory(entity)) {
        return entity;
      }
    }
    throw Exception('Extracted archive does not contain a supported KWS model');
  }

  Future<bool> _isValidModelDirectory(Directory dir) async {
    if (!await dir.exists()) {
      return false;
    }
    final requiredFiles = [
      'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      'decoder-epoch-13-avg-2-chunk-16-left-64.onnx',
      'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      'tokens.txt',
    ];
    for (final fileName in requiredFiles) {
      if (!await File('${dir.path}/$fileName').exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      final newPath = '${target.path}/$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<void> deleteModel() async {
    final path = await modelPath;
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
