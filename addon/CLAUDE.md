# CLAUDE.md

Conventions for AI agents working in this repository.

## Project

AltArmy TBC is a **World of Warcraft: The Burning Crusade Classic** account-wide alt-management addon. UI and data live under `AltArmy_TBC/` (Lua 5.1). Tests and tooling: `npm test`, `npm run check` (see `TESTING.md`, `LINTING.md`).

## Documentation

Product docs live in **`docs/`**. Start at [`docs/README.md`](docs/README.md).

Do **not** recreate deleted root specs (`ALTARMY_TBC_STRUCTURE.md`, `ALTARMY_TBC_SUMMARY.md`, `ALTARMY_TBC_CHARACTERS.md`, `ALTARMY_TBC_SEARCH.md`, `ALTARMY_TBC_OPTIONS_AND_MINIMAP.md`). There is no Characters containers tab; inventory is Search.

### Keep docs in the same task

When you change **user-visible** behavior, update the matching docs in the **same task** — not as a follow-up.

| Code change | Update |
|-------------|--------|
| Tab UI / workflow (`Tabs/Tab*.lua`) | Matching `docs/tabs/*.md`; `docs/FEATURES.md` if it is a significant new capability |
| New main-window tab | New `docs/tabs/` file, `docs/README.md`, `docs/FEATURES.md`, `docs/ARCHITECTURE.md` |
| Options, minimap, slash commands | `docs/tabs/options.md` |
| Alerts, bank alts, realm filter, optional addon deps | `docs/FEATURES.md` (cross-cutting) and the owning tab doc |
| DataStore scan/shape / SavedVariables | `AltArmy_TBC/Data/DESIGN.md` and `DATA_VERSIONS.md` if a version or domain changed |
| Shipping or dropping a roadmap item | `docs/FEATURE_IDEAS.md` status table; move shipped detail into FEATURES / tab docs |

### Altitude

Significant features only. Skip debug-only slash commands, placeholder files, and pixel-level UI.

### Finish check

If the diff is user-visible and no `docs/` (or Data DESIGN / DATA_VERSIONS) file changed, the work is incomplete unless the change is purely internal.

## Other project rules

Prefer red-green-refactor for new features: write a failing unit test first, then make it pass.

Domain-specific skills (e.g. debug compare dumps, Summary missing-data) live in `.claude/skills/`.

### Lua tooling

Use `npm test` and `npm run check` / `npm run lint` from the repo root. Do **not** search for a system Lua install, invent `LUA_51_PATH`, shim `luajit` as `lua.exe`, or poke Homebrew/LuaRocks unless an `npm` script fails with a clear missing-tool message — if Lua 5.1 / busted / luacheck are missing, run `npm run setup:dev` once, then retry. Runners auto-resolve `<repo>/.lua51/bin` (and Windows Lua for Windows defaults); no per-session env exports are needed once that tree exists.

### Lua 5.1 local-variable limit

WoW TBC runs Lua 5.1, which allows at most **200 local variables per function** (a file's main chunk counts as one function). Exceeding it fails at load with `main function has more than 200 local variables` — **luacheck does not catch this**; only `npm run check`'s Lua 5.1 compile pass does. Run it after editing large `Tabs/Tab*.lua` files (especially `TabGuild.lua` / `TabGear.lua` / `TabSearch.lua`), before considering the work done.

When editing those large UI files: prefer packing related constants/session state into one table (`local UI = { ... }`, `local state = { ... }`) instead of many top-level `local`s; prefer small helper modules under `Data/` for pure logic rather than growing a tab file's main-chunk locals. Nested `do ... end` blocks do **not** reset the limit, only a new function gets a fresh 200; forward declarations (`local foo` then `foo = function...`) still count. If the warning appears, count top-level locals and reduce by grouping into tables or extracting helpers until comfortably under 200, leaving headroom for future edits.
