# Impeccable — VibeX iOS 设计规范

本目录是 **视觉与交互实现规范**。产品行为以 [`PRD/`](../PRD/README.md) 为准；这里规定屏幕看起来像什么、用哪些 SwiftUI 材料、禁止哪些 AI 套版。

视觉语言沉淀自 [codeg-ios](https://github.com/xintaofei/codeg-ios) 的 `CodegiOS/DesignSystem/`（Liquid Glass、双晕底、动态 Accent、hairline、状态视图）。产品范围仍是 Companion，不是 Codeg 远程控制台。

根目录 [`PRODUCT.md`](../PRODUCT.md) 与 [`DESIGN.md`](../DESIGN.md) 是 impeccable skill 的入口。改视觉先改 `DESIGN.md` 的 token，再改本目录的配方。

## 何时读哪份

| 文件 | 何时打开 |
| --- | --- |
| [`tokens.md`](./tokens.md) | 写 Theme、Accent、颜色、字号、间距、圆角 |
| [`components.md`](./components.md) | 实现 GlassCard / Row / Button / Chip / Empty / Banner |
| [`screens.md`](./screens.md) | 做某一屏的布局与层级 |
| [`platform.md`](./platform.md) | 导航、iPad、动态字体、Reduce Motion、glass API |
| [`copy.md`](./copy.md) | 按钮、空态、错误、连接态文案 |

## 给实现者的硬规则

1. 复用 codeg-ios 的 **材料与 token 结构**（`Theme`、`Color(light:dark:)`、Accent trait、`.glassEffect`、`.hairlineBorder`），不要另起一套 Material 色板。
2. 默认强调色是 **Neutral**，与 codeg-ios 一致；VibeX 蓝只是色板里的一项，不是品牌底色。
3. UI 字体是 **SF Pro**。不要把 Android 的 IBM Plex Sans 搬进 iOS chrome。等宽用 SF Mono。
4. 底栏是系统 `TabView`，四处：文件夹 / 会话 / 状态 / 设置。不要自制悬浮胶囊导航去模仿 Android `LiquidNavBar`。
5. 没有 Git / MCP / 终端 / Agent 安装 / 第五个搜索 Tab。那些是 codeg-ios 的产品面，不是本应用的。

## 源文件对照（codeg-ios）

| 本规范 | 上游 |
| --- | --- |
| tokens.md | `DesignSystem/Theme.swift`, `Appearance.swift` |
| components.md | `GlassComponents.swift`, `StateViews.swift`, `FormComponents.swift`, `SettingsRow.swift`, `Badges.swift`, `CodegBackground.swift` |
| platform.md | `App/RootView.swift`, iOS 26 Liquid Glass, HIG |
| screens.md | Companion 信息架构 × codeg-ios 组件配方 |
