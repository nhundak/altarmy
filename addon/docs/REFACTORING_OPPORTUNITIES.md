# AltArmy Refactoring Opportunities

A code-review snapshot of refactoring opportunities across the addon's ~18,500 lines of
source (the `AltArmy_TBC/Data`, `AltArmy_TBC/Tabs`, and `AltArmy_TBC/UI` layers; excluding
bundled `Libs/` and the `busted/` test framework).

The codebase is generally well-organized: `Theme.lua` provides a styling layer, logic is
partly separated from UI (e.g. `ProgressionGraphLogic.lua`), and modules are cohesive. The
main opportunities are **cross-cutting duplication** and a few **oversized files/functions**
that mix concerns.

> Status: **§1 implemented** (June 2026). **§2 partial** — safe-wave UI factories done (June 2026).
> §2 grid/sort-panel/virtual-list and §3–§6 are still open. Line numbers in §2–§6 are
> approximate and reflect the codebase at review time.

## Suggested order of attack

1. ~~**Quick utility extractions** (low risk, broad payoff) — shared helpers below.~~ **Done** (see §1).
3. ~~**Shared UI factories (safe wave)** — horizontal scrollbar, vertical scroll viewport, theme checkbox.~~ **Done** (see §2).
4. **Shared UI factories (remaining)** — scrollable grid + sort settings panel + virtual list.
5. **Theme constants + tokens** — centralize magic numbers, adopt existing color helpers.
6. **File splits** — `TabCooldowns`, `DataStore` deferred timers, `Options` sub-tabs.
7. **Cleanup** — remove dead code; review the cooldown-expiry write path as a possible bug.

---

## 1. Top cross-cutting duplications (highest impact) — **Done**

Small helpers that were copy-pasted across many files. Extracted into shared modules; call
sites migrated; unit tests added under `spec/Data/` and `spec/UI/`.

| Helper | Was (copies) | Resolution |
|--------|--------------|------------|
| `TruncateName` | 5 (`TabGear`, `TabReputation`, `TabSummary`, `TabSearch`, `CharacterPinHideList`) | [`UI/Text.lua`](../AltArmy_TBC/UI/Text.lua) — `AltArmy.Text.TruncateFontString(fs, text, maxWidth, opts)` |
| `GetSortValue` / `CompareBySort` | 3 (`TabGear`, `TabReputation`, `ReputationFactionSort`) | [`Data/CharacterSort.lua`](../AltArmy_TBC/Data/CharacterSort.lua) — `AltArmy.CharacterSort` |
| Class-colored name formatting | 4–5 inline + `RealmFilter` | [`Data/ClassColor.lua`](../AltArmy_TBC/Data/ClassColor.lua) — `getRGB`, `getRGBOr`, `formatName`, `formatHex`, `wrapName`; `RealmFilter.formatColoredCharacterNameRealm` delegates internally |
| Player identity | 3–4 private/inlined | [`DataStore.lua`](../AltArmy_TBC/Data/DataStore.lua) — `GetCurrentPlayerName/Realm/Identity`, `IsCurrentCharacter` |
| "Iterate all characters" loop | 6+ | `DS:ForEachCharacter(callback)` — used in `SummaryData`, `SearchData`, `CooldownData`, `Options`, `LevelProgressData` (debug). `TabCooldowns` realm-count loop left as-is. |
| Search cache invalidation wrapper | 4 (`Containers`, `Equipment`, `Mail`, `Professions`) | [`SearchData.lua`](../AltArmy_TBC/Data/SearchData.lua) — `NotifyContainerDataChanged`, `NotifyRecipesChanged` |
| `CharKey` (inconsistent arg order) | 4 tabs | [`Data/CharKey.lua`](../AltArmy_TBC/Data/CharKey.lua) — `AltArmy.CharKey(name, realm)`; `TabProgression` arg order fixed |

**Tests:** `CharKey_spec`, `CharacterSort_spec`, `ClassColor_spec`, `Text_spec`; extended
`DataStore_spec`; updated `GearDisplayList_spec`, `LevelProgressData_spec`,
`CooldownData_spec`, `ReputationFactionSort_spec`.

---

## 2. Repeated UI scaffolding (high impact, medium risk)

The Tabs duplicate large, structural UI assemblies. **Safe wave (June 2026)** extracted three
helpers into [`UI/Theme.lua`](../AltArmy_TBC/UI/Theme.lua); call sites migrated; tests in
[`spec/UI/theme_spec.lua`](../spec/UI/theme_spec.lua).

| Item | Status | Resolution |
|------|--------|------------|
| **Horizontal scrollbar + drag-to-scroll** (~45 lines × 4) | **Done** | `Theme.CreateHorizontalScrollBar(parent, opts)` + `Theme.HorizontalDragValue` — adopted in `TabGear`, `TabReputation`, `TabSummary`, `TabSearch` |
| **Vertical scroll viewport** (3 copies with drift) | **Done** | `Theme.CreateVerticalScrollViewport(opts)` + `Theme.ScrollMax` / `Theme.ClampScroll` — adopted in `CharacterPinHideList`, `Options` char list, `CooldownOptions`; unified clamp-on-range-shrink |
| **Theme checkbox construction** (3×) | **Done** | `Theme.CreateThemeCheckbox(parent, size)` — `CreateLabeledCheckbox` refactored; adopted in `CharacterPinHideList` (pin/hide), `TabProgression` (replaces `UICheckButtonTemplate`) |
| **Scrollable character grid** (~250–300 lines duplicated) | Open | `TabGear` / `TabReputation` two-axis scroll grid → `Theme.CreateScrollableGrid(opts)` |
| **Character sort settings panel** (~140 lines) | Open | `TabGear` / `TabReputation` near-verbatim panel → `AltArmy.UI.CharacterSortSettingsPanel(frame, opts)` |
| **Virtualized row list** | Open | `TabSearch`, `TabSummary`, `TabCooldowns` → generic `VirtualList` helper |

**Still open (detail):**

- **Scrollable character grid:** `TabGear` (~502–780) and `TabReputation` (~252–550) are two
  skins of the same two-axis scroll grid (vertical scroll child, fixed header row, horizontal
  scroll, scrollbars, wheel handlers).
- **Character sort settings panel:** `TabGear` (~1046–1249) vs `TabReputation` (~983–1164)
  differ mainly in saved-var key and refresh callback.
- **Virtualized row list:** `TabSearch.UpdateVisibleRows` (~716–920) repeats the same block
  three times (items/recipes/tooltip-only).

---

## 3. Oversized files / functions to split

| File | Lines | Notes |
|------|-------|-------|
| `TabCooldowns.lua` | 1,639 | Mixes list UI with live bag/mail attach logic. `TryAdvanceAttachSeq` alone is ~290 lines (~1167–1456). Mail/stockpile action sequence (~700 lines) could move to a testable non-UI module. |
| `TabProgression.lua` | 1,303 | Graph rendering (~678–1026) could move to a render module; compare-selector panel to its own module. |
| `TabReputation` / `TabGear` / `TabSearch` | ~1,166–1,251 | Shrink substantially once the shared grid/settings/scroll helpers (§2) are extracted. |
| `DataStoreProfessions.lua` | 1,101 | Owns scanning, reagent capture, cooldown persistence, action-bar scans. Split into scan/reagents/cooldown submodules. |
| `DataStoreLevelHistory.lua` | 1,063 | Mixes runtime recording with one-time Questie/RXP/NIT imports + migration. |
| `DataStore.lua` | 606 | Single `OnEvent` handles 30+ events inline; **7 near-identical deferred-timer frames** (~194–426) → one `RunAfterDelay(delay, fn)` helper. |
| `Options.lua` | 887 | Mixes defaults, tab strip, 3 sub-tabs, char list, slash commands. `CooldownOptions` already demonstrates the cleaner host-panel split to mirror. |

---

## 4. Inconsistency / correctness-adjacent items

- **Cooldown expiry writes bypass the safe path:** `DataStoreProfessions` tradeskill/craft
  scans write `char.ProfCooldownExpiry` directly (~1010–1087), skipping the `(0,0)`
  anti-clobber guard in `PersistCooldownExpiry` (~65–93). Route all writes through one
  function. **This is the one finding that may be a latent bug, not just style — worth a
  closer look.**
- ~~**`CharKey` arg-order mismatch** (see §1) — fixed: all tabs use `AltArmy.CharKey(name, realm)`.~~
- **Theme tokens defined but unused:** `SetLabelColor`, `SetGroupHeaderColor`, `CreatePanel`,
  `ApplyDropdownBackground`, deprecated `StyleScrollThumb`. Meanwhile colors are hardcoded
  elsewhere (e.g. muted `0.5,0.5,0.5` in `CooldownOptions`, `Core`, `TabReputation`).
  → Add `Theme.COLORS.muted` + `SetMutedColor` and adopt the existing helpers (or delete them).
- **Bag/bank constants redefined:** `SearchData` (~7–9) re-declares `BANK_CONTAINER` etc.
  already exported on `DS`.

---

## 5. Dead / unused code

- `GraphCore.CreateTooltipBase` (~401–441) — never called.
- `DataStoreContainers.ScanBagsAndLog` (~256) — duplicate of `ScanCurrentCharacterBags`,
  no production callers.
- `DataStoreCharacter.GetStoredRestXp` — only referenced by tests.
- `TabGear` left panel ("Who can use this?", ~55 lines) gated behind `LEFT_PANEL_VISIBLE = false`.
- `LevelProgressData.WATCH_NAMES_LOWER` — all entries commented out, but still iterated.
- `TabSearch`/`TabSummary` build list widgets on `frame` then reparent to the scroll child —
  leftover migration artifact with dead initial anchors.

---

## 6. Magic numbers worth centralizing

Recurring across tabs and not in `Theme`: `PAD = 4`, `HORIZONTAL_SCROLL_BAR_HEIGHT = 20`,
`ROW_HEIGHT = 18/20`, `GRID_SPLIT_FRACTION = 0.6`, `MIN_SCROLL_CHILD_WIDTH = 400`, hint
width `520`.

In Data: `MAX_LOGOUT_SENTINEL = 5000000000`, `28800` (rest bubble), `86400` (seconds/day),
`1.5` (rest cap multiplier), `0.10` (post-cast scan delay).

→ Promote to `Theme.*` and `DS.*` constants.
