# Product

## Register

product

## Platform

ios

## Users

Developers who already run a VibeX Host on a machine they control. They leave the keyboard and still need to watch turns, send follow-ups, and approve what is waiting. They are technical, task-focused, and often tracking several conversations at once. The phone is a companion, not their IDE.

People without a Host are not users. The app does not create accounts, host projects, or run agents on-device.

## Product Purpose

VibeX-IOS is the iOS Mobile companion in the VibeX Host family. It is a thin native client. Agents, worktrees, terminals, plugins, and Git stay on the Host. The phone reads conversations, sends input, steers an in-flight turn, and answers permission or question prompts. Without a reachable Host it only reads the offline cache.

Success is a closed loop: scan a pairing invitation, pick a project, watch the turn, approve what is blocked, and still read the timeline when the network drops.

## Positioning

Pair to the Host on your desk, watch turns, send follow-ups, and approve what is waiting.

## Brand Personality

Calm, inspectable, and precise.

The app should feel like a night-shift instrument behind Liquid Glass — a serious engineering remote, not a promotional AI dashboard. Polish serves scanability, state clarity, and confidence. Tone is direct enough for developers and restrained enough for long sessions.

## Anti-references

- Generic AI SaaS dashboards with oversized cards, decorative gradients, nested glass panels, and vague productivity claims.
- Codeg-ios product scope: Git write, MCP, terminal PTY, agent install, chat channels, a fifth Search tab. Visual language is the reference; the console is not.
- A shrunk VibeX desktop, or ACP running on the phone.
- Material / Android screens ported pixel-for-pixel (IBM Plex as the UI face, custom four-icon dock copied as a fake tab bar).
- Dark-mode-by-default tool aesthetics that rely on neon, purple-blue glow, or dramatic contrast instead of usable structure.
- Web-shaped navigation: custom back gestures, hover-only affordances, card stacks instead of grouped settings.

## Design Principles

1. Make state visible before making it beautiful. Connection, turn, queue, and pending approval must be readable at a glance.
2. Keep the tool dense but calm. Density is acceptable; every surface needs rhythm, grouping, and one component vocabulary.
3. Use the platform. Tab bar, navigation stack, sheets, lists, SF Symbols, Dynamic Type, system materials. Brand expresses through tint, type, and the dual-glow backdrop — not by reinventing chrome.
4. Treat color as information. Accent marks selection, primary action, focus, and live state. Warning, danger, and diff stay semantic and never follow the accent.
5. Prefer inspectable structure over theatrical UI. Transcript, tool cards, and diffs should feel durable and work-focused.

## Accessibility & Inclusion

Target WCAG AA contrast for text, controls, and state indicators. Do not use color alone for connection, turn, or approval state. Dynamic Type is required. Reduce Motion replaces springs and breathing with cross-fades. Reduce Transparency replaces glass with opaque surfaces. VoiceOver must speak the signal bar, pending approvals, and permission actions. Minimum hit target is 44×44 pt.
