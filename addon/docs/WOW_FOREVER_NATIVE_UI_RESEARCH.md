# WoW Forever native UI — research

Research for a possible UI/UX rework: making AltArmy look and feel like the built-in WoW Forever client UI (window frames, buttons, tabs, lists, dropdowns). This covers **source and web research only** (checked 2026-09-23). Nothing here has been verified in the live client yet. Today's custom look is documented in [UI_DESIGN.md](UI_DESIGN.md) (`AltArmy_TBC/UI/Theme.lua`). For addon-API compatibility, see [WOW_FOREVER_COMPATIBILITY_RESEARCH.md](WOW_FOREVER_COMPATIBILITY_RESEARCH.md) and [WOW_FOREVER_COMPAT.md](WOW_FOREVER_COMPAT.md).

## TL;DR

- Forever's UI code is the **retail (Mainline, Midnight-era) FrameXML** plus Forever-specific overrides. Blizzard's internal name for Forever is **"Camelot"**.
- Forever doesn't add new template names. It **reskins the retail art in place**: the same texture names (atlases) and NineSlice layouts, with Forever-drawn art and small offset fixes.
- So an addon built from **stock Blizzard templates and atlas names looks native on Forever automatically**. Hand-drawn backdrops (AltArmy today) don't.
- Nearly every template we'd use **also exists on TBC Anniversary 2.5.6**, where it draws with Classic art. AltArmy's single `.toc` (`## Interface: 20506, 16001`) can therefore look native on both clients. Only a few Forever/retail-only pieces need a fallback.

## Primary source: Blizzard's UI code

[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/branches) mirrors Blizzard's UI code per game version:

| Branch | Build (at check time) | Use |
|---|---|---|
| `forever` | 1.60.1 (69977) | WoW Forever |
| `classic_anniversary` | 2.5.6 (69795) | TBC Anniversary |

To browse locally: `git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source.git`. Grep for `name="<TemplateName>"` to find a template's XML.

### How Forever differs from retail

- Blizzard's `.toc` files (the load lists inside each Blizzard_* folder) treat Forever as a variant of retail ("mainline"). For example, `Blizzard_Minimap.toc` loads `[Game]\MinimapConstants.lua [AllowLoadGameType camelot]` next to `[Family]\MinimapConstants.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`. So files marked for "mainline" also load on Forever unless they explicitly exclude it.
- There are 48 `Camelot/` override folders, e.g. `Blizzard_SharedXML/Camelot`, `Blizzard_UIPanels_Game/Camelot` (Character, Reputation, Skills, Bank, Container frames), `Blizzard_Minimap/Camelot/Skin.lua`.
- `Blizzard_SharedXML/Camelot/NineSliceLayoutOverrides.lua` says it outright: *"the art made for Camelot doesn't match the exact size of the Mainline Standard art and needs to be offset differently."* It patches corner offsets of `UI-Frame-Metal-*` pieces in every `NineSliceLayouts` entry. Anything using those layouts (`ButtonFrameTemplate`, `PortraitFrameTemplate`, …) inherits the fix.
- `Blizzard_SharedXML/Camelot/SharedUIPanelTemplates.lua` re-anchors `UIPanelCloseButtonDefaultAnchors` and side-tab icon offsets for the Camelot art.
- Forever-only template: `ColoredProgressBarTemplate` (`Blizzard_SharedXML/Camelot/ProgressBars/`). It uses the `common-stat-bar-BG` / `common-stat-bar-white` / `common-stat-bar-Mask` atlases.

**Implication:** reference art through `SetAtlas("<atlas name>")` and inherit templates. Don't ship BLP files or hard-code texture file paths, or the Forever reskin gets bypassed.

## Template / API availability

Checked by grepping both branches for the template definition.

| Element | Template / API | Forever | TBC 2.5.6 | Notes |
|---|---|---|---|---|
| Main window | `ButtonFrameTemplate`, `PortraitFrameTemplate`, `PortraitFrameFlatTemplate`, `PortraitFrameBaseTemplate` | ✅ | ✅ | `ButtonFrameTemplate_HidePortrait(frame)` for no portrait |
| Plain panel | `DefaultPanelTemplate`, `DefaultPanelFlatTemplate` | ✅ | ✅ | |
| Inset content area | `InsetFrameTemplate` | ✅ | ✅ | |
| Close button | `UIPanelCloseButton`, `UIPanelCloseButtonDefaultAnchors` | ✅ | ✅ | Forever re-anchors it for its art |
| Bottom / top tabs | `PanelTabButtonTemplate`, `PanelTopTabButtonTemplate` + `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab` | ✅ | ✅ | Classic-style tab strip |
| Modern tab bar | `TabSystemTemplate`, `TabSystemButtonTemplate` | ✅ | ✅ | Dragonflight-style tab system (used in retail's newer windows) |
| Side tabs | `LargeSideTabButtonTemplate` | ✅ | ❌ | Used by Forever's CharacterFrame |
| Scrolling lists | `WowScrollBoxList` + `MinimalScrollBar` / `WowTrimScrollBar`; `CreateDataProvider`, `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar` | ✅ | ✅ | Replaces hand-rolled row pooling |
| Dropdowns | `WowStyle1DropdownTemplate`, `WowStyle1FilterDropdownTemplate` (`DropdownButton` + `SetupMenu`) | ✅ | ✅ | |
| Context menus | `MenuUtil.CreateContextMenu`, `MenuUtil.CreateButtonMenu` | ✅ | ✅ | Replaces `UIDropDownMenu_*` |
| Search box | `SearchBoxTemplate` | ✅ | ✅ | |
| Buttons | `UIPanelButtonTemplate`, `UIPanelDynamicResizeButtonTemplate`, `SharedButtonSmallTemplate`, `SharedGoldRedButtonSmallTemplate` | ✅ | ✅ | |
| Checkbox | `UICheckButtonTemplate`, `SettingsCheckboxTemplate` | ✅ | ✅ | |
| Slider | `MinimalSliderWithSteppersTemplate` | ✅ | ✅ | |
| Column headers | `ColumnDisplayTemplate` | ✅ | ✅ | |
| Layout helpers | `VerticalLayoutFrame`, `ResizeLayoutFrame` | ✅ | ✅ | |
| Progress bar (Forever art) | `ColoredProgressBarTemplate` | ✅ | ❌ | Forever-only; needs a fallback |
| Options UI | `Settings.RegisterVerticalLayoutCategory` (native controls), `Settings.RegisterCanvasLayoutCategory` (custom canvas) | ✅ | ✅ | AltArmy already uses Canvas |
| Addon compartment | `AddonCompartmentFrame`; `.toc` `## AddonCompartmentFunc` | ✅ | ❌ | Loads for mainline, so it's on Forever; keep LibDBIcon for TBC |

## Blizzard's own Forever windows as references

These are the closest models for AltArmy's tabs, and they're built only from the templates above:

- **`Blizzard_UIPanels_Game/Camelot/ReputationFrame.xml`**: `WowScrollBoxList` + `MinimalScrollBar` list, `WowStyle1DropdownTemplate` filter, `ColoredProgressBarTemplate` bars, `SharedGoldRedButtonSmallTemplate` button, `CallbackRegistrantTemplate`. A direct model for the Reputation tab.
- **`Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml`**: `PortraitFrameBaseTemplate` shell, `UIPanelCloseButtonDefaultAnchors`, `LargeSideTabButtonTemplate` side tabs, stat categories in a ScrollBox (`CharacterStatsPaneScrollBoxTemplate`), `VerticalLayoutFrame`. A model for Gear / Summary layouts.
- **`Blizzard_UIPanels_Game/Camelot/SkillsFrame.xml`**: `SkillsEntryTemplate` / `SkillsBarTemplate` rows. A model for profession rows.
- **`Blizzard_Menu/11_0_0_MenuImplementationGuide.lua`**: Blizzard's own worked examples for the Menu system.

## What the community is doing

- Most Forever UI addons so far go the **other direction**, putting Classic art back over what players call Forever's "modern flat and unadorned frames": [ClassicUI Forever](https://www.curseforge.com/wow/addons/classicui-forever), [standujar/forever-classic-ui](https://github.com/standujar/forever-classic-ui) (partial skins of 16 windows; restores Classic Era BLPs; hooks into Edit Mode), [Classic UI for Forever](https://www.curseforge.com/wow/addons/classic-ui-for-forever). Forever's Layout menu also ships "Modern" and "Classic" presets ([wowhead](https://www.wowhead.com/forever/news/updated-character-panel-ui-in-wow-forever-explains-stats-in-detail-383013), [warcrafttavern](https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/)).
  - This supports using stock templates: AltArmy then follows the player's chosen look (and any reskin addon that targets Blizzard templates) instead of forcing its own.
- Cross-version addons already on Forever that build on Blizzard's modern toolkit: Auctionator and Baganator/Syndicator (plusmouse). Baganator ships a default "Blizzard" skin alongside ElvUI / GW2 skins ([Patreon post](https://www.patreon.com/posts/skins-for-105871197), [CurseForge](https://www.curseforge.com/wow/addons/baganator)). Its source repo wasn't publicly clonable at check time.
- [Royaleint/Foundry](https://github.com/Royaleint/Foundry) (MIT) wraps the Settings API, Menu system, ScrollBox and tooltip hooks with less boilerplate. It doesn't provide window frames, tabs or buttons, and doesn't document which game versions it supports.
- [DragonUI PR #459](https://github.com/NeticSoul/DragonUI/pull/459) is a worked example of applying `PortraitFrameTemplate` and `InsetFrameTemplate` NineSlice chrome to a custom frame. Gotcha: stripping textures only reaches the frame's own regions and `NineSlice`, not child frames like `CloseButton` / `PortraitContainer`.

## Implications for an AltArmy rework

- **Theme.lua is the seam.** Tabs already go through `Theme.CreatePanel`, `Theme.SkinButton`, `Theme.SetupScrollBar`, `Theme.CreateTabContentPanel`, etc. A "native" mode can swap what those helpers build (inherit templates instead of `BackdropTemplate` + palette) without rewriting each tab first.
- **Dropdowns:** `UIDropDownMenu_*` (used today) is kept only for backward compatibility on the retail-based client and is otherwise deprecated ([Patch 11.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_11.0.0/API_changes)). Move to `WowStyle1DropdownTemplate` / `MenuUtil` ([Menu implementation guide](https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide)), which works on both clients.
- **Lists:** ScrollBox + DataProvider replaces custom scroll frames and row pools. It also shifts per-row locals out of the large `Tabs/Tab*.lua` main chunks, which helps with the Lua 5.1 200-local limit (see [CLAUDE.md](../CLAUDE.md)).
- **Forever-only pieces:** check before use, e.g. `if C_XMLUtil.GetTemplateInfo("ColoredProgressBarTemplate") then … end` (or `pcall` around `CreateFrame`), and fall back on TBC. Same for the addon compartment vs LibDBIcon.
- **Art:** use `SetAtlas` names, never bundled textures. Treat custom palette colors as an accent, not the frame chrome.
- **Open question:** whether to keep the current dark/bronze theme as an option (like Baganator's skins) or go fully native. Also check how the reskin addons above treat third-party windows built from Blizzard templates.

## Suggested next step

Build a throwaway spike window: `ButtonFrameTemplate` shell + `TabSystemTemplate` tabs + `WowScrollBoxList` / `MinimalScrollBar` list + `WowStyle1DropdownTemplate` + `SearchBoxTemplate`. Load it on **both** Forever and TBC Anniversary and screenshot. Use [DEV_DUMPS.md](DEV_DUMPS.md) to capture anything that errors on one client.

## Sources

- [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) — `forever` and `classic_anniversary` branches (cloned and grepped 2026-09-23)
- [ClassicUI Forever](https://www.curseforge.com/wow/addons/classicui-forever), [Classic UI for Forever](https://www.curseforge.com/wow/addons/classic-ui-for-forever), [standujar/forever-classic-ui](https://github.com/standujar/forever-classic-ui)
- [Warcraft Tavern: ClassicUI Forever](https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/)
- [Wowhead: Forever character panel](https://www.wowhead.com/forever/news/updated-character-panel-ui-in-wow-forever-explains-stats-in-detail-383013)
- [WoW Forever addons guide](https://wowforevergame.wiki/classic-plus/wow-forever-addons-guide/) (interface 16001, shared 12.1.5 API set)
- [Warcraft Wiki: Patch 11.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_11.0.0/API_changes), [Blizzard Menu implementation guide](https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide), [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment)
- [Royaleint/Foundry](https://github.com/Royaleint/Foundry)
- [Baganator](https://www.curseforge.com/wow/addons/baganator), [Skins for Baganator](https://www.patreon.com/posts/skins-for-105871197)
- [NeticSoul/DragonUI PR #459](https://github.com/NeticSoul/DragonUI/pull/459)
