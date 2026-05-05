# Omni Code Client

Flutter 客户端仓库。现在这个仓库只包含客户端代码，桌面 bridge 已拆到同级目录
`../omni-code-desktop-bridge`。

## 环境要求

- `Flutter` 3.5+
- Android Studio 或 Xcode

## 启动客户端

```bash
flutter pub get
flutter run
```

如果 bridge 不在默认地址，可以通过 Dart define 指定：

```bash
flutter run --dart-define=ECHO_MATE_BRIDGE_URL=http://127.0.0.1:8787
```

## 连接 Bridge

客户端通过 HTTP 和 SSE 访问桌面 bridge，地址可以在设置页里填写，也可以通过
`ECHO_MATE_BRIDGE_URL` 传入。

如果你使用同级目录里的 bridge 仓库：

```bash
cd ../omni-code-desktop-bridge
cp .env.example .env
cargo run
```

如果 bridge `.env` 里配置了 `ECHO_MATE_BRIDGE_TOKEN` 或
`ECHO_MATE_ALLOWED_CLIENT_IDS`，客户端也要填对应值：

1. 打开客户端设置页。
2. 复制自动生成的 `Client ID`。
3. 写入 `../omni-code-desktop-bridge/.env`。
4. 把 `.env` 里的 `ECHO_MATE_BRIDGE_TOKEN` 填到客户端的 `Bridge Token`。
5. 重启 bridge，然后在客户端保存设置。

## 目录

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

## 开发检查

```bash
flutter pub get
flutter analyze
```

## GitHub Actions 打包

当前仓库包含一个客户端发布 workflow：

- `.github/workflows/build.yml`
- Workflow 名称：`Release Client`
- 触发方式：手动 `workflow_dispatch`，或 `pubspec.yaml` 发生变更
- 产物：Android APK GitHub Release
- `main` 只允许 stable 版本
- 其他分支必须使用 prerelease 版本号，例如 `0.1.0-beta.1`

当前 release APK 在没有本地签名文件时会回退到 Android debug signing
config。真正分发给用户前，需要先配置 release signing secrets。

建议配置的 GitHub Actions secrets：

- `ANDROID_KEYSTORE_BASE64`：base64 编码后的 Android keystore 文件
- `ANDROID_KEY_ALIAS`：Android 签名 key alias
- `ANDROID_KEY_PASSWORD`：Android 签名 key password
- `ANDROID_STORE_PASSWORD`：Android keystore password
- `ANDROID_GOOGLE_SERVICES_JSON_BASE64`：base64 编码后的 `android/app/google-services.json`

## 文档

- [客户端说明](CLIENT_README.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## 许可证

本项目使用 [MIT License](LICENSE)。
