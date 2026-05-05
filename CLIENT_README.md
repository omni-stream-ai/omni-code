# Omni Code Client

## Firebase Push Setup

Android remote push now uses the standard Firebase Android setup instead of
manual `--dart-define` values.

1. Open Firebase Console and add an Android app with package name
   `com.omnistreamai.code`.
2. Download `google-services.json`.
3. Place it at `android/app/google-services.json`.
4. Run the app normally:

```bash
flutter run -d <device-id>
```

Notes:
- `google-services.json` is intentionally gitignored.
- The bridge still needs server-side FCM credentials to send pushes:
  `ECHO_MATE_FCM_SERVICE_ACCOUNT_PATH=/path/to/service-account.json`.

## App Update Check

The client app can check an update manifest in Settings → App Update. If the
manifest URL is empty, the app requests the current bridge at
`/app-update/manifest`. When `version_code` is greater than the installed build
number, the app downloads the APK in-app, shows progress, and then opens
Android's installer.

The bridge serves the newest APK it can find under the local Flutter build
outputs, for example:

```bash
flutter build apk
cd ../omni-code-desktop-bridge
cargo run
```

Bridge endpoints:

```text
GET /app-update/manifest
GET /app-update/apk
```

The manifest response is generated automatically:

```json
{
  "version_name": "0.1.1",
  "version_code": 1710000000,
  "apk_url": "/app-update/apk",
  "release_notes": "Bridge 自动提供的 APK：.../app-release.apk",
  "force": false
}
```

Notes:
- Android users may need to allow installs from unknown sources.
- New APKs must be signed with the same certificate as the installed app.
- This is a full APK update flow, not binary diff patching.
