# 会话消息内容与解析

核对日期：2026-11-03。共 58 个消息内容状态，入口为 [内容浏览器](content.html)，完整设计源为 [main.op](main.op)。

## 解析分支核对

| 输入类型 | 输入示例 | 当前解析结果 | 源码 |
| --- | --- | --- | --- |
| markdown-image | `` ![检查结果](assets/review.png) `` | 正文后出现图片缩略图 | [lib/src/message_image_paths.dart:89](../lib/src/message_image_paths.dart#L89) |
| ordinary-image-link | `` [截图](assets/review.png) `` | 链接与提取后的媒体缩略图；点击均打开媒体 | [lib/src/screens/session_detail_screen.dart:5636](../lib/src/screens/session_detail_screen.dart#L5636) |
| bare-or-code-path | `` assets/review.png 或 `assets/review.png` `` | 提取媒体；保留正文原文 | [lib/src/message_image_paths.dart:97](../lib/src/message_image_paths.dart#L97) |
| data-uri | `` data:image/png;base64,... `` | 有效数据直接解码，无 Bridge 文件读取 | [lib/src/message_image_paths.dart:60](../lib/src/message_image_paths.dart#L60) |
| same-path-deduplication | `` 同一路径在链接、行内代码、正文中重复 `` | 每个路径只生成一个媒体引用 | [lib/src/message_image_paths.dart:86](../lib/src/message_image_paths.dart#L86) |
| media-types | `` PNG / JPEG / GIF / WebP / BMP / SVG / MP4 `` | 支持类型；MP4 走视频分支，SVG 走矢量分支 | [lib/src/bridge_client.dart:2182](../lib/src/bridge_client.dart#L2182) |
| query-classification-boundary | `` https://example.com/demo.mp4?token=abc `` | 路径检测可以通过，但 isVideo 对完整字符串做 endsWith(.mp4)，含 query 时不会进入视频分支；当前实现边界，设计不假装已支持 | [lib/src/message_image_paths.dart:40](../lib/src/message_image_paths.dart#L40) |
| local-file-client-access | `` [文件](lib/src/screens/home_screen.dart) `` | 仅在客户端本地项目路径存在时预览；不保证任意远程 Bridge 项目文件可打开 | [lib/src/screens/session_detail_screen.dart:5670](../lib/src/screens/session_detail_screen.dart#L5670) |
| structured-diff-vs-code | `` 结构化 turn diff / Markdown fenced diff `` | 前者可打开带原新行号的 DiffViewer；后者是普通代码高亮 | [lib/src/screens/session_detail_screen.dart:4883](../lib/src/screens/session_detail_screen.dart#L4883) |
| gfm-readonly-details | `` - [x] 已核对 / ~~旧方案~~ `` | 默认 GFM 只读任务状态与删除线，无新增编辑动作 | [lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553) |

## 能力边界

- 媒体缩略图排在正文之后，图片和 MP4 不直接在段落中重复渲染。
- 视频识别限 MP4；带 query 的 MP4 / SVG / 动图分类仍存在 endsWith 的实现边界。
- 本地文件链接预览要求客户端可访问目标文件；大于 2 MiB 或二进制内容仅提示错误。
- 普通 fenced diff 与结构化 DiffViewer 分开展示，未新增补丁应用或编辑功能。

Markdown 使用 flutter_markdown 0.7.7+1 / markdown 7.3.1 的默认 GitHub Flavored 扩展，任务列表只展示完成状态。视频初始化成功后自动循环播放，静音偏好保存到应用设置。Linux / Windows 点击视频走外部播放器；Android / iOS / macOS 可生成视频首帧缩略图。普通代码块不新增运行或复制代码块按钮。

## Markdown 正文

### 标题与段落层次

[查看状态画面](content.html?id=render-headings#render-headings) · [源码 lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553)

触发：返回 Markdown 标题与普通段落

````text
# 让信息，各就其位。

本次调整聚焦阅读体验。

## 检查结果

导航入口已完成检查。
````

### 加粗与斜体

[查看状态画面](content.html?id=render-emphasis#render-emphasis) · [源码 lib/src/screens/session_detail_screen.dart:5486](../lib/src/screens/session_detail_screen.dart#L5486)

触发：内容包含强调语法

````text
**关键结论：**功能保持完整，*阅读更轻松。*
````

### 行内代码与路径

[查看状态画面](content.html?id=render-inline-code#render-inline-code) · [源码 lib/src/screens/session_detail_screen.dart:5477](../lib/src/screens/session_detail_screen.dart#L5477)

触发：段落包含反引号代码

````text
检查 `SessionStatus.running`。
````

图中高亮块用于放大展示行内代码字色；实际在正文行内排列。

### 代码块与语法高亮

[查看状态画面](content.html?id=render-code#render-code) · [源码 lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560)

触发：返回 fenced code block

````text
```dart
final style = TextStyle(
  fontSize: 16,
  height: 1.6,
);
```
````

可用操作：选择文本。

关键词、字符串、数字、注释按现有正则高亮；没有新增执行代码或复制代码块按钮。

### 长代码横向阅读

[查看状态画面](content.html?id=render-code-wide#render-code-wide) · [源码 lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560)

触发：长行代码超出正文宽度

````text
```dart
final screen = SessionDetailScreen(session: selectedSession, client: bridgeClient);
```
````

可用操作：选择文本。

长代码内容需保持可读；不把横向代码伪装成换行后改变源文本。

### 无序列表

[查看状态画面](content.html?id=render-unordered-list#render-unordered-list) · [源码 lib/src/screens/session_detail_screen.dart:5494](../lib/src/screens/session_detail_screen.dart#L5494)

触发：内容包含无序列表

````text
## 本次检查

- 确认导航与已有路由一致
- 检查审批按钮的可用条件
- 复核长回复与媒体内容
````

### 有序步骤

[查看状态画面](content.html?id=render-ordered-list#render-ordered-list) · [源码 lib/src/screens/session_detail_screen.dart:5494](../lib/src/screens/session_detail_screen.dart#L5494)

触发：内容包含有序列表

````text
1. 进入项目并打开已有会话
2. 查看本轮返回内容
3. 完成检查后继续对话
````

### Markdown 表格

[查看状态画面](content.html?id=render-table#render-table) · [源码 lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553)

触发：MarkdownBody 以默认 Markdown 规则渲染表格

````text
| 内容类型 | 展示方式 |
| --- | --- |
| Markdown | 正文与引用 |
| 图片 / MP4 | 独立媒体缩略图 |
````

表格属于文本解析，不提供排序、筛选或单元格编辑。

### 引用块

[查看状态画面](content.html?id=render-quote#render-quote) · [源码 lib/src/screens/session_detail_screen.dart:5498](../lib/src/screens/session_detail_screen.dart#L5498)

触发：内容以 > 引用标记开头

````text
这次修改遵循原始要求：

> 不能遗漏当前功能，也不能把不可用的动作展示为可用。

因此，视觉调整只改变展示层次。
````

### 嵌套引用

[查看状态画面](content.html?id=render-quote-nested#render-quote-nested) · [源码 lib/src/screens/session_detail_screen.dart:5506](../lib/src/screens/session_detail_screen.dart#L5506)

触发：引用内容包含嵌套引用

````text
> 会话状态与消息内容，需要分别设计。
>
> > 先核对解析分支，再调整视觉呈现。
````

左侧引用线表达引用层级，不新增折叠引用交互。

### 消息内分隔线

[查看状态画面](content.html?id=render-divider#render-divider) · [源码 lib/src/screens/session_detail_screen.dart:5586](../lib/src/screens/session_detail_screen.dart#L5586)

触发：正文包含独立的 --- 分隔行

````text
## 已完成

导航与审批入口核对完成。

---

## 接下来

继续检查返回的图文与代码。
````

### 连续助手消息分隔

[查看状态画面](content.html?id=render-consecutive#render-consecutive) · [源码 lib/src/screens/session_detail_screen.dart:4937](../lib/src/screens/session_detail_screen.dart#L4937)

触发：同一轮中相邻的助手消息分别展示

````text
assistant[0]: 第一部分：已完成导航检查。
assistant[1]: 第二部分：接下来核对图片与视频。
````

### 流式内容尚未返回完整

[查看状态画面](content.html?id=render-streaming-markdown#render-streaming-markdown) · [源码 lib/src/screens/session_detail_screen.dart:5284](../lib/src/screens/session_detail_screen.dart#L5284)

触发：正文持续增长，Markdown 按当前已收到的文本渲染

````text
```dart
final style = TextStyle(
  fontSize: 16,
````

不新增语法错误警告；流式片段继续随内容更新。

### 任务列表 / 只读勾选状态

[查看状态画面](content.html?id=render-task-list#render-task-list) · [源码 lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553)

触发：默认 GitHub Flavored Markdown 解析任务列表

````text
## 检查清单

- [x] 导航与审批入口已核对
- [ ] 继续检查媒体预览
````

隐藏：交互式修改勾选状态。

当前未提供 checkboxBuilder / onTap 回调；展示原文中的完成状态，不新增待办编辑功能。

### 删除线与修订说明

[查看状态画面](content.html?id=render-strikethrough#render-strikethrough) · [源码 lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553)

触发：默认 GitHub Flavored Markdown 解析删除线

````text
~~沿用之前的紧凑排版~~

改为更舒适的正文行距。
````

删除线属于返回文本的样式，不等同于结构化 Diff，也不提供应用补丁操作。

## 链接与文件

### 外部网页链接

[查看状态画面](content.html?id=render-external-link#render-external-link) · [源码 lib/src/screens/session_detail_screen.dart:5652](../lib/src/screens/session_detail_screen.dart#L5652)

触发：链接既不是媒体引用，也不是客户端可访问的本地文件

````text
详细说明见：[查看移动端审查记录](https://example.com/review)
````

可用操作：打开系统链接。

隐藏：网页抓取摘要、网页预览卡片。

### 尖括号自动链接

[查看状态画面](content.html?id=render-autolink#render-autolink) · [源码 lib/src/screens/session_detail_screen.dart:5562](../lib/src/screens/session_detail_screen.dart#L5562)

触发：返回尖括号包裹的 URL

````text
也可以直接访问：<https://example.com/review>
````

可用操作：打开系统链接。

### 项目内相对文件链接

[查看状态画面](content.html?id=render-file-relative#render-file-relative) · [源码 lib/src/screens/session_detail_screen.dart:5642](../lib/src/screens/session_detail_screen.dart#L5642)

触发：客户端能访问项目根路径，且目标文件在本机存在

````text
[home_screen.dart](lib/src/screens/home_screen.dart)
````

可用操作：打开本地文件预览。

路径以客户端本地可访问的项目根目录解析；不是通用远程 Bridge 文件浏览器。

### file URI 与绝对路径

[查看状态画面](content.html?id=render-file-uri#render-file-uri) · [源码 lib/src/screens/session_detail_screen.dart:5659](../lib/src/screens/session_detail_screen.dart#L5659)

触发：file URI 解析为存在的客户端本地文件

````text
[查看设计说明](file:///workspace/omni-code/DESIGN.md)
````

可用操作：打开本地文件预览。

### 文本文件全文预览

[查看状态画面](content.html?id=render-file-preview#render-file-preview) · [源码 lib/src/screens/session_detail_screen.dart:5735](../lib/src/screens/session_detail_screen.dart#L5735)

触发：文件存在、大小不超过 2 MiB，且不包含 0 字节

````text
点击 [home_screen.dart](lib/src/screens/home_screen.dart)
````

可用操作：关闭、选择文本、横向与纵向滚动。

隐藏：编辑、保存文件。

### 文件过大提示

[查看状态画面](content.html?id=render-file-too-large#render-file-too-large) · [源码 lib/src/screens/session_detail_screen.dart:5678](../lib/src/screens/session_detail_screen.dart#L5678)

触发：客户端本地文件大于 2 MiB

````text
本地文件大小：2 MiB + 1 byte
````

对应当前 SnackBar；不虚构“下载”“重试预览”按钮。

### 二进制文件提示

[查看状态画面](content.html?id=render-file-binary#render-file-binary) · [源码 lib/src/screens/session_detail_screen.dart:5684](../lib/src/screens/session_detail_screen.dart#L5684)

触发：文件字节包含 0，判定为二进制

````text
[archive](assets/archive.bin) → 本地字节包含 0
````

对应当前 SnackBar；不会渲染为可编辑文本。

## 图片与媒体解析

### Markdown 图片

[查看状态画面](content.html?id=render-image-markdown#render-image-markdown) · [源码 lib/src/message_image_paths.dart:89](../lib/src/message_image_paths.dart#L89)

触发：消息包含标准 Markdown 图片标记

````text
这是本次检查的输出截图。

![检查结果](assets/review.png)
````

可用操作：打开全屏预览。

Markdown 中的图片节点隐藏，提取出的缩略图统一排在正文后。

### 指向图片的普通链接

[查看状态画面](content.html?id=render-image-link#render-image-link) · [源码 lib/src/screens/session_detail_screen.dart:5636](../lib/src/screens/session_detail_screen.dart#L5636)

触发：普通 Markdown 链接指向支持的媒体路径

````text
[打开检查截图](assets/review.png)
````

可用操作：点击链接或缩略图打开媒体。

隐藏：按普通网页链接打开。

### 裸路径提取

[查看状态画面](content.html?id=render-image-bare#render-image-bare) · [源码 lib/src/message_image_paths.dart:111](../lib/src/message_image_paths.dart#L111)

触发：正文出现支持的图片文件路径

````text
输出文件：assets/review.png
````

可用操作：打开媒体预览。

### 行内代码中的图片路径

[查看状态画面](content.html?id=render-image-inline-path#render-image-inline-path) · [源码 lib/src/message_image_paths.dart:97](../lib/src/message_image_paths.dart#L97)

触发：行内代码的值可以解析为媒体路径

````text
`assets/review.png`
````

可用操作：打开缩略图预览。

提取缩略图不意味着原行内代码自动变为可点击文件链接。

### 远程图片 URL

[查看状态画面](content.html?id=render-image-remote#render-image-remote) · [源码 lib/src/screens/session_detail_screen.dart:5895](../lib/src/screens/session_detail_screen.dart#L5895)

触发：引用为 http / https 图片地址

````text
![远程截图](https://example.com/review.png)
````

可用操作：打开媒体预览。

### Base64 内嵌图片

[查看状态画面](content.html?id=render-image-data#render-image-data) · [源码 lib/src/message_image_paths.dart:60](../lib/src/message_image_paths.dart#L60)

触发：data:image/*;base64, 后的内容可成功解码

````text
![内嵌截图](data:image/png;base64,<有效 Base64 内容>)
````

可用操作：打开媒体预览。

示例占位表示有效字节；支持 PNG、JPEG、GIF、WebP、BMP、SVG MIME。

### SVG 与透明背景

[查看状态画面](content.html?id=render-image-svg#render-image-svg) · [源码 lib/src/screens/session_detail_screen.dart:5928](../lib/src/screens/session_detail_screen.dart#L5928)

触发：媒体引用识别为 SVG

````text
![矢量图](assets/diagram.svg)
````

可用操作：打开预览、缩放、切换背景。

使用 SVG 渲染分支；透明区域在不同背景下可见。

### GIF / WebP 动图

[查看状态画面](content.html?id=render-image-animated#render-image-animated) · [源码 lib/src/message_image_paths.dart:44](../lib/src/message_image_paths.dart#L44)

触发：GIF 或 WebP 引用进入预览

````text
![过程](assets/flow.gif)
````

可用操作：打开媒体预览。

预览打开时更换会话 token，动图重新开始；没有新增手动逐帧控制。

### 重复路径只出现一次

[查看状态画面](content.html?id=render-image-deduplicate#render-image-deduplicate) · [源码 lib/src/message_image_paths.dart:86](../lib/src/message_image_paths.dart#L86)

触发：同一路径被多种语法重复引用

````text
assets/review.png

`assets/review.png`
````

可用操作：打开唯一缩略图。

隐藏：重复媒体卡片。

### 图片与视频混排

[查看状态画面](content.html?id=render-media-mixed#render-media-mixed) · [源码 lib/src/screens/session_detail_screen.dart:5536](../lib/src/screens/session_detail_screen.dart#L5536)

触发：同一消息提取到图片、MP4 与 SVG

````text
![截图](assets/review.png)
[录像](assets/demo.mp4)
![矢量图](assets/diagram.svg)
````

可用操作：打开相应媒体、在预览中切换项目。

媒体按提取顺序独立排列；图文中间不重复嵌入大图。

### 用户消息中的媒体

[查看状态画面](content.html?id=render-media-user#render-media-user) · [源码 lib/src/screens/session_detail_screen.dart:4984](../lib/src/screens/session_detail_screen.dart#L4984)

触发：用户消息同时包含正文与图片

````text
user: 检查这张截图。

![截图](assets/review.png)
````

可用操作：打开媒体预览。

用户消息右对齐；不会改用助手消息的开放式背景。

### 本地缩略图读取中

[查看状态画面](content.html?id=render-image-loading#render-image-loading) · [源码 lib/src/screens/session_detail_screen.dart:11957](../lib/src/screens/session_detail_screen.dart#L11957)

触发：Bridge 文件 Future 尚未完成

````text
assets/review.png → 文件读取中
````

占位位于媒体缩略图位置，不覆盖整条消息。

### 本地缩略图读取失败

[查看状态画面](content.html?id=render-image-hidden-error#render-image-hidden-error) · [源码 lib/src/screens/session_detail_screen.dart:6224](../lib/src/screens/session_detail_screen.dart#L6224)

触发：Bridge 读取失败或没有数据，缩略图分支返回 SizedBox.shrink

````text
assets/review.png → Bridge 读取失败
````

隐藏：失败的缩略图。

当前代码隐藏该缩略图；没有内联“重试图片”按钮。

### 缩略图解码失败

[查看状态画面](content.html?id=render-image-decode-error#render-image-decode-error) · [源码 lib/src/screens/session_detail_screen.dart:5937](../lib/src/screens/session_detail_screen.dart#L5937)

触发：图片字节不可解码，缩略图内容收起

````text
assets/review.png → 无效图像字节
````

外层媒体点击区域仍可能存在；全屏失败态单独展示。

### 全屏媒体读取中

[查看状态画面](content.html?id=render-image-preview-loading#render-image-preview-loading) · [源码 lib/src/screens/session_detail_screen.dart:6215](../lib/src/screens/session_detail_screen.dart#L6215)

触发：打开本地图片预览，文件 Future 尚未完成

````text
点击本地图片缩略图 → 读取中
````

可用操作：关闭预览、切换背景。

### 全屏图片加载失败

[查看状态画面](content.html?id=render-image-preview-failed#render-image-preview-failed) · [源码 lib/src/screens/session_detail_screen.dart:6135](../lib/src/screens/session_detail_screen.dart#L6135)

触发：全屏读取或图片解码失败

````text
点击缩略图 → 图像读取 / 解码失败
````

可用操作：关闭预览、切换背景。

隐藏：虚构的重试按钮。

### 画廊第一项

[查看状态画面](content.html?id=render-gallery-0#render-gallery-0) · [源码 lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496)

触发：同一消息有 3 个媒体引用，当前索引为 0

````text
[review.png, demo.mp4, diagram.svg] → index=0
````

可用操作：关闭、切换背景、下一项。

禁用：上一项。

### 画廊中间项

[查看状态画面](content.html?id=render-gallery-1#render-gallery-1) · [源码 lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496)

触发：同一消息有 3 个媒体引用，当前索引为 1

````text
[review.png, demo.mp4, diagram.svg] → index=1
````

可用操作：关闭、切换背景、上一项、下一项。

### 画廊最后一项

[查看状态画面](content.html?id=render-gallery-2#render-gallery-2) · [源码 lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496)

触发：同一消息有 3 个媒体引用，当前索引为 2

````text
[review.png, demo.mp4, diagram.svg] → index=2
````

可用操作：关闭、切换背景、上一项。

禁用：下一项。

## 视频播放

### MP4 缩略图回退

[查看状态画面](content.html?id=render-video-fallback#render-video-fallback) · [源码 lib/src/screens/session_detail_screen.dart:5982](../lib/src/screens/session_detail_screen.dart#L5982)

触发：缩略图未初始化、初始化失败，或平台不支持内联视频帧

````text
[演示录像](assets/demo.mp4)
````

可用操作：打开视频。

回退显示 MP4 播放图形。Android / iOS / macOS 可在初始化后显示视频首帧；Web、Linux、Windows 使用回退缩略图。

### MP4 视频首帧

[查看状态画面](content.html?id=render-video-thumbnail#render-video-thumbnail) · [源码 lib/src/screens/session_detail_screen.dart:6052](../lib/src/screens/session_detail_screen.dart#L6052)

触发：支持内联视频帧且缩略图已完成初始化

````text
导航与审批交互的演示录像：

[录像](assets/demo.mp4)
````

可用操作：打开视频预览。

### 视频播放器初始化

[查看状态画面](content.html?id=render-video-loading#render-video-loading) · [源码 lib/src/screens/session_detail_screen.dart:13392](../lib/src/screens/session_detail_screen.dart#L13392)

触发：视频文件读取或播放器初始化尚未完成

````text
assets/demo.mp4 → 初始化中
````

可用操作：关闭、切换背景。

禁用：播放 / 暂停、静音切换、进度拖动。

### 播放中 / 静音

[查看状态画面](content.html?id=render-video-playing-muted#render-video-playing-muted) · [源码 lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441)

触发：播放器已初始化，isPlaying=true，muted=true

````text
assets/demo.mp4 → 播放，静音
````

可用操作：播放 / 暂停、切换静音、拖动进度、关闭、切换背景。

初始化成功后自动循环播放；静音选择会保存到应用设置。

### 播放中 / 有声

[查看状态画面](content.html?id=render-video-playing-sound#render-video-playing-sound) · [源码 lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441)

触发：播放器已初始化，isPlaying=true，muted=false

````text
assets/demo.mp4 → 播放，有声
````

可用操作：播放 / 暂停、切换静音、拖动进度、关闭、切换背景。

初始化成功后自动循环播放；静音选择会保存到应用设置。

### 已暂停 / 静音

[查看状态画面](content.html?id=render-video-paused-muted#render-video-paused-muted) · [源码 lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441)

触发：播放器已初始化，isPlaying=false，muted=true

````text
assets/demo.mp4 → 暂停，静音
````

可用操作：播放 / 暂停、切换静音、拖动进度、关闭、切换背景。

初始化成功后自动循环播放；静音选择会保存到应用设置。

### 已暂停 / 有声

[查看状态画面](content.html?id=render-video-paused-sound#render-video-paused-sound) · [源码 lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441)

触发：播放器已初始化，isPlaying=false，muted=false

````text
assets/demo.mp4 → 暂停，有声
````

可用操作：播放 / 暂停、切换静音、拖动进度、关闭、切换背景。

初始化成功后自动循环播放；静音选择会保存到应用设置。

### 竖屏视频比例

[查看状态画面](content.html?id=render-video-portrait#render-video-portrait) · [源码 lib/src/screens/session_detail_screen.dart:13420](../lib/src/screens/session_detail_screen.dart#L13420)

触发：视频已初始化，采用播放器返回的原始宽高比

````text
assets/portrait.mp4 → aspectRatio=9/16
````

可用操作：播放 / 暂停、静音切换、拖动进度、缩放、关闭。

### 视频播放失败

[查看状态画面](content.html?id=render-video-error#render-video-error) · [源码 lib/src/screens/session_detail_screen.dart:13387](../lib/src/screens/session_detail_screen.dart#L13387)

触发：视频读取或初始化失败

````text
assets/demo.mp4 → 初始化失败
````

可用操作：关闭、切换背景。

隐藏：重试按钮、不可用播放控件。

当前视频分支复用 imagePreviewLoadFailed 文案；未把它设计成不存在的专用错误和重试流程。

### 桌面端交给外部播放器

[查看状态画面](content.html?id=render-video-external#render-video-external) · [源码 lib/src/screens/session_detail_screen.dart:6084](../lib/src/screens/session_detail_screen.dart#L6084)

触发：Linux / Windows 点击视频引用，进入外部打开流程

````text
[演示录像](assets/demo.mp4)
````

可用操作：通过系统播放器打开。

隐藏：应用内视频播放器。

此项标明平台分支，不作为手机新增功能。

## Diff 与文件变更

### 单文件变更摘要

[查看状态画面](content.html?id=render-diff-single#render-diff-single) · [源码 lib/src/screens/session_detail_screen.dart:5040](../lib/src/screens/session_detail_screen.dart#L5040)

触发：当前轮次只有一个文件变更

````text
turn.diff: files=[home_screen.dart], added=24, removed=8
````

可用操作：打开全屏 Diff。

隐藏：多文件展开开关。

### 多文件变更 / 收起

[查看状态画面](content.html?id=render-diff-collapsed#render-diff-collapsed) · [源码 lib/src/screens/session_detail_screen.dart:5043](../lib/src/screens/session_detail_screen.dart#L5043)

触发：当前轮次有多个变更，expanded=false

````text
turn.diffs=[home_screen.dart, session_detail_screen.dart] → collapsed
````

可用操作：打开首个 Diff、展开其他文件。

隐藏：其余文件摘要。

### 多文件变更 / 展开

[查看状态画面](content.html?id=render-diff-expanded#render-diff-expanded) · [源码 lib/src/screens/session_detail_screen.dart:5082](../lib/src/screens/session_detail_screen.dart#L5082)

触发：当前轮次有多个变更，expanded=true

````text
turn.diffs=[home_screen.dart, session_detail_screen.dart] → expanded
````

可用操作：查看各文件 Diff、收起其他文件。

### 全屏 Diff / 原行与新行

[查看状态画面](content.html?id=render-diff-detail#render-diff-detail) · [源码 lib/src/screens/session_detail_screen.dart:12597](../lib/src/screens/session_detail_screen.dart#L12597)

触发：点击文件变更摘要，打开全屏 Diff

````text
@@ -168,3 +168,4 @@
 style: textTheme.bodyLarge,
-fontSize: 11,
+fontSize: 16,
+height: 1.6,
````

可用操作：关闭、选择文本、横向与纵向滚动。

旧行号、新行号、增删前缀与底色同时区分；不新增应用补丁或代码编辑按钮。

### Diff 无 patch / 使用 summary

[查看状态画面](content.html?id=render-diff-summary-only#render-diff-summary-only) · [源码 lib/src/screens/session_detail_screen.dart:5189](../lib/src/screens/session_detail_screen.dart#L5189)

触发：patch 为空，优先显示 summary，否则显示 No diff details

````text
patch=""; summary="调整了首页导航与消息排版。"
````

可用操作：关闭。

### 超长 Diff / 虚拟列表

[查看状态画面](content.html?id=render-diff-long#render-diff-long) · [源码 lib/src/screens/session_detail_screen.dart:12557](../lib/src/screens/session_detail_screen.dart#L12557)

触发：解析后行数大于 1000，使用固定行高的虚拟列表

````text
patch → 1001 条 diff 行
````

可用操作：关闭、横向与纵向滚动。

虚拟列表使用 RichText，未承诺与短 Diff 的 SelectableText.rich 相同的跨行选择行为。

### 消息内 fenced diff 文本

[查看状态画面](content.html?id=render-diff-fenced-text#render-diff-fenced-text) · [源码 lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560)

触发：助手在普通 Markdown 回复中返回 diff 代码块

````text
```diff
- fontSize: 11,
+ fontSize: 16,
```
````

可用操作：选择文本。

普通 fenced diff 走通用语法高亮；只有结构化变更条目进入专门的 DiffViewer，不伪造 patch 应用交互。
