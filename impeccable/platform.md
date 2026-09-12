# iOS platform

HIG 管结构、导航、交互。品牌只走 tint、材料、内容。codeg-ios 已证明的 iOS 26 规则全部沿用；产品导航按 Companion 四栏裁剪。

## 系统版本

- 部署：iOS 26 / iPadOS 26（`.glassEffect`、`.buttonStyle(.glassProminent)`、`tabViewBottomAccessory` 若使用）。
- Xcode 26 SDK。工程由 XcodeGen 生成。
- Swift 6 严格并发。`@Observable` 模型；禁止 `ObservableObject` 三件套。

## 导航

| 尺寸 | 壳 |
| --- | --- |
| Compact | `TabView` 四栏 + 每栏 `NavigationStack` |
| Regular | `NavigationSplitView`：来源（四栏）\| 列表 \| 时间线 |

- Tab 是 **section**，不是 action。四处：文件夹、会话、状态、设置。
- 时间线是会话栈上的 detail，不是第五 Tab。push 后 `.toolbar(.hidden, for: .tabBar)`。
- 左边缘返回必须可用。不要用全宽横向手势抢系统 pop。
- 顶层用 inline-large 标题（与 trailing 按钮同行）。详情 inline。
- Sheet 做自包含任务（新会话、会话信息、扫描）。Cancel / 关闭明确。有数据损失才拦截 dismiss。
- 深链（若做）：`vibex://conversation/<id>` 切到会话 Tab 并 push 详情，返回栈正确。

不要：自制全局导航、网页式 hamburger、把 Android 底栏胶囊画在 `safeAreaInset` 里冒充 Tab。

## Liquid Glass

- 用系统 `.glassEffect` / `.glass` / `.glassProminent`。禁止手写 `ultraThinMaterial` 一套去「近似玻璃」。
- 玻璃只做 **chrome 与浮层**（行、卡、compose、banner）。内容（Markdown、diff、代码）不透明。
- 禁止玻璃叠玻璃。浅色密集列表改 FlatCard。
- Reduce Transparency：去掉 blur，改 `bgElevated` + hairline。

## 字体与触控

- chrome：语义 `Font` 样式。禁止 8.5–12pt 写死 UI 字。
- 代码 / origin / id：SF Mono，允许 Dynamic Type 缩放。
- 11pt 地板；Body 默认 17pt。
- 触控 ≥ 44×44 pt。相邻目标之间留空。
- SF Symbols，weight 与字号对齐。不要混 Lucide / Material Icons。

## 颜色与外观

- 动态 `Color(light:dark:)`。Accent 走 UIKit trait bridge（codeg-ios `AccentPaletteTrait`）。
- 跟随系统是默认外观。设置可锁 light / dark。
- 一个 tint 驱动交互。装饰不是它的工作。
- 对比：正文 ≥ 4.5:1；大字 ≥ 3:1。状态不只靠颜色。

## 控件

用系统：Switch、分段、Stepper、系统选择器、确认对话框、action sheet、context menu、swipe actions、`PhotosPicker`（若附图）。为「味道」重做这些是最常见的 native slop。

设置页 = inset grouped `List`。

## 运动

- Push 滑入、sheet 升起、dismiss 走原路返回。
- 只用 `Theme.Motion` 五条。无 bounce、无弹性、无全页粒子。
- Reduce Motion：交叉淡入或瞬切。信号条呼吸关闭。流式滚动本就无动画。

## iPad

- 分栏保持时间线在 detail；换会话不拆掉栏。
- 键盘：`⌘N` 新会话、`⌘F` 当前列表搜索、`⌘.` 停止在途、`⌘1–4` 切栏。
- pointer hover 行高亮用系统 list hover，不要网页 `:hover` 阴影。
- Settings 在 regular 宽度必须可达（sidebar 底 gear 或独立栏），这是 codeg-ios 修过的坑。

## 权限与生命

- 相机：仅扫码。用途说明写扫 VibeX 邀请。
- 本地网络：仅 LAN origin。
- 后台：持续监控是用户开关；P1 不接 APNs。Scene background 可关 socket、保留投影；foreground 用 `after_sequence` 续传。
- Keychain 需要签名后的 `application-identifier`。模拟器可降级；真机不可。

## 质量

- 未知 JSON / 未知 event kind 不得让解码失败（开放枚举）。
- 字符串进 String Catalog（en + zh-Hans）。
- Preview 覆盖 light / dark / 一档大字号。
