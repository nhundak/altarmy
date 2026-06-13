# AltArmy Refactoring Opportunities

A code-review snapshot of refactoring opportunities across the addon's ~18,500 lines of
source (the `AltArmy_TBC/Data`, `AltArmy_TBC/Tabs`, and `AltArmy_TBC/UI` layers; excluding
bundled `Libs/` and the `busted/` test framework).

The codebase is generally well-organized: `Theme.lua` provides a styling layer, logic is
partly separated from UI (e.g. `ProgressionGraphLogic.lua`), and modules are cohesive. The
main opportunities are **cross-cutting duplication** and a few **oversized files/functions**
that mix concerns.

> Status: findings only — none of these have been implemented yet. Line numbers are
> approximate and reflect the codebase at review time.

## Suggested order of attack

1. **Quick utility extractions** (low risk, broad payoff) — shared helpers below.
2. **Theme constants + tokens** — centralize magic numbers, adopt existing color helpers.
3. **Shared UI factories** — scroll helpers, theme checkbox, scrollable grid + settings panel.
4. **File splits** — `TabCooldowns`, `DataStore` deferred timers, `Options` sub-tabs.
5. **Cleanup** — remove dead code; review the cooldown-expiry write path as a possible bug.

---

## 1. Top cross-cutting duplications (highest impact)

Small helpers copy-pasted across many files. Cheapest, safest wins.

| Helper | Copies | Where |
|--------|--------|-------|
| `TruncateName` (ellipsis via `GetStringWidth`) | 5 | `TabGear`, `TabReputation`, `TabSummary`, `TabSearch`, `CharacterPinHideList` |
| `GetSortValue` / `CompareBySort` (character sort comparators) | 3 | `TabGear`, `TabReputation`, `ReputationFactionSort` |
| Class-colored name formatting | 4–5 | `RealmFilter`, `CooldownAlerts`, `SummaryData`, `LevelProgressData`, `TabCooldowns` |
| Player identity (`GetCurrentPlayerName`/`Realm`/`IsCurrentCharacter`) | 3–4 | `DataStore`, `DataStoreCharacter`, `DataStoreMail`, inlined in `SummaryData` |
| "Iterate all characters" loop `for realm in pairs(DS:GetRealms())...` | 6+ | `SummaryData`, `SearchData`, `LevelProgressData`, `CooldownData`, `Options`, `TabCooldowns` |
| Search cache invalidation wrapper | 3 | `DataStoreContainers`, `DataStoreEquipment`, `DataStoreMail` |
| `CharKey` (with **inconsistent arg order**) | 3 | `TabGear`/`TabReputation` use `(name, realm)`; `TabProgression` uses `(realm, name)` |

**Suggestions:**

- Add `UI/Text.lua` (or extend `Theme`) with `TruncateFontString(fs, text, maxWidth, opts)`.
- Centralize `AltArmy.CharacterSort = { GetSortValue, CompareBySort }` and a single
  `AltArmy.CharKey(name, realm)` — and fix the `TabProgression` arg-order mismatch, which is
  a latent bug risk.
- Add `AltArmy.ClassColor.formatName(name, classFile)` / `getRGB(classFile)`.
- Export `DS.GetCurrentPlayerName/Realm/Identity/IsCurrentCharacter` once; add
  `DS:ForEachCharacter(callback)` to replace the nested realm/char loops.

---

## 2. Repeated UI scaffolding (high impact, medium risk)

The Tabs duplicate large, structural UI assemblies:

- **Scrollable character grid (~250–300 lines duplicated):** `TabGear` (~502–780) and
  `TabReputation` (~252–550) are two skins of the same two-axis scroll grid (vertical scroll
  child, fixed header row, horizontal scroll, scrollbars, wheel handlers).
  → Extract `Theme.CreateScrollableGrid(opts)`.
- **Character sort settings panel (~140 lines, near-verbatim):** `TabGear` (~1046–1249) vs
  `TabReputation` (~983–1164) differ only in the saved-var key and refresh callback.
  → `AltArmy.UI.CharacterSortSettingsPanel(frame, opts)`.
- **Horizontal scrollbar + drag-to-scroll (~45 lines × 4):** `TabSummary`, `TabSearch`,
  `TabGear`, `TabReputation`. Identical scale-aware cursor math.
  → `Theme.CreateHorizontalScrollBar(parent, opts)`.
- **Vertical scroll viewport (3 copies with drift):** `CharacterPinHideList`, `Options`,
  `CooldownOptions` reimplement ScrollFrame+Slider+wheel with different wheel multipliers and
  inconsistent resize clamping. → `Theme.CreateVerticalScrollViewport(opts)`.
- **Theme checkbox construction (3×):** `Theme.CreateLabeledCheckbox`, plus two manual copies
  in `CharacterPinHideList`; `TabProgression` uses raw `UICheckButtonTemplate`.
  → `Theme.CreateThemeCheckbox(parent, size)`.
- **Virtualized row list:** Reimplemented in `TabSearch`, `TabSummary`, `TabCooldowns`.
  `TabSearch.UpdateVisibleRows` (~716–920) repeats the same block three times
  (items/recipes/tooltip-only). → a generic `VirtualList` helper.

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
- **`CharKey` arg-order mismatch** (see §1) — verify `TabProgression` call sites.
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
