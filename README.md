# Omni Code Client

[中文文档](README.zh-CN.md)

Flutter client for Omni Code. This repository now contains only the client app.
The desktop bridge lives in a separate repository:
`https://github.com/omni-stream-ai/omni-code-bridge`.

Omni Code Client is a cross-platform client for desktop agent sessions. It connects
to the bridge over HTTP and SSE so you can manage projects, open sessions, send
messages, receive reply notifications, and handle approval prompts across
mobile and desktop devices.

## Who It's For

- Developers running Codex or similar command-line agent workflows on a desktop machine.
- Users who want to review or approve sensitive agent actions without staying at their desk.
- Teams or individuals who prefer a self-hosted bridge they can point to their own machine or LAN.
- Users who want a cross-platform client with voice input, speech playback, and notifications around coding sessions.

## Why Use It

- Cross-platform access to desktop sessions: check project state, continue a session, or start a new one from mobile or desktop clients.
- Practical approval flow: sensitive bridge requests can fall back to explicit approval instead of silently executing.
- Better day-to-day ergonomics: notifications, speech-to-text, and text-to-speech reduce the need to stay in front of the terminal.
- Bridge-based architecture: bridge URL, token, and client ID are configurable, so the client is not tied to a single hosted backend.
- Simple Android distribution: the app checks an official GitHub release manifest by default and can also use a bridge-served manifest for self-hosted updates.

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

If you are running the bridge from the bridge repository:

```bash
git clone https://github.com/omni-stream-ai/omni-code-bridge.git
cd omni-code-bridge
cp .env.example .env
cargo run
```

If your bridge `.env` sets `ECHO_MATE_BRIDGE_TOKEN` or
`ECHO_MATE_ALLOWED_CLIENT_IDS`, the client app needs matching values:

1. Open the client app and go to Settings.
2. Copy the generated `Client ID`.
3. Put it in `omni-code-bridge/.env`.
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

- `.github/workflows/release.yml`
- Workflow name: `Release Client`
- Trigger: `workflow_dispatch` or pushes that change `pubspec.yaml` or `.github/workflows/release.yml`
- Output: universal Android APK, split Android ABI APKs, Windows zip, Linux tar.gz, plus `update.json` GitHub Release assets
- Release notes: generated from Conventional Commit messages since the previous tag
- `main` can publish stable versions only
- Other branches must use prerelease versions such as `0.1.0-beta.1`

If `.github/workflows/release.yml` changes and the current app version tag does
not exist yet, the workflow will still publish that version's release.

The release APK currently falls back to the Android debug signing config when
no local signing files are present. Configure signing secrets before
distributing release builds to users.

Recommended GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded Android keystore file in a single line, without quotes or `data:...;base64,` prefixes
- `ANDROID_KEY_ALIAS`: Android signing key alias
- `ANDROID_KEY_PASSWORD`: Android signing key password
- `ANDROID_STORE_PASSWORD`: Android keystore password
- `ANDROID_GOOGLE_SERVICES_JSON_BASE64`: base64-encoded `android/app/google-services.json` in a single line, without quotes or `data:...;base64,` prefixes

## Documentation

- [中文文档](README.zh-CN.md)
- [Client app notes](CLIENT_README.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Omni Code is licensed under the [MIT License](LICENSE).
