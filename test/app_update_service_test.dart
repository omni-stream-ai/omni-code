import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/app_update_service.dart';

void main() {
  group('AppUpdateService.resolveManifestUrl', () {
    test('keeps latest manifest when target version is empty', () {
      expect(
        AppUpdateService.resolveManifestUrl(
          manifestUrl:
              'https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json',
          targetVersion: '',
        ),
        'https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json',
      );
    });

    test('rewrites official latest GitHub manifest to a tagged release', () {
      expect(
        AppUpdateService.resolveManifestUrl(
          manifestUrl:
              'https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json',
          targetVersion: '0.2.1',
        ),
        'https://github.com/omni-stream-ai/omni-code/releases/download/v0.2.1/update.json',
      );
    });

    test('rewrites official tagged GitHub manifest to another tagged release',
        () {
      expect(
        AppUpdateService.resolveManifestUrl(
          manifestUrl:
              'https://github.com/omni-stream-ai/omni-code/releases/download/v0.3.0/update.json',
          targetVersion: 'v0.2.1',
        ),
        'https://github.com/omni-stream-ai/omni-code/releases/download/v0.2.1/update.json',
      );
    });

    test('keeps custom manifest URLs unchanged', () {
      expect(
        AppUpdateService.resolveManifestUrl(
          manifestUrl: 'https://bridge.example.com/app-update/manifest',
          targetVersion: '0.2.1',
        ),
        'https://bridge.example.com/app-update/manifest',
      );
    });
  });

  group('AppUpdateService.normalizeTargetVersion', () {
    test('trims and removes leading v prefix', () {
      expect(
        AppUpdateService.normalizeTargetVersion('  v0.2.1  '),
        '0.2.1',
      );
    });

    test('returns empty string for blank input', () {
      expect(AppUpdateService.normalizeTargetVersion('  '), isEmpty);
    });
  });

  group('AppUpdateService.isNewerVersionAvailable', () {
    test('prefers a higher version code', () {
      expect(
        AppUpdateService.isNewerVersionAvailableForTest(
          currentVersionName: '0.5.0',
          currentVersionCode: 8,
          candidate: const AppUpdateInfo(
            versionName: '0.5.0',
            versionCode: 9,
            apkUrl: 'https://example.com/app.apk',
            apkUrls: {},
            releaseNotes: '',
            force: false,
          ),
        ),
        isTrue,
      );
    });

    test('falls back to version name when version codes are equal', () {
      expect(
        AppUpdateService.isNewerVersionAvailableForTest(
          currentVersionName: '0.5.0',
          currentVersionCode: 8,
          candidate: const AppUpdateInfo(
            versionName: '0.5.1',
            versionCode: 8,
            apkUrl: 'https://example.com/app.apk',
            apkUrls: {},
            releaseNotes: '',
            force: false,
          ),
        ),
        isTrue,
      );
    });

    test('does not report update when candidate version is older', () {
      expect(
        AppUpdateService.isNewerVersionAvailableForTest(
          currentVersionName: '0.5.0',
          currentVersionCode: 8,
          candidate: const AppUpdateInfo(
            versionName: '0.4.9',
            versionCode: 8,
            apkUrl: 'https://example.com/app.apk',
            apkUrls: {},
            releaseNotes: '',
            force: false,
          ),
        ),
        isFalse,
      );
    });
  });
}
