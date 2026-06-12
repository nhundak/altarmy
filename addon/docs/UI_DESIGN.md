# AltArmy UI Design System

Visual language for the AltArmy TBC addon. Inspired by [AHPriceGraph](https://www.curseforge.com/wow/addons/ahpricegraph); the Graphs tab established the canonical AltArmy palette (slightly brighter bronze borders and 0.95-alpha panels).

## Goals

- **Consistent dark panels** with subtle textured borders across every surface (main window, tabs, settings panels, popovers, Interface Options).
- **Warm bronze / gold accents** for borders, titles, selection, and separators.
- **Single source of truth** in `AltArmy_TBC/UI/Theme.lua` — no copy-pasted backdrop blocks in tab files.
- **TBC compatibility** — guard `SetBackdrop`; use `BackdropTemplateMixin` fallback when needed.

## Palette (`Theme.COLORS`)

| Role | RGBA | Usage |
|------|------|-------|
| `windowBg` | 0.08, 0.08, 0.10, **0.55** | Main window shell (semi-transparent; gaps between section panels show through) |
| `windowBorder` | 0.45, 0.38, 0.22, 0.75 | Main window outer border |
| `sectionBg` | 0.10, 0.10, 0.12, **0.95** | Side panels, settings (opaque cards on the shell) |
| `graphBg` | 0.08, 0.08, 0.10, **0.95** | Graph plot area |
| `dialogBg` | 0.08, 0.08, 0.10, 0.97 | Modal popovers (opaque) |
| `panelBg` | 0.08, 0.08, 0.10, 0.95 | Legacy alias; prefer tier-specific roles |
| `inputBg` | 0.06, 0.06, 0.08, 1.00 | Edit boxes |
| `panelBorder` | 0.45, 0.38, 0.22, 0.90 | Window / primary panel edges |
| `sectionBorder` | 0.45, 0.38, 0.22, 0.90 | Inner section edges |
| `inputBorder` | 0.22, 0.22, 0.26, 0.80 | Input field borders |
| `sepLine` | 0.55, 0.46, 0.22, 0.70 | Section separators |
| `title` | 0.85, 0.78, 0.42, 1.00 | Panel titles (warm gold) |
| `label` | 0.69, 0.69, 0.69, 1.00 | Secondary labels |
| `value` | 0.92, 0.92, 0.92, 1.00 | Primary values |
| `groupHeader` | 0.55, 0.55, 0.60, 1.00 | Muted section headers |
| `btnBg` / `btnBorder` | 0.14, 0.14, 0.18 / 0.28, 0.25, 0.20 | Default buttons |
| `btnHoverBg` / `btnHoverBorder` | 0.20, 0.18, 0.14 / 0.45, 0.38, 0.18 | Button hover |
| `btnPressBg` | 0.08, 0.08, 0.10 | Button pressed |
| `btnActiveBg` / `btnActiveBorder` | 0.18, 0.16, 0.10 / 0.55, 0.46, 0.22 | Selected toggle tab |
| `btnText` / `btnTextHover` | 0.90, 0.88, 0.80 / 1.00, 0.94, 0.70 | Button label colors |
| `rowHover` | 0.20, 0.18, 0.12, 0.40 | List row hover tint |
| `rowSelected` | 0.22, 0.20, 0.10, 0.60 | Selected row background |
| `rowAccent` | 0.55, 0.46, 0.22, 1.00 | Left-edge selection bar |
| `gridHeaderBg` | 0.12, 0.12, 0.15, 1.00 | Gear / Reputation column headers |
| `scrollTrack` | 0.08, 0.08, 0.08, 0.80 | Scrollbar track |
| `scrollThumb` | 0.50, 0.50, 0.60, 1.00 | Scrollbar thumb |
| `headerBg` | 0.10, 0.10, 0.12, 0.95 | Main window title bar |
| `settingsGlow` | 1.00, 0.82, 0.20, 0.55 | Active settings gear glow |

Signal colors: `green`, `red`, `yellow` for status indicators.

## Backdrop recipes

All use `ChatFrameBackground` (bg) + `UI-Tooltip-Border` (edge).

| Tier | tile | edgeSize | insets | bg role | border role |
|------|------|----------|--------|---------|-------------|
| **window** | true, 16 | 16 | 4 | `panelBg` | `panelBorder` |
| **section** | false | 12 | 2 | `sectionBg` | `sectionBorder` |
| **graph** | false | 12 | 2 | `graphBg` | `sectionBorder` |
| **tooltip** | true, 16 | 12 | 3 | `sectionBg` | `panelBorder` |
| **button** | false | 10 | 2 | `btnBg` | `btnBorder` |

Apply via `Theme.ApplyBackdrop(frame, tier)`.

## Typography

| Element | Font object | Color role |
|---------|-------------|------------|
| Window title | `GameFontNormalLarge` | `title` |
| Section title | `GameFontHighlightSmall` | `title` |
| Section header | `GameFontNormalSmall` | `groupHeader` |
| Row / label | `GameFontHighlightSmall` | class color or `value` |
| Muted / empty | `GameFontDisable(Small)` | default gray |
| Button | inherited | `btnText` / `btnTextHover` |

## Spacing

- **Outer gutter**: 8px between window edge and content.
- **Panel padding**: 6–8px inside bordered sections.
- **Panel gap**: 4–8px between adjacent sections.
- **Row height**: 18–20px for list rows and option rows.

## Interaction states

- **Buttons**: `Theme.SkinButton(btn, isToggle)` — normal / hover / press / active (toggle) with backdrop color transitions.
- **Row hover**: `Theme.InstallHoverTint(frame)` + `Theme.SetHoverTint(frame, on)` or highlight texture tinted `rowHover`.
- **Row selected**: `rowSelected` background + left `rowAccent` bar (2px).
- **Disabled**: alpha 0.35–0.55 on text and controls.
- **Settings gear active**: `settingsGlow` texture behind icon.

## API summary

```lua
local T = AltArmy.Theme

T.ApplyBackdrop(frame, "section")   -- "window" | "section" | "graph" | "tooltip" | "button"
T.CreatePanel(parent, "section")
T.SkinButton(btn, isToggle)
T.InstallHoverTint(frame, "BACKGROUND")
T.SetHoverTint(frame, true)
T.StyleScrollThumb(texture)
T.StyleScrollTrack(texture)
T.CreateSeparator(parent, width)
T.ApplyInputTextures(editBox)       -- sets .bg and .border child textures
T.SetTitleColor(fontString)
T.SetGroupHeaderColor(fontString)
T.SetupScrollBar(slider, { thickness = 14 })           -- vertical
T.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
```

Scrollbars use a dark `scrollTrack` background plus the Blizzard `UI-ScrollBar-Knob` thumb (Compare panel style).

## Compatibility

- Prefer `CreateFrame("Frame", nil, parent, "BackdropTemplate")` for new panels.
- For existing frames: `Theme.EnsureBackdrop(frame)` mixes in `BackdropTemplateMixin` when `SetBackdrop` is missing.
- Never assume `SetBackdrop` exists without checking.
