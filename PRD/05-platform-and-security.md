# 平台、安全与工程约束

## 1. 技术栈

| 项 | 选择 |
| --- | --- |
| 语言 | Swift（Swift 6 严格并发） |
| UI | SwiftUI，iOS 26 SDK，Liquid Glass |
| 最低系统 | iOS 26（codeg-ios 同源设计语言依赖系统 glass API） |
| 设备 | iPhone + iPad（universal） |
| 工程 | XcodeGen `project.yml` 生成工程，不手改 `pbxproj` 作为权威 |
| 状态 | `@Observable`，不用 `ObservableObject` / `@Published` / `@StateObject` |
| 网络 | URLSession + URLSessionWebSocketTask；HTTP Bearer，WS 走 `Sec-WebSocket-Protocol` |
| 持久化 | Server Profile 元数据进 Application Support；凭证进 Keychain；离线事件缓存进 Application Support，可清除 |
| 协议模型 | 由 VibeX `docs/protocol/v1` 生成的 Swift 类型，本仓不平行手写权威 |
| 图标 | SF Symbols + Host 下发的 Agent SVG / 资源 |

明确不做：Kotlin Multiplatform UI、React Native、Capacitor、把 Android Compose 屏幕移植过来。与 Android 共享的是 Remote Protocol、fixture 与验收语义。

架构对照 codeg-ios 的模块切分，按 Companion 产品面裁剪：

```text
App/            入口、根导航、选择态
Models/         协议与投影模型（生成 + 折叠）
Networking/     HTTP、WebSocket attach、错误信封
Persistence/    Server Profile、Keychain、离线缓存
DesignSystem/   见 impeccable/：Theme、Glass、状态视图
Features/       Onboarding、Folders、Sessions、Timeline、Status、Settings
```

iPhone：`TabView` 四栏 + `NavigationStack`。时间线 push 后隐藏 Tab。
iPad：`NavigationSplitView`。sidebar 为四栏来源，content 为列表，detail 为时间线。不要做成 codeg-ios 的「服务器列表三栏」。

## 2. 安全

- Device credential 只进 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）。模拟器可降级到不持久的开发存储，真机必须 Keychain。
- 备份排除凭证。`NSURLIsExcludedFromBackupKey` 用于缓存目录。
- 日志、崩溃报告、URL、通知、屏幕录制文案不得出现 pairing secret、device token、管理员 token、prompt 全文、文件路径。
- ATS：仅因局域网 HTTP 声明本地网络例外；公网优先 HTTPS。出示邀请前的明文风险由 Host 控制台确认，客户端不另开例外。
- 相机权限：`NSCameraUsageDescription` 只解释扫 VibeX 邀请。拒绝则手动输入。
- 本地网络权限：若探测 LAN origin，按系统要求声明。
- 没有账号系统，没有第三方登录，没有分析 SDK，没有把项目上传到 VibeX 运营的云。

## 3. 离线

- 缓存只含已确认 sequence 的事件与列表摘要。
- `read_only` 必须为 true。离线禁止排队写、禁止「稍后发送」。
- 打开会话时先渲染缓存，标只读；恢复 online 后再 attach 续传。
- 「清除缓存」只删事件缓存，不删档案与 Keychain。

## 4. 无障碍与平台习惯

- 触控目标 ≥ 44×44 pt。
- Dynamic Type：UI 用系统文字样式；代码 / diff / origin 用等宽，允许缩放。
- VoiceOver：信号条、待办、权限按钮、工具卡必须有标签。
- Reduce Motion：信号条呼吸与新行长出改为瞬切 / 交叉淡入。
- Reduce Transparency：glass 表面改为不透明 `bgElevated` + hairline。
- 颜色不单独表达状态（轨颜色 + 文案 / 图标）。
- 左边缘返回手势不得被自定义手势吃掉。
- 设置页用 inset grouped 列表，不要自制网页式卡片堆。

## 5. 国际化

跟随系统语言。首发 String Catalog：`en`、`zh-Hans`。专有名不译。

## 6. 分发

测试阶段侧载 / TestFlight。Bundle ID 建议 `dev.vibex.companion`。版本与 Host 家族 semver 对齐；capabilities 再做运行时协商。

## 7. 测试

行为必须能用与 Android `companion-core` 相同的 golden fixture 验证：

- 未知 event kind 不崩、缓存仍可读
- sequence 去重，断线后续上不双份气泡
- `turn_interrupted` 没有自动重发
- 权限在桌面与手机互斥消解
- 同一 `operation_id` 幂等
- 邀请解析拒绝 loopback 与长期口令

协议模型编译冒烟：VibeX 的 `pnpm run remote-protocol-schema:check` 已含 Swift。本仓单测覆盖折叠、配对解析、origin 排序。
