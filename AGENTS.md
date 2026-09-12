# Agents

Read `CONTEXT.md` before changing product behavior. Read `PRD/` before adding a screen. Read `docs/design/ios-companion.md` before adding a module or protocol call. Read `impeccable/` before changing visuals.

This repo is the **Companion Device** iOS app only.

- Do not add Host console features (listen, FRP, tokens, MCP, Git write, terminal PTY, plugin write).
- Do not hand-edit `docs/protocol/v1/generated`.
- Event fold must follow `docs/design/ios-companion.md` §5. Unknown kinds stay as 「Host 更新了此会话」.
- UI follows `impeccable/`. Bottom destinations stay at four: 文件夹 / 会话 / 状态 / 设置. System `TabView`, not a custom dock.
- Credentials go in Keychain. No secrets in logs, URLs, or backups.

## Agent skills

### Issue tracker

Issues live as markdown under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: root `CONTEXT.md` plus `docs/adr/` (when present). See `docs/agents/domain.md`.
