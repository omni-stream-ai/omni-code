# 当前应用界面基准

此目录直接使用当前 Flutter 页面生成预览，替代此前改版提案作为现状参考。没有修改应用视觉或布局。

## 覆盖范围

工作台、会话、项目详情、设置；移动尺寸 390 × 844、桌面尺寸 1440 × 900；每页提供深浅主题，共 16 张。入口为 [应用预览](../index.html)。

预览使用当前页面、AppTheme 和响应式布局，数据来自测试夹具，并非真实用户数据。语言为英语；测试环境显式加载 Roboto 和 MaterialIcons，按钮空字体使用 Roboto 替代测试框架默认方块字体。系统字体、平台能力、窗口装饰及真机渲染可能有差异。设置页的模型加载提示来自未接入真实服务的测试环境。

当前范围仅覆盖上述核心页面的初始可见区域，尚未覆盖全部路由、弹层和业务状态。历史 main.op、tokens.json、coverage 和 states 的画稿均不能作为现状视觉证据。本次未制作新的可编辑矢量稿，也未声称全量现状还原已经完成。

## 重新生成

在项目根目录、可用的 Flutter 开发环境中运行：

```sh
flutter test --no-pub --update-goldens --dart-define=UPDATE_CURRENT_APP_PREVIEWS=true test/generate_readme_previews_test.dart
```

生成器复用应用页面与示例接口，需随当前接口同步维护。预览色值摘录见 source-colors.json；派生颜色、别名及页面覆盖仍以源码为准。source-manifest.json 记录本轮截图对应的关键源码哈希，源码变化后应重新导出。
