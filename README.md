# Omni Code Client

[中文文档](README.zh-CN.md)

Flutter client for Omni Code. This repository now contains only the client app.
The desktop bridge lives in the sibling repository directory
`../omni-code-desktop-bridge`.

## Requirements

- `Flutter` 3.5+
- Android Studio or Xcode, depending on the target platform

## Run The Client

```bash
flutter pub get
flutter run
```

If the bridge is not available at the default address, pass it with a Dart
define:

```bash
flutter run --dart-define=ECHO_MATE_BRIDGE_URL=http://127.0.0.1:8787
```

## Connect To The Bridge

The client talks to the desktop bridge over HTTP and SSE. By default it uses
the current bridge URL configured in settings or via
`ECHO_MATE_BRIDGE_URL`.

If you are running the bridge from the sibling repository:

```bash
cd ../omni-code-desktop-bridge
cp .env.example .env
cargo run
```

If your bridge `.env` sets `ECHO_MATE_BRIDGE_TOKEN` or
`ECHO_MATE_ALLOWED_CLIENT_IDS`, the client app needs matching values:

1. Open the client app and go to Settings.
2. Copy the generated `Client ID`.
3. Put it in `../omni-code-desktop-bridge/.env`.
4. Put the `.env` value from `ECHO_MATE_BRIDGE_TOKEN` into the app's
   `Bridge Token` field.
5. Restart the desktop bridge, then save the app settings.

## Repository Layout

```text
android/
ios/
lib/
linux/
macos/
test/
web/
windows/
```

## Development Checks

```bash
flutter pub get
flutter analyze
```

## GitHub Actions Builds

This repository includes a client release workflow:

- `.github/workflows/build.yml`
- Workflow name: `Release Client`
- Trigger: `workflow_dispatch` or pushes that change `pubspec.yaml`
- Output: Android APK GitHub Release assets
- `main` can publish stable versions only
- Other branches must use prerelease versions such as `0.1.0-beta.1`

The release APK currently falls back to the Android debug signing config when
no local signing files are present. Configure signing secrets before
distributing release builds to users.

Recommended GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded Android keystore file
- `ANDROID_KEY_ALIAS`: Android signing key alias
- `ANDROID_KEY_PASSWORD`: Android signing key password
- `ANDROID_STORE_PASSWORD`: Android keystore password
- `ANDROID_GOOGLE_SERVICES_JSON_BASE64`: base64-encoded `android/app/google-services.json`

## Documentation

- [中文文档](README.zh-CN.md)
- [Client app notes](CLIENT_README.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Omni Code is licensed under the [MIT License](LICENSE).
