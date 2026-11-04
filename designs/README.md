# 当前应用界面

设计工作已切换为记录现有应用，暂停视觉改版。先看 [当前应用界面图册](current/README.md) 与 [现状说明](current/README.md)。

下文是此前改版工作的历史记录，链接中的画稿、变量、状态预览和规范不代表当前应用，也不再作为实施依据。

---

# Omni Code 移动端改版

[设计体系 v1.0](design-system.md) 是后续页面设计与验收依据，覆盖基础样式、组件、交互和深浅主题。桌面布局、密度与键盘交互见 [桌面端规范](desktop-design-system.md)。现有画稿与预览仍需按规范验证，不能视为全部符合规范。

2026-11-03 视觉精修：石墨底色、暖白表面与青柠主操作；首页增加柔和渐变信息区与独立统计块，统一选中导航、卡片、标题和会话输入区。主界面路由、状态文案与功能节点 ID 保持一致。详见 [视觉调整说明](visual-refinement.md)。

视觉参考为 [mobile-refresh-concept.html](mobile-refresh-concept.html?view=all)，功能依据为当前工作区中的 Flutter 代码。设计通过 OpenPencil `op` CLI 创建、细化和导出。

- [首页改版前后对照](previews/visual-refinement-comparison.png)：深浅主题并排比较。
- [打开历史设计总览](redesign-proposal.html?view=all)：主界面深浅对照、流程分组、单屏与整板预览。
- [会话样张（深浅对照）](redesign-proposal.html?group=26&view=all)：图文回复、变更与验证、图片与视频，共 6 张完整会话画面。
- [独立状态浏览器](states.html)：247 个独立状态，按分类搜索；[完整状态表](states.md)。
- [Logo 与 SVG 图标库](icons.html)：项目真实 Logo、65 个自绘 SVG 及尺寸规范。
- [可编辑设计源](main.op)：29 个画板、296 个页面 / 弹层 / 组件预览。
- [功能核对表](coverage.md)：413 个功能组的源码依据、条件与设计节点；原始数据见 `coverage.json`。
- [消息内容解析](content.html)：Markdown、链接、图片、视频与 Diff 的输入、展示和交互；[解析核对表](content.md)。
- [颜色变量](tokens.json) 与 [校验结果](validation.json)。

## 设计与状态范围

主界面为 390 × 844，包含工作台、会话、项目列表、项目内会话和设置，提供深浅两套稿。滚动详情按内容展开；独立组件状态按内容高度展示，画外注释不属于应用界面。

- 会话主状态：13 个独立状态。
- 执行阶段：20 个独立状态。
- 审批请求：10 个独立状态。
- 消息与输入：20 个独立状态。
- 消息与内容：15 个独立状态。
- 语音通话：14 个独立状态。
- 连接、首页与项目：17 个独立状态。
- 创建、设置与模型供应商：24 个独立状态。
- 语音服务与 Pi 插件：26 个独立状态。
- Pi 扩展交互：5 个独立状态。
- 验收运行：11 个独立状态。
- 验收计划、桌面与证据：14 个独立状态。
- Markdown 正文：15 个独立状态。
- 链接与文件：7 个独立状态。
- 图片与媒体解析：19 个独立状态。
- 视频播放：10 个独立状态。
- Diff 与文件变更：7 个独立状态。

会话的 6 个 SessionStatus、8 个 ExecutionPhase、本地消息 queued / pending / submitted / failed、录音三种松手动作、通话提示、图片背景、输入设置子面板，以及验收 11 个阶段均已对应独立状态稿。枚举和节点对应关系见 `states.json` 与 `validation.json`。

## 关键功能约束

- 底部导航复用工作台、项目、设置路由；抽屉保留最近项目、最近会话及其上下文操作。首页统计只对应当前已加载数据。
- 空草稿不显示发送；queued 可编辑和撤回，failed 提供重试，pending / submitted 分别等待处理或确认。
- 审批按钮按 resolvable、命令和请求能力显示；提交中、等待执行端确认、失败、已解决分别展示。
- 当前项目页的 _openAcceptance 使用 automatic=false，为手动远程桌面；会话与全局设置保留自动验收。
- 供应商格式为 OpenAI Compatible、Anthropic、Codex。Agent 安装、兼容供应商、模型和推理强度受当前能力限制。
- 语音保留实时 ASR、批量 ASR、TTS 三条独立路由，以及凭据、动态参数、测试、本地模型、说话人与通话设置。Pi 列表、安装、参数与扩展交互分开展示。
- Web 禁用 App 更新检查；Android 下载并安装更新，其他原生平台打开发布页。桌面宽屏侧栏折叠未新增为手机功能。
- 系统 / 浅色 / 深色主题模式保持现有语义。新配色是设计变量，应用中未新增自定义主题色选择器。

## Logo、字体与 SVG

Logo 源：`/data/code/code/omni-code/assets/app-icon.svg`。本目录 `assets/logo.svg` 与源文件逐字节一致；SHA-256：`9a5cbd55eea344fc11c73ffe38b834ffb4ffddc97a3b18e0a9e18e45af609795`。原始 SVG 以图像节点嵌入 .op，保留渐变与比例。

`assets/icons/*.svg` 是 65 个自绘图标；`assets/icons.json` 记录 canonical 名、语义别名、原始路径及光学归一化数据。.op 中功能图标为可编辑 path，统一使用 20 × 20 容器，源 SVG 为 24 × 24 / 2px，操作热区 44 × 44，图文间距 8px，颜色跟随主题。实施时应将这套资产同步到 Flutter。

`assets/fonts/` 中的 Roboto 与项目使用的 Flutter SDK 同源，许可见 `assets/Roboto_LICENSE.txt`。中文预览使用 Noto Sans CJK SC；项目未固定中文回退字体，跨设备显示需真机比对。

`assets/samples/` 提供返回媒体的示例内容；SVG 保留可维护源，PNG 用于保持预览中文字的显示一致。

代码预览使用系统等宽字体，设计渲染为 DejaVu Sans Mono；正文继续使用 Roboto / Noto Sans CJK SC。新增 quote-bg、link、code、code-keyword、code-string 语义颜色，分别配有深浅变量。

## 使用 OpenPencil CLI 维护

从项目根目录运行：

```sh
op start --file designs/main.op
op get --depth 2
op vars
```

修改前通过 `op get` / `op read-nodes` 查询节点。`coverage.json` 和 `states.json` 保存相关 nodeIds、源码行号与哈希。

```sh
op update <node-id> '{"content":"更新后的文案"}'
op design:refine --root-id <board-id>
op save designs/main.op
op export --item <node-id> --format png --output designs/previews/<name>.png
```

配色由 `tokens.json` 维护。并排稿实际引用 `dark-*` / `light-*`，如 dark-accent、light-accent、dark-bg、light-bg；同时保留 mode 主题轴和通用颜色变量。修改配色时更新通用定义及对应主题定义，然后导入并重新导出受影响的预览。

```sh
op vars:set @designs/tokens.json
```

变量不会自动修改 Flutter。功能或源码变化后，应复核对应条件和状态稿，并同步更新预览、清单与源码哈希。设计核对不替代应用运行测试，也不穷举所有状态交叉组合。
