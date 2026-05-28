<p align="center">
  <img src="assets/app-icon.svg" width="128" alt="Omni Code">
</p>

<h1 align="center">Omni Code Client</h1>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.5+-02569B?logo=flutter" alt="Flutter"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-lightgrey" alt="Platforms">
  <a href="https://github.com/omni-stream-ai/omni-code/releases"><img src="https://img.shields.io/github/v/release/omni-stream-ai/omni-code" alt="Release"></a>
</p>

<p align="center">
  <a href="README.zh-CN.md">中文文档</a>
</p>

---

Omni Code 是一个跨平台 Flutter 客户端，支持桌面端和移动端，核心目标是让你通过语音完成产品设计、开发、测试等全部工作流——不需要一直守在屏幕前。

它连接 [omni-code-bridge](https://github.com/omni-stream-ai/omni-code-bridge)，让桌面 agent 的能力延伸到多端和语音交互中。

## Preview

![Omni Code](preview/omni-code-showcase.png)

## Roadmap (V1)

1. **完善基本交互** — 优化会话、审批、通知等核心流程的体验
2. **跨项目跨会话语音交互** — 用语音在多个项目和会话间无缝切换
3. **任务编排** — 支持多步骤任务的编排与自动化执行

## Install

**Homebrew (macOS):**

```bash
brew tap omni-stream-ai/homebrew-omni-code
brew install --cask omni-code
```

**Arch Linux (AUR):**

```bash
yay -S omni-code-bin
```

## Development

```bash
flutter pub get
flutter run
```

## License

[MIT](LICENSE)
