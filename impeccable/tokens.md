# Tokens

实现为 `DesignSystem/Theme.swift` + `Appearance.swift`，结构对齐 codeg-ios。所有颜色都是 **dynamic color**：call site 不写 `if colorScheme == .dark`。

## Backdrop

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `Theme.bg` | `#F2F4F6` | `#0A0B0D` | 窗口底，玻璃后面 |
| `Theme.bgElevated` | `#FFFFFF` | `#14161A` | 不透明分组列表、FlatCard |
| `Theme.surface` | primary 5% | primary 5% | 时间线一级容器 |
| `Theme.surfaceNested` | primary 3.5% | primary 3.5% | 组内代码 / diff 内嵌 |
| `Theme.codeSurface` | black 4.5% | black 30% | 代码块、diff 沉底 |

## Stroke

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `Theme.surfaceStroke` | black 10% | white 9% | 玻璃描边 |
| `Theme.hairline` | black 7% | white 5.5% | 更弱的分隔 |
| `Theme.rail` | black 20% | white 16% | 时间线脊，必须比 hairline 强 |

Hairline 线宽 **0.75pt**，`RoundedRectangle(..., style: .continuous)`。

## Text

| Token | Light | Dark |
| --- | --- | --- |
| `Theme.textPrimary` | white 0.11 (`#1C1C1C`) | white 0.97 (`#F7F7F7`) |
| `Theme.textSecondary` | white 0.38 | white 0.64 |
| `Theme.textTertiary` | white 0.55 | white 0.44 |

正文对比不足时向 ink 端靠，不要用「优雅灰」当 body。

## Semantic (never accent-driven)

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `Theme.danger` | `#CC2E2E` | `#F57575` | 失败、撤销、中断 |
| `Theme.warning` | `#CC8A0F` | `#F5BD5C` | 待审批、connecting、用量中段 |
| Pass / diff add | `#21854F` | `#8CE69E` | 完成、`+` 行 |
| Diff del text | `#C73333` | `#F58585` | `−` 行 |
| Diff add bg | green 16% | green 15% | |
| Diff del bg | red 12% | red 13% | |
| Cool glow | `#4C6BF2` | `#4C6BF2` | 背景第二晕 |

## Accent palettes

默认 **Neutral**。持久化用稳定 raw index（与 codeg-ios 相同，升级不改已选）。

| Palette | index | Light fill RGB | Dark fill RGB |
| --- | --- | --- | --- |
| Neutral | 8 | 0.16, 0.17, 0.20 | 0.90, 0.91, 0.93 |
| Mint | 0 | 0.06, 0.58, 0.42 | 0.40, 0.88, 0.70 |
| Blue | 1 | 0.00, 0.45, 0.92 | 0.39, 0.66, 1.00 |
| Indigo | 2 | 0.29, 0.31, 0.86 | 0.56, 0.60, 0.99 |
| Purple | 3 | 0.52, 0.26, 0.83 | 0.76, 0.55, 1.00 |
| Pink | 4 | 0.86, 0.16, 0.49 | 1.00, 0.45, 0.71 |
| Orange | 5 | 0.85, 0.42, 0.05 | 1.00, 0.62, 0.30 |
| Teal | 6 | 0.00, 0.52, 0.58 | 0.30, 0.82, 0.86 |
| Red | 7 | 0.82, 0.19, 0.20 | 1.00, 0.45, 0.45 |
| Mocha | 9 | 0.51, 0.36, 0.29 | 0.82, 0.64, 0.54 |
| Butter | 10 | 0.70, 0.53, 0.05 | 0.98, 0.84, 0.42 |
| Dusk | 11 | 0.35, 0.31, 0.54 | 0.60, 0.55, 0.80 |

`Theme.accent` 从 `AccentPaletteTrait` 解析。`Theme.onAccent` 按相对亮度：luminance > 0.6 用 `#0F0F0F`，否则白。`Theme.accentDim` = accent 16%（选中高亮、玻璃着色）。

Appearance 存 `UserDefaults`：mode（system / light / dark）+ accent index。根视图注入 `.preferredColorScheme` 与 accent environment。

## Radius

| Token | pt | 用途 |
| --- | --- | --- |
| `sm` | 10 | 小控件 |
| `md` | 14 | 行、主按钮、sheet 控件 |
| `lg` | 20 | 卡片 |
| `xl` | 26 | 大表面 |
| pill | 999 | chip / 胶囊按钮 |

一律 `style: .continuous`。卡片不要 32pt+ 圆角。

## Spacing

| Token | pt | 用途 |
| --- | --- | --- |
| `screenHMargin` | 16 | 与系统导航栏大标题对齐。不要为了迁就悬浮 Tab 改成 21 |
| `sectionSpacing` | 20 | 顶层 section 间距 |
| `screenTopInset` | 8 | 滚动顶 |
| `screenBottomInset` | 28 | 滚动底 |
| card padding | 16 | GlassCard 默认 |
| row | 14 / 12 | GlassRow 水平 / 垂直 |
| message block | 12 | 消息块之间 |
| message lineSpacing | 5 | 正文 ≈1.45× |
| list item | 5 | 列表项 |

## Type ramp (chrome)

语义样式，随 Dynamic Type：

| 角色 | 样式 |
| --- | --- |
| 屏标题 | `.title2` / compact 下 `.toolbarTitleDisplayMode(.inlineLarge)` |
| 空态标题 | `.headline` |
| 卡片标题 | `.subheadline.weight(.semibold)` |
| 正文 | `.body` + lineSpacing 5 |
| 说明 | `.subheadline` + `textSecondary` |
| meta | `.caption2.weight(.medium)` |
| micro | `.caption2.weight(.bold)` |
| 代码 | `.mono(13)` |
| diff | `.mono(11.5)` lineSpacing 2 |
| 代码 chrome | `.mono(10)` |

标题级：h1 `.title2` bold，h2 `.title3` bold，h3 `.headline` semibold，其余 `.subheadline` semibold。

## Motion

| 名 | 值 | 用途 |
| --- | --- | --- |
| `chrome` | `snappy(0.24)` | 栏、chip、toggle、insert |
| `content` | `smooth(0.26)` | loading ↔ loaded，无 overshoot |
| `expand` | `snappy(0.22)` | 卡片展开；新时间线行 120ms 长出 |
| `press` | `snappy(0.12)` | 按钮缩放 |
| `scroll` | `snappy(0.30)` | 用户触发的滚到 |

流式自动跟随 **不要** 对每个 token 做动画，用无动画 `scrollTo`。Reduce Motion：全部改为短交叉淡入或瞬切。信号条 recovering 呼吸在 Reduce Motion 下关闭。

## Backdrop glows

```text
fill Theme.bg
accent circle  0.95×width  blur 130  offset (-0.28w, -0.30h)  opacity dark 0.16 / light 0.10
cool  circle   0.95×width  blur 150  offset ( 0.36w,  0.44h)  opacity dark 0.14 / light 0.07
```

ignoresSafeArea。这是唯一允许的大面积模糊色；内容层保持不透明或系统 glass。
