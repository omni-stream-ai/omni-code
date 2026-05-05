import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/current_l10n.dart';

class AppUpdateService {
  AppUpdateService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const MethodChannel _channel = MethodChannel('omni_code/app_update');

  final http.Client _httpClient;

  Future<AppUpdateCheckResult> checkForUpdate(
      {required String manifestUrl}) async {
    final trimmedUrl = manifestUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw AppUpdateException(currentL10n().updateManifestUrlRequired);
    }

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw AppUpdateException(currentL10n().updateManifestUrlInvalid);
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

    try {
      final response = await _httpClient.get(uri, headers: const {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppUpdateException(
          currentL10n().updateCheckHttpFailed(response.statusCode),
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw AppUpdateException(currentL10n().updateManifestMustBeJson);
      }

      final update = AppUpdateInfo.fromJson(decoded).resolveAgainst(uri);
      return AppUpdateCheckResult(
        currentVersionName: packageInfo.version,
        currentVersionCode: currentBuildNumber,
        update: update.versionCode > currentBuildNumber ? update : null,
      );
    } on AppUpdateException {
      rethrow;
    } catch (error) {
      throw AppUpdateException(currentL10n().updateCheckFailed(error));
    }
  }

  Future<File> downloadApk(
    String apkUrl, {
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(apkUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw AppUpdateException(currentL10n().apkUrlInvalid);
    }
    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException(
        currentL10n().apkDownloadHttpFailed(response.statusCode),
      );
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/omni-code-update-${DateTime.now().millisecondsSinceEpoch}.apk',
    );
    final sink = file.openWrite();
    var receivedBytes = 0;
    final totalBytes = response.contentLength;

    try {
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          AppUpdateDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
    } finally {
      await sink.close();
    }

    return file;
  }

  Future<void> installApk(File apkFile) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.message ?? currentL10n().cannotOpenInstaller,
      );
    }
  }
}

class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return receivedBytes / total;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
    required this.force,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;
  final bool force;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final versionName = (json['version_name'] as String?)?.trim() ?? '';
    final apkUrl = (json['apk_url'] as String?)?.trim() ?? '';
    final versionCode = _parseVersionCode(json['version_code']);

    if (versionName.isEmpty) {
      throw AppUpdateException(currentL10n().updateManifestMissingVersionName);
    }
    if (versionCode <= 0) {
      throw AppUpdateException(currentL10n().updateManifestInvalidVersionCode);
    }
    if (apkUrl.isEmpty) {
      throw AppUpdateException(currentL10n().updateManifestMissingApkUrl);
    }

    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: apkUrl,
      releaseNotes: (json['release_notes'] as String?) ?? '',
      force: (json['force'] as bool?) ?? false,
    );
  }

  AppUpdateInfo resolveAgainst(Uri manifestUri) {
    final rawUri = Uri.parse(apkUrl);
    if (rawUri.hasScheme && rawUri.hasAuthority) {
      return this;
    }
    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: manifestUri.resolveUri(rawUri).toString(),
      releaseNotes: releaseNotes,
      force: force,
    );
  }

  static int _parseVersionCode(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.update,
  });

  final String currentVersionName;
  final int currentVersionCode;
  final AppUpdateInfo? update;

  bool get hasUpdate => update != null;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

final appUpdateService = AppUpdateService();
