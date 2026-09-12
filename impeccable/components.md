# Components

SwiftUI 配方。命名可加 `Vibex` 前缀，结构与 codeg-ios `DesignSystem/` 一一对应。

## Backdrop — `CompanionBackground`

codeg-ios `CodegBackground`。全应用根，玻璃之下。配对页、主壳、时间线共用，不要每屏自己铺一层渐变。

## GlassCard

```swift
content
  .padding(16)
  .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
  .hairlineBorder(Theme.Radius.lg)
```

用于：会话行组、空态上的说明块、时间线工具卡的外框（暗底 / 晕底上）。

## FlatCard

不透明 `Theme.bgElevated`，无 glass、无阴影。用于：浅色底上的分组列表、设置 inset 组的后备、密集 Changes 式列表。浅色模式下优先 Flat，避免霜玻璃变成浮板。

## GlassRow

padding 14 / 12，radius `md`。`isSelected` 时 `.glassEffect(.regular.tint(Theme.accent.opacity(0.22)))`，hairline 用 accent 45%。用于：可点选的 Host / 项目 / 会话行。

## PressableRowStyle

按下 scale 0.98、opacity 0.72，`Theme.Motion.press`。所有可点行共用。不要 `.plain` 到没有按下反馈。

## Buttons

| 组件 | 何时 |
| --- | --- |
| `FlatPrimaryButton` | Sheet、浅色表面的主 CTA（配对手动提交、新建会话开始）。全宽、实心 accent、14pt 竖向 padding、radius md |
| `PrimaryGlassButton` | 晕底上的主 CTA（扫描二维码）。`.glassProminent` + accent tint |
| `AccentPillButton` | 行内次要动作。`prominent` 实心；否则 accent 12% 底 + accent 字。无阴影 |

按下：primary scale 0.99 / opacity 0.85；pill 0.98 / 0.75。禁用 opacity **0.4**（必须仍像按钮，不能消失）。loading 用小 `ProgressView`，禁用点击。

系统 `.glass` 用于空态次要按钮、Retry。

## FilterChip

胶囊。未选：primary 6% + `textSecondary`。选中：accent 底 + onAccent。图标 caption2 semibold，标题 subheadline medium。padding 12 / 7。用于：近 3 / 7 / 30 天、四态筛选。

## Settings

设置用系统 **inset grouped** `List`，行结构对齐 codeg-ios `SettingsRow`：leading SF Symbol 徽章、标题、说明、chevron。不要把设置做成网页卡片堆。开关、分段控件用系统控件。

## State views

### EmptyStateView

Accent 图标砖（60pt）+ headline 标题 + subheadline 说明 + 可选 glass 按钮。最大宽 320，内边距 32。空屏是邀请，不是灰色占位符。

配对后各屏空态：

| 屏 | 标题 | 说明 | CTA |
| --- | --- | --- | --- |
| 文件夹 | Host 上还没有项目 | 在电脑上打开项目后，下拉刷新 | 重试（失败时） |
| 会话（未选项目） | 先选择文件夹 | 状态与会话都按当前项目同步 | 去选择 |
| 会话（空，online） | 还没有会话 | 用这个项目开一轮 | 新会话 |
| 会话（空，offline） | 上次同步 · 只读 | 连上 Host 后才能发消息 | — |
| 状态 | 先选择文件夹 | 状态按当前项目近几天的会话分组 | 去选择 |

### LoadingView

大号 ProgressView + subheadline 说明，accent tint。不要循环骨架屏闪烁。

### InlineErrorView

轻三角 + 「出了问题」+ 原因 + 「再试一次」。最大宽 340。

### RefreshErrorBanner

列表仍显示旧数据。玻璃 + danger 16% tint + danger 35% hairline。Retry / dismiss。刷新失败不得清空列表。

### Connection / Host banner

连接失败、需要再配对、版本不兼容：顶栏下方一条，颜色随严重度（warning / danger / info），主按钮说下一步。不是全屏错误，除非从未配对成功。

## Badges

Agent 类型用 Host 下发 SVG / 资源，圆形 28–32pt。状态点 8pt：live accent、hold warning、fail danger、idle tertiary。四态用 caption2 胶囊，不要彩虹标签。

数字角标（待办数）用系统 `.badge`。

## Timeline pieces

- **Rail：** 左侧 2pt 连续竖线，`Theme.rail`，当前行可改 semantic 色。
- **User bubble：** 右对齐玻璃气泡，body 文案。
- **Assistant：** 全宽 transcript + Agent 头像，Markdown 用 `Theme.Typography`。
- **Thinking：** 默认按设置折叠 / 隐藏，不是正文。
- **Tool card：** 按 kind 分化（read 单行 chip、edit Diff、execute 终端块、未知通用卡）。连续 ≥3 个已完成工具折成「执行了 N 个操作」。
- **Permission / question：** 卡内主次按钮直接映射 Host options。处理后折成结果行。
- **Composer：** safeAreaInset 底栏；token 弹出用 sheet。Stop 仅在途。

## Markdown / code / diff

codeg-ios `MarkdownContent` / `CodeBlockView` / `DiffView` 的字号与色：正文 body、代码 mono 13、diff mono 11.5、gutter mono 10。Diff 用 `DiffPalette`，不跟 accent。代码块 `Theme.codeSurface`。复制按钮是代码 chrome，不是主 CTA。

## Haptics

审批出现 `.warning`，成功结束 `.success`，失败 `.error`。不要给每一次 token 或滚动加触感。Reduce Motion 不取消触感。
