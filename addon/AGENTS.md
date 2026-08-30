# AGENTS.md

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

Prefer red-green-refactor for new features. After large `Tabs/Tab*.lua` edits, run `npm run check` (Lua 5.1 local limit). See `.cursor/rules/` for TDD, Lua tooling, and domain-specific skills.
