# Omni Code Client

## Push And Desktop Notifications

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

Desktop support now works as follows:

- `macOS`: local desktop notifications are supported while the app is running.
- `Linux`: local desktop notifications are supported while the app is running.
- `Windows`: local toast notifications are supported while the app is running.
- `Linux` and `Windows` are currently local-notification only. No remote push
  transport is wired for desktop platforms in this client.

## App Update Check

The client app checks updates from the official GitHub release manifest by
default:

`https://github.com/omni-stream-ai/omni-code/releases/latest/download/update.json`

When `version_code` is greater than the installed build number, the app
downloads the APK in-app, shows progress, and then opens Android's installer.

If needed, you can override the manifest URL in Settings → App Update and point
it to a self-hosted manifest, including the bridge endpoints below.

The bridge serves the newest APK it can find under the local Flutter build
outputs, for example:

```bash
flutter build apk
git clone https://github.com/omni-stream-ai/omni-code-bridge.git
cd omni-code-bridge
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
  "apk_urls": {
    "armeabi-v7a": "/app-update/apk?abi=armeabi-v7a",
    "arm64-v8a": "/app-update/apk?abi=arm64-v8a",
    "x86_64": "/app-update/apk?abi=x86_64"
  },
  "release_notes": "Bridge 自动提供的 APK：.../app-release.apk",
  "force": false
}
```

Notes:
- When `apk_urls` is present, the Android client prefers the matching ABI APK and
  falls back to `apk_url` as the universal package.
- Android users may need to allow installs from unknown sources.
- New APKs must be signed with the same certificate as the installed app.
- This is a full APK update flow, not binary diff patching.
