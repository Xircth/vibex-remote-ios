# 协议与事件

权威：VibeX `docs/protocol/v1/`（OpenAPI + JSON Schema）。生成的 Swift 模型是编译夹具，不是第二份权威。本仓不手改 schema。

Companion 不解析 ACP，不维护第二份会话权威。它消费 Host 已经写入事件日志、并经投影折叠过的事实。

## 1. 传输

```text
Agent ACP / 用户 / Workflow / IM
        │
        ▼
ConversationControl（唯一写入口）
        │  append ConversationEvent
        ▼
Event log（单调 sequence）
        │  fold
        ▼
Remote Protocol
        HTTP commands
        WS attach → snapshot / replay / live RemoteEvent
```

### 1.1 握手

1. `GET /api/v1/capabilities`（Bearer device credential）
2. 比较 `protocol_version` 主版本、`minimum_client_version`、`host_id`
3. 拉 Reachability 权威名单
4. 一条 WebSocket：`GET /api/v1/ws`，`Sec-WebSocket-Protocol: vibex.token.<base64url>`
5. 凭证永不进 URL、日志、崩溃报告

`GET /health` 只用于 origin 探活，不代替 capabilities。

### 1.2 一条 Socket，多个订阅

客户端发送：`attach { subscription_id, resource, conversation_id, after_sequence }`、`detach`、`ping`。

服务端按序：`ready` → 可选 `snapshot` → replay `event…`（sequence > after_sequence）→ `live`（high_water_mark）→ 实时 `event…`。

规则：

- 重复 sequence 丢弃。
- `after_sequence = 0` 且无本地缓存：允许带 snapshot。
- 重连：使用本地已确认的最大 sequence。
- 设备被撤：已有 WS 必须立刻断开，后续 HTTP 401 → `auth_required`。
- 也可 `attach workflow_run`（只读）；P1 产品面可以不展示运行编辑器，但协议不得因此失败。
- 未知 `RemoteEvent.kind` 必须保留 JSON，不得让缓存或 attach 失败。

### 1.3 HTTP 写命令

所有写带客户端生成的 `operation_id`。重试同一 id 不得产生第二条输入。

| 用户动作 | Command | 随后可见（典型） |
| --- | --- | --- |
| 目录 | `conversation_catalog` | 只读 |
| 近 N 天会话 | `conversation_list_recent` | 只读 |
| 斜杠命令 | `conversation_slash_commands` | 只读 |
| 工作区文件 | `conversation_workspace_entries` | 只读 |
| 新建工作区 | `conversation_workspace_create` | 目录更新 |
| 新建会话 | `conversation_create` | `conversation_created` |
| 发送 / 排队 / 改未认领 | `conversation_input_submit` | `conversation_input` |
| 取消排队 | `conversation_input_cancel` | `conversation_input` Cancelled |
| 纠偏 | `conversation_steer` + `expected_turn_id` | `conversation_steering`；目标已变则 conflict |
| 取消在途 | `conversation_cancel_turn` | `turn_cancelled` |
| 批 / 拒权限 | `conversation_respond_permission` | `permission_responded` |
| 回答提问 | `conversation_respond_question` | `question_responded` |
| 置顶 / 归档 / 删除 / 重命名 / 四态 | `conversation_set_pinned` 等 | 列表更新 |
| 会话 mode / config | `conversation_set_session_mode` / `_config_option` | 对应 updated / stale |
| Artifact 列表 | `artifact_list` | 只读 |
| 离线事件 | `GET …/conversations/{id}/offline?after_sequence=` | `read_only: true` |
| 终态摘要 | `GET …/conversations/{id}/notification-summary` | 无 secret |
| 撤销本设备 | `DELETE /api/v1/auth/devices/{device_id}` | 忘记流程 |

Host 用 scope fail-closed。UI 隐藏不是安全边界。

## 2. Companion Device scopes

配对只接受该集合。邀请带额外 scope 则拒绝兑换。

```
conversation.read
conversation.write
conversation.attach
conversation.permission
conversation.question
conversation.cancel
conversation.steer
artifact.read
workflow.read
automation.read
delegation.read
notification.summary
offline.read
```

没有：Git 写、终端、插件写、Workflow / Automation 写、`application.call`、Host 管理。只读目录必须挂在 `conversation.read` 下，而不是开放 `application.call`。

## 3. 配对邀请

```text
vibex-pairing:1
  host_id
  preset            companion
  expires_at
  pairing_id
  pairing_token     仅未配对设备兑换
  reachability[]    origin + kind（lan | frp | tailscale | cloudflare）
```

- 长期 `vbx_device_`、管理员 token 不得出现。
- `127.0.0.1` 永不进入邀请。
- 未配对设备：`POST /api/v1/auth/pairings/redeem`，一次兑换。
- 已持有该 `host_id` 的凭证：合并 Reachability，不兑换、不换设备。secret 过期后仍可从新出示的邀请收下 origin。

## 4. 事件折叠

客户端把事件折成时间线行。一行一个稳定 `row_id` + `revision`。文本 delta 合并进同一消息行。

| `kind` | 呈现 |
| --- | --- |
| `conversation_created` | 不成行；更新标题 |
| `conversation_input` | 队列条：已提交 / 已更新 / 已认领 / 已取消 |
| `conversation_steering` | 纠偏条，挂在目标 Turn |
| `conversation_relation_created` | 子会话卡片，可点开（不合并历史） |
| `agent_binding_started` | 「正在启动 Agent」 |
| `agent_binding_ready` | 去掉启动态；能力快照显隐 steer |
| `agent_binding_recovered` | 简短恢复提示 |
| `agent_binding_recovery_failed` / `agent_binding_load_failed` | 错误条；后者可有重绑入口 |
| `agent_connection_status_changed` | 顶栏，不是时间线行 |
| `user_turn_created` | 用户气泡 |
| `user_turn_queued` | 「已排队」 |
| `user_turn_started` | 去掉排队，进入在途 |
| `assistant_text_delta` | 合并进助手消息（按 `message_id`） |
| `assistant_reasoning_delta` | 思考块，默认按消息流设置折叠 / 隐藏 |
| `assistant_content_appended` | 按块类型；未知块保留 |
| `plan_updated` | 计划列表；status/priority 用协议字段，禁止一律写成 pending |
| `tool_call_upsert` | 工具卡片，按 tool id upsert |
| `permission_requested` | 待办 + 时间线卡，必须能批 / 拒 |
| `permission_responded` | 卡变为已处理；任意设备互斥消解 |
| `question_requested` / `question_responded` | 待办 + 结构化选项 |
| `feedback_requested` / `feedback_submitted` | 若 Agent 发出则进待办 |
| `terminal_updated` | 只读摘要，不提供 PTY |
| `usage_updated` | 仅当字段存在时显示；禁止填 0 |
| `file_change_summary_updated` | 「N 个文件」只读 |
| `artifact_revision_recorded` | 只读产物条目 |
| `turn_blocked` | 待办角标 |
| `turn_completed` / `turn_failed` / `turn_cancelled` | 结束条 |
| `turn_interrupted` | 已中断；禁止自动重发 |
| `session_mode_updated` / `session_config_options_updated` | Composer 有则显示 |
| `session_config_stale` | 通知：默认未生效 |
| `prompt_capabilities_updated` | 决定能否 steer / 附图 |
| `available_commands_updated` | 命令候选；无则空 |
| `agent_session_info_updated` | 只回填 Agent 给出的 title 等 |
| `delegation_started` / `delegation_completed` | 子会话卡 + 结果摘要 |
| `raw_diagnostic_recorded` | 默认隐藏 |

未知 `kind`：占位行「Host 更新了此会话」。

Snapshot 最低字段：`conversation_id`、`title`、`through_sequence`、当前 Turn、timeline rows、未认领 inputs、未处理 permission / question、agent 连接状态、capabilities 快照。用 snapshot 填行，再用 replay/live 按 sequence 打补丁。本地行 `revision` 落后才应用。

## 5. 会话目录

在 `conversation.read` 下必须能拿到：

- 已添加且就绪的 Agent（id、显示名、是否 ready / usable、lifecycle、authentication、icon、session config / modes）
- 用户可见的 Project / Workspace（id、名称、路径、所属、分支）
- 某项目近 N 天会话
- 无工作区会话是否可用

这是会话读模型，不是运维面。

## 6. 多设备

- 同一 Conversation 同一时刻至多一个在途 Turn。
- 两台设备同时批同一权限：先到的生效，后到的 conflict / already resolved。
- Steering 必须带 `expected_turn_id`。
