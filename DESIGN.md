# 当前应用界面记录

2026-11-03：设计工作的目标改为如实体现当前应用，暂停新视觉设计。移动端和桌面端均以当前 Flutter 源码为依据，不以此前规范草案修改应用。

- [当前应用预览](designs/index.html)：直接渲染当前 Flutter 页面，使用示例数据。
- [现状记录与生成说明](designs/current/README.md)：覆盖范围、生成方式与限制。
- 颜色：`lib/src/theme/app_colors.dart`；主题与字体：`lib/src/theme/app_theme.dart`。
- 间距与圆角：`lib/src/theme/app_spacing.dart`；桌面布局：`lib/src/responsive/app_responsive_layout.dart` 及各页面的实际调用。

当前实现即记录依据，包括页面级覆盖和既有不一致；记录不自动修正它们。截图中的示例数据、测试环境字体和平台能力不等于真机数据与全部运行状态。

此前 `designs/main.op`、`designs/tokens.json`、新设计规范及旧预览属于已暂停的改版提案，不能当作当前应用或现行规范。它们保留用于历史参考；入口为 [历史提案](designs/redesign-proposal.html)。原有 coverage / states / content 资料仅作源码索引，画稿引用不是现状视觉验收证据。
