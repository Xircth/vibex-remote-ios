# VibeX-IOS

VibeX Host 家族的 **iOS 伴随端**：纯原生 Swift / SwiftUI 薄客户端。功能对齐 [Android Companion](https://github.com/Xircth/vibex-companion)；仓库发布为 [vibex-remote-ios](https://github.com/Xircth/vibex-remote-ios)。产品范围仍是 Companion Device。

离开键盘时配对桌上的 Host，查看回合、发送跟进，并在 Agent 卡住时拍板。不在手机上运行 Agent、Git 或终端。

## 结构

| 路径 | 内容 |
| --- | --- |
| `Sources/CompanionCore` | 可测深模块：配对、origin、scopes、EventFold、HostClient、Runtime |
| `VibeXCompanion/` | SwiftUI 应用：四栏、时间线、设置、Keychain、相机扫码 |
| `Checks/` | 无 XCTest 的 CompanionCore 金样（`swift run CompanionCoreCheck`） |
| `PRD/` | 产品需求 |
| `impeccable/` | 视觉与文案配方 |
| `docs/design/ios-companion.md` | 实现方案 |

显示名 **VibeX**，Bundle ID `dev.vibex.companion`。

## 下载与安装

安装包在 [GitHub Releases](https://github.com/Xircth/vibex-remote-ios/releases/latest)，产物是 `.ipa`。这是测试阶段的侧载包，不经过 App Store。

iOS 不允许像 Android APK 那样直接点开安装。用电脑把 IPA 签到你的设备上：

| 方式 | 说明 |
| --- | --- |
| [AltStore](https://altstore.io) / [SideStore](https://sidestore.io) | 用你自己的 Apple ID 重签，免费账号约 7 天需刷新 |
| [Sideloadly](https://sideloadly.io) | 在 Mac / Windows 上把 IPA 装进已连接的 iPhone |

包名 `dev.vibex.companion`，需要 iOS 18 或更高。还要有一台正在运行、协议为 Remote v1 的 VibeX Host；手机访问的是局域网或隧道地址，不要填 Host 本机的 `127.0.0.1`。

## 构建

CompanionCore（本机可跑）：

```sh
swift run CompanionCoreCheck
```

iOS 应用（需要 Xcode + XcodeGen）：

```sh
brew install xcodegen
xcodegen generate
open VibeXCompanion.xcodeproj
```

工程由 `project.yml` 生成，不要手改 pbxproj。模拟器可运行；真机侧载需要开发者证书。Keychain 在模拟器上可降级，真机必须写入钥匙串。

## 不是什么

- 缩小版 VibeX 桌面
- Codeg 远程控制台（无 Git 写、MCP、终端 PTY、Agent 安装、第五个搜索 Tab）
- 跨平台 UI 壳
