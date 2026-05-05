import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
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
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

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

      final parsedUpdate = await AppUpdateInfo.fromJson(
        decoded,
        deviceInfo: _deviceInfo,
      );
      final update = parsedUpdate.resolveAgainst(uri);
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
    required this.apkUrls,
    required this.releaseNotes,
    required this.force,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final Map<String, String> apkUrls;
  final String releaseNotes;
  final bool force;

  static const List<String> _androidAbiPriority = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  ];

  static const Map<String, List<String>> _androidAbiAliases = {
    'arm64-v8a': ['arm64-v8a', 'arm64', 'aarch64'],
    'armeabi-v7a': ['armeabi-v7a', 'armeabi', 'arm32', 'armv7'],
    'x86_64': ['x86_64', 'x64'],
  };

  static Future<AppUpdateInfo> fromJson(
    Map<String, dynamic> json, {
    required DeviceInfoPlugin deviceInfo,
  }) async {
    final versionName = (json['version_name'] as String?)?.trim() ?? '';
    final fallbackApkUrl = (json['apk_url'] as String?)?.trim() ?? '';
    final versionCode = _parseVersionCode(json['version_code']);
    final apkUrls = _parseApkUrls(json['apk_urls']);

    if (versionName.isEmpty) {
      throw AppUpdateException(currentL10n().updateManifestMissingVersionName);
    }
    if (versionCode <= 0) {
      throw AppUpdateException(currentL10n().updateManifestInvalidVersionCode);
    }
    if (fallbackApkUrl.isEmpty && apkUrls.isEmpty) {
      throw AppUpdateException(currentL10n().updateManifestMissingApkUrl);
    }

    final selectedApkUrl = await _selectBestApkUrl(
      deviceInfo: deviceInfo,
      fallbackApkUrl: fallbackApkUrl,
      apkUrls: apkUrls,
    );

    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: selectedApkUrl,
      apkUrls: apkUrls,
      releaseNotes: (json['release_notes'] as String?) ?? '',
      force: (json['force'] as bool?) ?? false,
    );
  }

  AppUpdateInfo resolveAgainst(Uri manifestUri) {
    final resolvedApkUrls = <String, String>{};
    for (final entry in apkUrls.entries) {
      final rawUri = Uri.parse(entry.value);
      resolvedApkUrls[entry.key] =
          rawUri.hasScheme && rawUri.hasAuthority
              ? entry.value
              : manifestUri.resolveUri(rawUri).toString();
    }

    final rawUri = Uri.parse(apkUrl);
    final resolvedApkUrl =
        rawUri.hasScheme && rawUri.hasAuthority
            ? apkUrl
            : manifestUri.resolveUri(rawUri).toString();

    if (resolvedApkUrls.isEmpty && resolvedApkUrl == apkUrl) {
      return this;
    }

    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: resolvedApkUrl,
      apkUrls: resolvedApkUrls,
      releaseNotes: releaseNotes,
      force: force,
    );
  }

  static Map<String, String> _parseApkUrls(Object? raw) {
    if (raw is! Map) {
      return const {};
    }

    final normalized = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key is String ? (entry.key as String).trim() : '';
      final value =
          entry.value is String ? (entry.value as String).trim() : '';
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      normalized[key] = value;
    }
    return normalized;
  }

  static Future<String> _selectBestApkUrl({
    required DeviceInfoPlugin deviceInfo,
    required String fallbackApkUrl,
    required Map<String, String> apkUrls,
  }) async {
    if (!Platform.isAndroid || apkUrls.isEmpty) {
      return fallbackApkUrl.isNotEmpty ? fallbackApkUrl : apkUrls.values.first;
    }

    try {
      final info = await deviceInfo.androidInfo;
      final supportedAbis = {
        ...info.supported64BitAbis,
        ...info.supported32BitAbis,
        ...info.supportedAbis,
      }.map((abi) => abi.trim().toLowerCase()).where((abi) => abi.isNotEmpty);

      for (final candidate in _androidAbiPriority) {
        if (!apkUrls.containsKey(candidate)) {
          continue;
        }

        final aliases = _androidAbiAliases[candidate] ?? const <String>[];
        if (aliases.any(supportedAbis.contains)) {
          return apkUrls[candidate]!;
        }
      }
    } catch (_) {
      // Fall back to the universal APK when device ABI detection fails.
    }

    return fallbackApkUrl.isNotEmpty
        ? fallbackApkUrl
        : (apkUrls['arm64-v8a'] ??
              apkUrls['armeabi-v7a'] ??
              apkUrls['x86_64'] ??
              apkUrls.values.first);
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
