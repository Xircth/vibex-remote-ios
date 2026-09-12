---
name: VibeX iOS Companion
description: Night-glass instrument for a VibeX Host. Liquid Glass surfaces over a dual-glow backdrop, one selectable accent, SF Pro chrome.
register: product
platform:
  os: [iOS, iPadOS]
  minimumDeployment: "26.0"
  appearance: [light, dark]
colors:
  bg-light: "#F2F4F6"
  bg-dark: "#0A0B0D"
  bg-elevated-light: "#FFFFFF"
  bg-elevated-dark: "#14161A"
  text-primary-light: "#1C1C1C"
  text-primary-dark: "#F7F7F7"
  text-secondary-light: "#616161"
  text-secondary-dark: "#A3A3A3"
  text-tertiary-light: "#8C8C8C"
  text-tertiary-dark: "#707070"
  surface: "#0000000D"
  surface-nested: "#00000009"
  hairline-light: "#00000012"
  hairline-dark: "#FFFFFF0E"
  stroke-light: "#0000001A"
  stroke-dark: "#FFFFFF17"
  rail-light: "#00000033"
  rail-dark: "#FFFFFF29"
  code-surface-light: "#0000000B"
  code-surface-dark: "#0000004D"
  danger-light: "#CC2E2E"
  danger-dark: "#F57575"
  warning-light: "#CC8A0F"
  warning-dark: "#F5BD5C"
  pass-light: "#21854F"
  pass-dark: "#8CE69E"
  accent-neutral-light: "#292B33"
  accent-neutral-dark: "#E6E8ED"
  accent-blue-light: "#0073EB"
  accent-blue-dark: "#63A8FF"
  cool-glow: "#4C6BF2"
  on-accent-on-light: "#FFFFFF"
  on-accent-on-dark: "#0F0F0F"
typography:
  display:
    fontFamily: SF Pro
    textStyle: title2
    fontWeight: 700
  headline:
    fontFamily: SF Pro
    textStyle: headline
    fontWeight: 600
  title:
    fontFamily: SF Pro
    textStyle: subheadline
    fontWeight: 600
  body:
    fontFamily: SF Pro
    textStyle: body
    fontSize: 17pt
    fontWeight: 400
  label:
    fontFamily: SF Pro
    textStyle: caption2
    fontWeight: 500
  mono:
    fontFamily: SF Mono
    fontSize: 13pt
    fontWeight: 400
rounded:
  sm: 10pt
  md: 14pt
  lg: 20pt
  xl: 26pt
  pill: 999pt
  curve: continuous
spacing:
  screen-h: 16pt
  section: 20pt
  screen-top: 8pt
  screen-bottom: 28pt
  card-padding: 16pt
  row-x: 14pt
  row-y: 12pt
  block: 12pt
  message-line: 5pt
components:
  button-primary:
    backgroundColor: "{colors.accent-neutral-light}"
    textColor: "{colors.on-accent-on-light}"
    rounded: "{rounded.md}"
    padding: "14pt 0"
  button-glass-prominent:
    backgroundColor: "{colors.accent-neutral-light}"
    textColor: "{colors.on-accent-on-light}"
    rounded: "{rounded.md}"
  button-pill:
    backgroundColor: "{colors.accent-neutral-light}"
    textColor: "{colors.on-accent-on-light}"
    rounded: "{rounded.pill}"
    padding: "8pt 16pt"
  card-glass:
    backgroundColor: "{colors.bg-elevated-dark}"
    rounded: "{rounded.lg}"
    padding: "{spacing.card-padding}"
  row-glass:
    backgroundColor: "{colors.bg-elevated-dark}"
    rounded: "{rounded.md}"
    padding: "12pt 14pt"
  chip-filter:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-secondary-light}"
    rounded: "{rounded.pill}"
    padding: "7pt 12pt"
  input-compose:
    backgroundColor: "{colors.bg-elevated-light}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.lg}"
    padding: "10pt 14pt"
---

# Design System: VibeX iOS Companion

Visual authority is this file plus [`impeccable/`](impeccable/README.md). Tokens here are normative. Screen recipes, SwiftUI mapping, and motion live under `impeccable/`. Source of the visual language: [codeg-ios](https://github.com/xintaofei/codeg-ios) `DesignSystem/`.

## 1. Overview

**Creative North Star: "Night Glass Console"**

The UI is a developer remote control sitting on a near-black (or cool paper) field with two soft, blurred glows — one following the user accent, one a cool blue. Liquid Glass cards and rows float on that field. Chrome is restrained; the transcript, tool cards, and connection state do the talking.

This is codeg-ios craft applied to a thinner product. Same materials, radii, type ramp, dual-glow backdrop, hairline definition, and selectable accent. Different information architecture: four companion tabs, pairing instead of URL + token, no Git/MCP/terminal console.

The system rejects SaaS-cream dashboards, neon cyberpunk skins, Android Plex-as-UI-face, and decorative glass stacked on glass.

**Key Characteristics:**

- Dual-glow backdrop (`CodegBackground` recipe); content surfaces opaque or system glass, never a page-wide gradient fill.
- One accent at a time, Neutral by default; warning / danger / diff never follow it.
- SF Pro for chrome and reading; SF Mono for code, paths, origin, ids, counters.
- Continuous-corner glass cards and rows with a 0.75pt hairline.
- Named motion only: chrome / content / expand / press / scroll. No bounce.

## 2. Colors

Restrained strategy: tinted neutrals plus one accent used on ≤10% of any screen.

### Primary

- **Accent (Neutral default)** (`#292B33` light / `#E6E8ED` dark): interactive fill, selected chip, live rail, prominent button, focus. Palettes (Mint, Blue, Indigo, Purple, Pink, Orange, Teal, Red, Mocha, Butter, Dusk) are user-selectable and resolve through one `Theme.accent` token. See [`impeccable/tokens.md`](impeccable/tokens.md).

### Secondary

- **Warning amber** (`#CC8A0F` / `#F5BD5C`): pending approval, connecting, mid-zone gauges. Not accent-driven.
- **Danger** (`#CC2E2E` / `#F57575`): failure, revoke, interrupted, destructive.
- **Pass green** (`#21854F` / `#8CE69E`): completed marks and diff additions. Not accent-driven.

### Neutral

- **Backdrop** (`#F2F4F6` / `#0A0B0D`): window field behind glass.
- **Elevated** (`#FFFFFF` / `#14161A`): flat lists, settings groups, sheets that must not frost.
- **Text primary / secondary / tertiary**: the only type colors. No raw gray-on-color.
- **Hairline / stroke / rail**: structural lines; rail is stronger than hairline so the timeline spine reads as a machine, not a divider.

**The One Voice Rule.** Accent appears on primary actions, selection, and live state. It is never a card background, never a full-screen wash, never a left stripe thicker than 1pt.

**The Semantic Exception Rule.** Warning, danger, and diff stay amber / red / green even when the accent is Neutral or Blue.

## 3. Typography

**Display / Body / Label Font:** SF Pro (system).
**Mono Font:** SF Mono / `.system(design: .monospaced)`.

San Francisco carries the UI so Dynamic Type, optical sizing, and tracking stay native. A brand face is not introduced.

### Hierarchy

- **Display** (title2, bold): screen titles in compact inline-large mode.
- **Headline** (headline, semibold): empty-state titles, section headers.
- **Title** (subheadline, semibold): card titles, settings row titles, tool-card names.
- **Body** (body 17pt @ default, line spacing 5pt ≈ 1.45×): assistant and user message prose. Block spacing 12pt.
- **Label** (caption2, medium): footer meta, relative time, chips. Micro labels are caption2 bold.
- **Mono 13 / 11.5 / 10**: reading code, dense diff, code chrome.

**The System Style Rule.** Chrome uses semantic text styles (`body`, `headline`, `caption2`), not hardcoded 8.5–12pt. Numeric chrome adds `.monospacedDigit()`. Code may use explicit mono sizes.

**The Weight Ladder Rule.** h1/h2 bold; h3/h4 semibold. Do not force every heading to `.bold`.

## 4. Elevation

Depth comes from **material and tone**, not drop shadows. Glass sits on the dual-glow field; flat grouped lists use `bgElevated` with no frost and no floating shadow.

Hairline (0.75pt, continuous rounded rect) gives glass a physical edge. Selected rows tint the glass with accent at 0.22 and stroke the hairline with accent at 0.45.

**The No Floating Plate Rule.** A frosted card on a light near-white field reads as a shadowed plate. Settings lists, folder git-style tables, and dense rows use `FlatCard` (opaque elevated fill), not glass.

**The Backdrop Rule.** The two glows exist so translucency has something to read against. Do not put glass on glass. Do not skip the backdrop.

## 5. Components

Recipes and SwiftUI names: [`impeccable/components.md`](impeccable/components.md).

### Buttons

- **Shape:** continuous rounded rect at 14pt (`md`), or capsule for compact pills.
- **Primary flat:** solid accent fill, on-accent label, 14pt vertical padding, full width in sheets. Press scale 0.99, disabled opacity 0.4. Use on light sheets where prominent glass washes out.
- **Primary glass:** `.buttonStyle(.glassProminent)` + `tint(Theme.accent)` on dark/glow fields (onboarding scan CTA).
- **Press:** snappy 0.12s. Feedback on touch-down.

### Chips

Capsule. Unselected: primary 6% fill, secondary text. Selected: accent fill, on-accent text. Horizontal 12 / vertical 7.

### Cards / Containers

- Glass card: 20pt continuous, 16pt padding, `.glassEffect(.regular)` + hairline.
- Glass row: 14pt continuous, 14/12 padding, selected accent tint.
- Timeline surfaces: `Theme.surface` then `Theme.surfaceNested` — two steps, not five greys.

### Inputs / Fields

Compose bar is a glass or elevated capsule above the keyboard, safe-area inset. Focus uses accent tint, not a custom glow ring. Origin and pairing fields are system text fields with accent tint.

### Navigation

System `TabView` (four destinations) and `NavigationStack`. Compact: inline-large title on the same row as trailing buttons. Regular: standard large title. Timeline hides the tab bar. Signal of connection is a chip in the header, not a toast.

### Signature: Timeline rail

A vertical spine in `Theme.rail`. Per-row color: live = accent, hold = warning, quiet = tertiary, stop = danger. New rows grow from the rail in 120ms (`expand`) unless Reduce Motion.

### Signature: Dual-glow backdrop

Near-black or cool paper fill. Accent circle ~0.95× width, blur 130, offset upper-left. Cool blue `#4C6BF2` circle, blur 150, offset lower-right. Opacity 0.16/0.14 dark, 0.10/0.07 light.

## 6. Do's and Don'ts

### Do:

- **Do** use system tab bar, navigation stack, sheets, context menus, swipe actions, and SF Symbols.
- **Do** put connection state in the header chip on every paired screen.
- **Do** keep four tabs: Folders, Sessions, Status, Settings.
- **Do** resolve light/dark through dynamic colors (`Color(light:dark:)`) so call sites never branch on scheme.
- **Do** resolve accent through one environment trait, the same way codeg-ios resolves `\.codegAccent`.
- **Do** honor Reduce Motion and Reduce Transparency.
- **Do** keep pairing copy as short instructions, not a feature list.

### Don't:

- **Don't** ship Codeg console surfaces (Git write, MCP, terminal PTY, agent install, chat channels, Search tab).
- **Don't** port Android IBM Plex as the UI face, or rebuild a custom LiquidNavBar that fights `TabView`.
- **Don't** use Inter, Roboto, or a display serif for chrome.
- **Don't** use decorative gradients, gradient text, neon purple-blue glow, or glassmorphism as default card styling.
- **Don't** put a colored left stripe thicker than 1pt on cards or rows — the rail is the spine, not a stripe accent.
- **Don't** nest cards in cards, or glass on glass.
- **Don't** hard-code point sizes for UI chrome, or freeze type against Dynamic Type.
- **Don't** use toast as the primary connection state.
- **Don't** invent a fifth visual style for Settings vs Sessions vs Timeline.
