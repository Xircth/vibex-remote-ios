# 领域用语

实现与文案共用这一套词。条目不含实现细节。避免栏里的词不得出现在产品文案、设置标题或错误说明里。

## Host 与配对

**VibeX Host**
当前拥有一个 VibeX 数据目录、并对客户端提供 Remote protocol 的运行实例（桌面应用或 `vibex-server`）。手机永远不会变成 Host。
_Avoid:_ server（单独使用）、backend、Codeg server

**Host identity**
该数据目录的稳定 id。Server Profile 按此合并，不按 URL。
_Avoid:_ baseUrl、服务器地址当作身份

**Host console**
跑 Host 的那台机器上的管理面。本应用不是本机控制台。
_Avoid:_ 设置（当意思是监听 / token / FRP）

**Reachability**
能打到同一 Host 的一条 origin。一个档案可以有多条（局域网、Tailscale、FRP、Cloudflare）。
_Avoid:_ 连接、隧道（当作档案本身）

**Pairing invitation**
本机控制台出示的短时邀请：Host 身份、设备权限预设、当前全部非 loopback Reachability，以及仅供未配对设备使用的一次性 secret。
_Avoid:_ QR（邀请是产物，二维码只是出示方式）、CODEG_TOKEN、管理员 token

**Device pairing**
用邀请里的 secret 兑成长期、可撤销的 device credential。
_Avoid:_ 登录、API key、账号

**Paired device**
本安装在某一 Host 上的身份。断开连接不解配对。
_Avoid:_ 用户账号

**Companion Device**
本应用的权限预设：会话读写、审批、纠偏、取消、只读 Artifact、离线缓存。
_Avoid:_ workstation、完整远程桌面、移动 IDE

**Server profile**
本应用对一台 Host 的本地记录：身份、名称、Reachability 列表、上次成功 origin。秘密进 Keychain。
_Avoid:_ server（表单字段）

**Forget server**
删除本地档案与凭证；Host 可达时请求撤销本设备。
_Avoid:_ 退出登录、断开（断开保留配对）

**Remote disconnect**
只结束当前网络连接，不删除档案、缓存、凭证或配对关系。

## 会话与事件

**Conversation（会话）**
与一个 Agent 的持久对话。历史由事件日志权威记录。
_Avoid:_ chat（作域名）、session（当意思是 Conversation）

**Turn（回合）**
一次「用户发起 → Agent 应答完毕」。同一会话同一时刻至多一个在途 Turn。

**Turn 终态**
恰好落在 Completed / Failed / Cancelled / Interrupted 之一。Interrupted 是宿主在回合中死亡，**禁止自动重发**。

**Event log（事件日志）**
会话的仅追加权威。手机折叠它，不拥有它。
_Avoid:_ websocket 消息（当作权威）

**Timeline row（时间线行）**
屏幕上可独立更新的最小一行，有稳定 id 与 revision。

**Durable attach（持久订阅附着）**
ready → snapshot/replay → high-water → live，以 sequence 为键。

**Queued conversation input（排队会话输入）**
已被 Host 接受、尚未绑定到 Turn 的用户意图。

**Turn steering（回合纠偏）**
向指定在途 Turn 追加的指导。不是新 Turn，也不能静默变成排队输入。

**Pending request（待办）**
等这名用户处理的权限、提问或被阻塞回合。

**Offline conversation cache（离线会话缓存）**
只读事件，到已确认 sequence 为止。离线不能排队写。

**Terminal notification summary（终态通知摘要）**
稳定 id、终态、时间、operation id。无 prompt、输出、路径。

**Workspace-less conversation（无工作区会话）**
不挂靠 Project / Workspace 的会话。若 Host 允许，创建表里单独一项。

## 连接态

| 状态 | 含义 | 写操作 |
| --- | --- | --- |
| connecting | 正在试探 origin | 禁 |
| online | 已握手且 capabilities 兼容 | 允许 |
| recovering | 重 attach，保留当前投影 | 禁 |
| offline | 打不到 Host | 禁 |
| auth_required | 凭证失效，需再配对 | 禁 |
| incompatible | 协议或最低客户端版本不匹配 | 禁 |

只有 `online` 可写。

## 用户可见词

邀请、配对、在线、待办、忘记、文件夹、会话、状态、设置。

不要对用户说：webhook、scope、sequence、bind、preset、redeem、capability（设置「能力」页除外，那里列出 Host 下发的能力名）。
