# VibeX iOS Companion — 需求文档

本目录是 **VibeX-IOS** 的产品需求权威。实现、审查、验收都以这里为准。

VibeX-IOS 是 [VibeX](https://github.com/Xircth/VibeX) Host 家族中的 **Mobile companion**：纯原生 Swift / SwiftUI 薄客户端。功能与 [vibex-remote-android](https://github.com/Xircth/vibex-companion) **完全相同**；视觉与交互规范见仓库根目录 [`PRODUCT.md`](../PRODUCT.md)、[`DESIGN.md`](../DESIGN.md) 与 [`impeccable/`](../impeccable/README.md)（沉淀自 [codeg-ios](https://github.com/xintaofei/codeg-ios)）。

## 读法

| 文档 | 回答什么 |
| --- | --- |
| [01-product.md](./01-product.md) | 背景、用户、一句话、成功标准、非目标 |
| [02-glossary.md](./02-glossary.md) | 领域用语；禁止发明同义词 |
| [03-functional.md](./03-functional.md) | 屏幕、流程、状态、文案 |
| [04-protocol-and-events.md](./04-protocol-and-events.md) | Remote Protocol v1、配对、事件折叠、写命令 |
| [05-platform-and-security.md](./05-platform-and-security.md) | iOS 技术栈、凭据、权限、离线、通知 |
| [06-acceptance.md](./06-acceptance.md) | 可检查的验收条 |

冲突时的优先级：

1. 本目录的产品行为
2. VibeX `docs/protocol/v1/` 与 ADR-0054 / 0059 / 0044 / 0001 / 0058
3. Android 仓的实现（行为对照，不是 UI 对照）
4. [`impeccable/`](../impeccable/README.md) 的视觉实现

协议与 Host 身份以 VibeX 仓库为准。本仓不手写第二份协议权威。

## 一句话

离开键盘的 Host 主人，用这台 iPhone / iPad **看清 Agent 在本机干什么，并在它卡住时拍板**。
