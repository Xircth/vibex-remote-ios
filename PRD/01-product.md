# 产品概述

## 背景

VibeX 是本地优先的 IADE（Integrated Agent Development Environment）。Agent、Worktree、终端、插件、Git、Automation 都跑在用户控制的 **VibeX Host** 上（桌面应用或 `vibex-server`）。同一数据目录同一时刻只能有一个 Host。

客户端分三等，配对时选 **Device permission preset**：

| 表面 | 是什么 |
| --- | --- |
| 本机控制台 | 跑 Host 的那台机器上的运维面：监听、Reachability、邀请、撤设备、token |
| Workstation Device | 其它电脑上的 VibeX.app：近乎全接管工作，不含 Host 运维 |
| Companion Device | 手机薄客户端：会话读写、审批、纠偏、只读 Artifact、离线缓存 |

VibeX-IOS 是 Companion Device 的 iOS 实现。Android 已交付；iOS 复用同一 Remote Protocol v1，独立选择原生技术（ADR-0041：不共享 UI 运行时）。

它不是缩小版桌面，不是在手机上跑 ACP，也不是 Codeg 那种带 Git / MCP / 终端写的远程管理台。Codeg-ios 只提供 **前端设计规范与样式**，不提供产品范围。

## 用户

**主用户：** 已经在电脑上跑 VibeX Host 的开发者。离开键盘时仍要看回合、发跟进、批准权限、回答提问。

他们技术、任务导向、经常同时盯几条会话。界面必须在高信息密度下保持冷静，状态一眼可读。

没有 Host 的人不是用户。本应用不提供云账号、不托管项目、不在设备上安装 Agent。

## 产品目的

把「人在场」的那一段从键盘挪到手机：观察、输入、拍板。执行面始终是 Host。

成功意味着：

1. 扫一次本机控制台出示的配对邀请就能连上，不必手贴管理员 token。
2. 选一个项目后能看到近几天的会话，打开时间线能跟上在途回合。
3. 权限与提问能在手机上批掉；桌面同一请求消失。
4. Host 不可达时仍能读已缓存的时间线；写操作明确不可用，且不排队。
5. 同一 Host 身份只有一份档案；换网只换 Reachability，不重新配对。

## 定位

**VibeX 的 iOS 伴随端：配对桌上的 Host，看回合、发跟进、处理卡住的审批。**

每一屏都强化这句话。不要做成移动 IDE、通用聊天 App，或第二份 Host 控制台。

## 品牌性格

冷静、可检查、精确。

语气直接，给开发者看，适合长时间使用。抛光服务于扫描与状态清晰，不服务于宣传。

## 能力边界

可以：

- 扫描或粘贴 `vibex-pairing:` 邀请，或手填 origin + 一次性配对码
- 同一 Host 身份再次扫描时只合并 Reachability（邀请里不会出现 `127.0.0.1`）
- 列出 Host 历史项目，选定后同步该项目近 N 天会话（默认 3，可 7 / 30）
- 列出、搜索、置顶、重命名、归档、删除会话；用 Host 目录创建新会话
- 折叠 Host 事件日志：用户消息、助手输出、思考、工具、计划、权限、提问、子会话
- 发送、排队、纠偏、取消回合
- 批准或拒绝权限，回答提问
- 使用 Host 已提供的 `/` Skill、`@` 文件、`#` 指令、`&` Agent 提及、`$` token
- 只读查看文件变更摘要、Artifact、终端摘要
- 按桌面 Kanban 四态看项目会话
- 断网后阅读已缓存会话
- 用户显式打开持续监控时，把终态摘要变成本地通知（P1 不接 APNs）

不可以：

- 粘贴管理员 token 或长期 `vbx_device_` 代替配对
- 写 Git、开终端 PTY、装插件、改 Host 监听 / FRP / token
- 写 Workflow / Automation
- 在手机上运行 Agent、Worktree 或产物工具
- 离线排队写操作
- 把缺失用量填成零，或自动重发中断 Turn

## 版本与兼容

- 桌面与 Server 必须同产品版本家族。
- Companion 可以落后 Host 一个次版本；连接时协商 capabilities。
- 缺 scope 或 capability 时 fail-closed：隐藏并禁用，不假装成功。
- 协议主版本不兼容时进入 `incompatible`，禁止写。

## 测试阶段

应用处于测试阶段。从 GitHub Releases 分发，不上架 App Store 直到产品宣布。用户须保持 Host 与应用处于匹配的产品版本，并在 Host 上检查 Agent 产生的变更后再提交或合并。
