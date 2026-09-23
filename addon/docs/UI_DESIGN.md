# AltArmy UI Design System

AltArmy looks like a built-in Blizzard window. It uses the same templates, texture files and atlases as the stock UI.

This matters on WoW Forever, which reskins those assets in place: reusing them means AltArmy follows Forever's art, the player's Classic/Modern layout choice, and any reskin addon that targets Blizzard templates. On TBC Anniversary the same names draw the Classic art.

Background research is in [WOW_FOREVER_NATIVE_UI_RESEARCH.md](WOW_FOREVER_NATIVE_UI_RESEARCH.md).

## Single source of truth

- **`AltArmy_TBC/UI/Theme.lua`:** every panel, button, scrollbar, checkbox, dropdown, input and row hover goes through a `Theme.*` helper. Tab files must not copy-paste chrome.
- **`AltArmy_TBC/UI/NativeUI.lua`:** detects which Blizzard templates and atlases the client has (`NativeUI.GetCaps()`). Each helper checks the relevant capability and falls back to the legacy flat theme (see [Legacy fallback](#legacy-fallback)) when it's missing.

## Main window

| Piece | Implementation |
|-------|----------------|
| Shell | `PortraitFrameTemplate`, 640 × 484 (Forever's `CHARACTER_FRAME_HEIGHT`). Provides the rock background, NineSlice border, close button, portrait circle and title bar. |
| Title / portrait | `SetTitle("Alt Army - <Tab>")` and `SetPortraitToAsset(icon)` on every tab switch. Both come from `UI/MainTabs.lua`. |
| Tabs | `UI/SideTabs.lua`: icon flyouts anchored like CharacterFrame's mode tabs. Forever uses `LargeSideTabButtonTemplate`; TBC uses spellbook skill-line tab art. On Forever, Reputation and Graphs use CharacterFrame's own Reputation / Statistics side-tab icons (`INV_SideTab_*_c60`). Guild shows the player's guild crest (`UI/GuildCrest.lua`), falling back to the tabard icon. |
| Sub-view tabs | `UI/TopTabs.lua`: spellbook-style tabs hanging from a panel top into the toolbar row Forever uses `TabSystemTemplate` + `TabSystemTopButtonTemplate` square icon tabs. TBC doesn't load TabSystem, so it uses classic text top tabs (`PanelTopTabButtonTemplate` + `PanelTemplates_SelectTab`). Anchor the tab row's BOTTOMLEFT at the tab frame's TOPLEFT + `AltArmy.MainToolbarInsetX`. |
| Toolbar | A row under the title bar, right of the portrait: a search slot (Summary's item search, or the Reputation / Guild tab's own filter), the active tab's settings button, and the search-mode Filter dropdown. |

## Helper → native art

| Helper | Native result | Capability |
|--------|---------------|------------|
| `ApplyBackdrop(f, "section" \| "graph")`, `CreatePanel`, `CreateTabContentPanel` | `InsetFrameTemplate` NineSlice layout drawn onto the frame at BORDER, over a tiled `UI-Background-Marble` | `nineSlice` |
| `ApplyBackdrop(f, "window" \| "dialog")` | `Dialog` NineSlice layout over a tiled `UI-DialogBox-Background-Dark` | `nineSlice` |
| `ApplyBackdrop(f, "tooltip")` | `TooltipDefaultLayout` with the GameTooltip center tint | `nineSlice` |
| `SkinButton`, `SkinDangerButton` | `UIPanelButtonTemplate` art (the `UI-Panel-Button-Up/Down/Disabled/Highlight` slices). Template buttons keep their own art; plain buttons get it drawn on. Toggles use `LockHighlight`. Danger buttons use red label text. | `nineSlice` |
| `SetupScrollBar`, `AnchorVerticalScrollBar`, `CreateHorizontalScrollBar`, `CreateVerticalScrollViewport` | `MinimalScrollBar` art drawn on our Slider (horizontal bars use the atlases rotated 90°): track, rounded thumb, and arrow stepper buttons at each end (click to step, hold to repeat). The Slider's thumb is an invisible hit texture `stepperInset` (19px) longer at each end, so the visible thumb travels only between the arrows. Callers keep the Slider API and their anchors. | `minimalScrollBar` |
| `CreateThemeCheckbox`, `CreateLabeledCheckbox` | `UICheckButtonTemplate`, grown by `NATIVE_CHECKBOX_PAD` (4px) because the art has transparent padding | `checkButton` |
| `CreateSingleSelectDropdown`, `CreateMultiSelectCheckboxDropdown`, `SkinDropdownButton`, `SkinDropdownPopup` | `WowStyle1DropdownTemplate` / `MenuStyle1` art: text holder, arrow and menu background. The selected row gets a radio check. Forever uses the mainline atlases, TBC the `-classic-` ones (chosen by `WOW_PROJECT_ID`). Popups reserve the native menu insets (`GetDropdownPopupInsets`; rows × height + top + bottom). | `wowStyleDropdown` |
| `CreateFilterDropdown` | The real `WowStyle1FilterDropdownTemplate` ("Filter" button, as in the Professions window) driven by `SetupMenu` / Blizzard_Menu checkboxes, dividers and buttons. Without the template: a skinned trigger and a popup rebuilt from the same entries. Used by the Search-mode toolbar. | `filterDropdown` |
| `ApplyInputTextures` | `InputBoxTemplate` border (`common-search-border-left/middle/right`) | `inputBox` |
| `CreateSearchBox` | `SearchBoxTemplate`, with a built-in magnifier, clear button and `Instructions` placeholder. Without the template, the fallback box draws the same pieces: magnifier, placeholder, and a clear (x) button inside the right edge that shows only while there is text. Hook its scripts with `HookScript`. Every search box (items/recipes, Reputation faction filter, Guild character and recipe searches) uses it so they look and behave the same. | `searchBox` |
| `InstallHoverTint`, `BindInteractableHover` | Additive `UI-QuestTitleHighlight` list glow | `nineSlice` |
| `StyleGridHeader`, `ApplyGridLabelColumnBackground` | Tiled inset background, so pinned headers stay opaque over scrolling rows | `nineSlice` |
| Pinned scroll fades | Neutral shadow (`NATIVE_SCROLL_SHADOW`) | `nineSlice` |

Rules:
- **Use atlases and texture paths, never bundled art, for chrome.** The textures under `AltArmy_TBC/Textures/` are for content, such as the compare arrow and quest reward markers.
  - **One exception:** `Textures/Icons/INV_SideTab_Reputation2_c60.blp` and `INV_SideTab_Stats_c60.blp` are byte-identical copies of Forever's CharacterFrame side-tab icons (fileDataIDs 8197103 / 8197104).
  - Only TBC Anniversary uses them, because those files don't exist in its game data. Forever keeps loading its own copies from `Interface\Icons`.
  - To re-extract them after a game update, with a local Forever install: `python scripts/extract-casc-files.py wow_classic_beta <outdir> interface/icons/inv_sidetab_reputation2_c60.blp interface/icons/inv_sidetab_stats_c60.blp`. The script is a read-only reader of the local CASC storage.
  - **Second exception:** `Textures/Icons/GearViewGrid.tga` and `GearViewUpgradeCheck.tga` are the Gear tab's Grid / Upgrade Check sub-view tab icons. They're drawn in code in the retail icon style (gold bevelled metal on a dark painted background), because no built-in grid or scales icon exists in Forever, TBC Anniversary or MoP Classic. To change them, edit and rerun `python scripts/generate-gear-view-icons.py [--preview out.png]` (requires Pillow).
- **Don't tint native chrome.** `SetBackdropColor` / `SetBackdropBorderColor` do nothing on native panels, because no backdrop is set. Where the tint itself carries meaning (the options attention flash), use `Theme.ApplyLegacyBackdrop`.
- **New Blizzard templates:** add a capability to `NativeUI.DetectCaps()` and give the helper a fallback before using the template in a tab.

## Text colors

`Theme.COLORS` still defines the text and signal roles: `title`, `label`, `value`, `groupHeader`, and `green` / `red` / `yellow`. Chrome roles (`panelBg`, `btn*`, `scroll*`, …) are used only by the legacy fallback.

`Theme.BUTTON_TEXT` holds the native button label colors: normal gold, highlight white, disabled gray, danger red.

## Typography

Use `Theme.FONTS.<role>` for every FontString, font object and EditBox font. A spec (`spec/UI/ThemeFonts_spec.lua`) fails on new `"GameFont…"` literals in UI code.

Like native panels (Character, Reputation, Skills), all AltArmy text is 12pt, including grids, column headers, footnotes and button labels. Only Gear upgrade badges and quest-reward glyphs use a 10pt base. Sizes are the same on Forever and TBC Anniversary: Small 10, Normal/Highlight 12, Med3 14, Large 16.

| Role | Font object | Use for |
|------|-------------|---------|
| `title` | `GameFontNormalMed3` (14) | Panel, settings and dialog titles |
| `heading` | `GameFontNormal` (12, gold) | Section, group and column headers, labels, compact button and tab labels |
| `body` | `GameFontHighlight` (12, white) | Grid cells, list rows, values, footnotes and hints, settings and checkbox text, dropdowns, inputs |
| `muted` | `GameFontDisable` (12) | Unavailable rows, graph axis labels, inline empty notes |
| `emptyState` | `GameFontDisableLarge` (16) | Centered empty-state messages that replace a table or graph (Graphs hint, Cooldowns views) |
| `headline` | `GameFontHighlightLarge` | Dialog headline |
| `pageTitle` | `GameFontNormalHuge` | Interface Options page header |
| `badge` | `GameFontNormalSmall` (10, drawn ×2) | Gear upgrade glyphs on item icons |

The title bar text comes from the template (`GameFontNormal`).

## Spacing

- **Window gutter:** 8px between the NineSlice border and the content area. Content starts at y −60, below the toolbar.
- **Panel padding:** 6–8px inside inset panels.
- **Panel gap:** 4px between adjacent sections (`Theme.SECTION_GAP`).
- **Row height:** 18–20px for list rows and option rows.

## Legacy fallback

When a capability is missing, helpers use the original dark/bronze flat theme: `BackdropTemplate` with `ChatFrameBackground` + `UI-Tooltip-Border`, colored from `Theme.COLORS`. Both Forever and TBC Anniversary have every capability today, so the fallback only protects against client changes. It is not a user-selectable skin.
