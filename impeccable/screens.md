# Screen recipes

布局骨架。文案见 [`copy.md`](./copy.md)，行为见 [`PRD/03-functional.md`](../PRD/03-functional.md)。

所有已配对屏：顶栏有 **连接 chip**（仅状态词，如「在线」）。点按弹出当前 Host 地址（origin），不显示 host ID。背景是 `CompanionBackground`。水平边距 16pt。

## 开屏

0.8s。`Theme.bg` + 标记。无文案、无卖点。Reduce Motion 或系统关闭动画：瞬切。

## 未配对 / 手动配对

单列，垂直居中偏上。

```
[标记 72]
连接到你的 VibeX          // title2
打开电脑桌面端 → 设置 → 远程连接，点击「生成连接码」。
[扫描连接二维码]          // PrimaryGlassButton
手动输入连接码            // text button, accent
```

手动：两个系统字段（地址、连接码）+ `FlatPrimaryButton`「配对」+ 返回扫描。错误一句 `danger`，留在本页。

扫描：系统相机全屏，框内提示「将连接二维码放入框内」。取消回未配对。

## 文件夹

```
Header: 文件夹                    [连接 chip]
SearchField  搜索项目或路径
List of GlassRow
  [色点] 名称
         path 末段 · mono caption
```

已选行 `isSelected`。空 / 错用 EmptyState / InlineError。下拉刷新。

## 会话

```
Header: 当前项目名（可切换）       [连接 chip]
Search + 近 3/7/30 FilterChip
可选：N 条待你处理               // warning 底，点进第一条
分组列表（置顶 / 今天 / 昨天 / 本周 / 更早）
  Agent 头像 + 状态点
  会话名
  工作区 · Agent · 四态
  右侧相对时间
FAB 新会话                      // 仅 online；tab bar 之上
```

行用 GlassRow。滑动与 context menu 用系统 API。FAB 用系统或 accent 圆钮，不要第二个自定义 Tab。

## 新会话 sheet

`.medium` → `.large` detent。项目横滑卡片、Agent 横排图标、工作区选择、可选 Prompt、主按钮「开始」。失败不关 sheet。

## 时间线

全屏 NavigationStack。Tab bar 隐藏。边缘返回保留。

```
[返回]  居中截断标题           [Agent 头像] [三横杠]
Lazy transcript
  过程折叠「已折叠 N 条过程消息」
  用户气泡靠右 / 助手 Markdown / 工具组 / 等待转圈
悬浮球（默认可拖，贴边）：消息列表 / 任务列表
底部中央 ↓ 圆钮（未贴底时）

safeAreaInset:
  可选：待审批卡片
  可选：队列 / 纠偏 pill
  ComposeBar（占位「发送消息，输入 / @ # &」，摘要 chip，用量环，发送/停止）
```

用户在底部附近才跟随滚动。三横杠打开 SessionInfoSheet。摘要 chip 打开 Agent 选项。左缘返回手势保留；悬浮球默认贴右侧。

## 状态

```
Header: 状态                     [连接 chip]
四个可折叠看板（色胶囊标题 + 圆形计数）
  待开始 / 进行中 / 待检查 / 已完成
  会话卡：Agent 头像、会话名、工作区、相对时间、状态
```

未选项目走空态。卡片 tap 进时间线。

## 设置

Inset grouped list。第一组第一行是 **连接**。

顺序：连接 / 外观 / 消息流控制 / Host / 能力 / 关于。

外观页：系统分段（浅色 / 深色 / 跟随）+ accent 色点网格（codeg-ios Appearance 预览：每个 swatch 独立 dynamic color，不依赖当前 trait）。消息流用 Choice 行，不要自造复杂控件。

忘记 Host：系统确认对话框，主按钮 destructive。
