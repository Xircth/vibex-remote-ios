# VibeX-IOS

VibeX Host 家族的 **iOS 伴随端**：纯原生 Swift / SwiftUI 薄客户端。功能与 [Android Companion](https://github.com/Xircth/vibex-companion) 相同；视觉规范沉淀自 [codeg-ios](https://github.com/xintaofei/codeg-ios)。

离开键盘时配对桌上的 Host，查看回合、发送跟进，并在 Agent 卡住时拍板。不在手机上运行 Agent、Git 或终端。

> 本仓库目前处于需求与设计规范阶段，应用代码尚未落地。

## 文档

| 路径 | 内容 |
| --- | --- |
| [PRD/](./PRD/README.md) | 完整产品需求：范围、屏幕、协议、验收 |
| [docs/design/ios-companion.md](./docs/design/ios-companion.md) | 实现方案：Host 接入面、模块、页面、M0–M6 批次与 PR 计划 |
| [PRODUCT.md](./PRODUCT.md) | 用户、定位、性格、设计原则 |
| [DESIGN.md](./DESIGN.md) | 设计 token（机器可读）与六节视觉规范 |
| [impeccable/](./impeccable/README.md) | codeg-ios 同源的组件、屏幕、平台与文案配方 |

实现前先读 `PRD/README.md` 与 `impeccable/README.md`。协议权威在 VibeX `docs/protocol/v1/`，本仓不手写第二份。

## 不是什么

- 缩小版 VibeX 桌面
- Codeg 远程控制台（无 Git 写、MCP、终端 PTY、Agent 安装）
- 跨平台 UI 壳

## 技术栈（已锁定）

Swift 6 · SwiftUI · iOS 26 / iPadOS 26 · Liquid Glass · XcodeGen · Keychain · Remote Protocol v1
