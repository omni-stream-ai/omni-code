# Omni Code Client

Flutter 客户端仓库。现在这个仓库只包含客户端代码，桌面 bridge 已拆到独立仓库：
`https://github.com/omni-stream-ai/omni-code-bridge`。

Omni Code Client 是桌面 agent 会话的跨平台客户端。它通过 HTTP 和 SSE
连接 bridge，让你可以在移动端和桌面端管理项目、打开会话、发送消息、接收
回复通知，以及处理需要人工确认的审批请求。

## 适合谁

- 在桌面上运行 Codex 或类似命令行 agent 工作流的开发者。
- 不想一直守在电脑前，但又需要审核敏感操作的用户。
- 希望把 bridge 部署在自己电脑或局域网内、自己掌控访问方式的个人或团队。
- 需要跨平台客户端、语音输入、语音播报和通知能力来配合编码会话的用户。

## 这个客户端的优势

- 跨平台接入桌面会话：可以在移动端或桌面端查看项目状态、继续已有会话，或新开会话。
- 审批链路更实用：bridge 遇到敏感请求时，可以回退到显式人工确认，而不是直接执行。
- 日常使用更顺手：通知、语音转文字、文字转语音，减少必须守着终端的时间。
- Bridge 架构更可控：bridge URL、token、client ID 都可配置，不绑定单一托管后端。
- Android 分发简单：客户端默认检查官方 GitHub Release 更新清单，也可以改成 bridge 提供的自托管更新清单。

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

如果你使用独立 bridge 仓库：

```bash
git clone https://github.com/omni-stream-ai/omni-code-bridge.git
cd omni-code-bridge
cp .env.example .env
cargo run
```

如果 bridge `.env` 里配置了 `ECHO_MATE_BRIDGE_TOKEN` 或
`ECHO_MATE_ALLOWED_CLIENT_IDS`，客户端也要填对应值：

1. 打开客户端设置页。
2. 复制自动生成的 `Client ID`。
3. 写入 `omni-code-bridge/.env`。
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

- `.github/workflows/release.yml`
- Workflow 名称：`Release Client`
- 触发方式：手动 `workflow_dispatch`，或 `pubspec.yaml` / `.github/workflows/release.yml` 发生变更
- 产物：release Android APK 和 `update.json` GitHub Release
- Release notes：基于上一个 tag 之后的 Conventional Commit 提交消息生成
- `main` 只允许 stable 版本
- 其他分支必须使用 prerelease 版本号，例如 `0.1.0-beta.1`

如果 `.github/workflows/release.yml` 发生变更，且当前 app 版本对应的 tag
还不存在，workflow 仍会发布这个版本的 release。

当前 release APK 在没有本地签名文件时会回退到 Android debug signing
config。真正分发给用户前，需要先配置 release signing secrets。

建议配置的 GitHub Actions secrets：

- `ANDROID_KEYSTORE_BASE64`：base64 编码后的 Android keystore 文件，要求是单行内容，且不要带引号或 `data:...;base64,` 前缀
- `ANDROID_KEY_ALIAS`：Android 签名 key alias
- `ANDROID_KEY_PASSWORD`：Android 签名 key password
- `ANDROID_STORE_PASSWORD`：Android keystore password
- `ANDROID_GOOGLE_SERVICES_JSON_BASE64`：base64 编码后的 `android/app/google-services.json`，要求是单行内容，且不要带引号或 `data:...;base64,` 前缀

## 文档

- [客户端说明](CLIENT_README.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## 许可证

本项目使用 [MIT License](LICENSE)。
