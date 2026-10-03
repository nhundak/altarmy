# Next steps after the monorepo move

The site and the addon moved into this repository on 2026-10-03 (`site/`, `addon/`; see `CLAUDE.md`). The
move itself is finished. This file lists what is left to confirm, and the changes that make use of having
both halves of the contract in one place. Delete each item once it is done.

## To confirm

- [ ] **The first addon release from the monorepo.** `python release.py`, option 1. Watch the `addon-release`
  run: it is the first upload to CurseForge and Wago from this repository (the secrets were added by hand).
  Check that the GitHub Release becomes the repository's Latest and
  `https://github.com/ntower/altarmy/releases/latest/download/AltArmy_TBC.zip` serves the new zip.
- [ ] **The first Sync release from the monorepo.** `python release.py`, option 4. Check that the `sync-v*`
  release is *not* marked Latest, and that `sync-latest` now carries the new exe
  (`https://github.com/ntower/altarmy/releases/download/sync-latest/altarmy-sync.exe`).
- [ ] **The first `addon-check` run.** It has never run: `npm run setup:dev` had only built Lua 5.1 on Windows.
  If the source build fails on `ubuntu-latest`, install `lua5.1` with apt and set `LUA_51_PATH`
  (`addon/scripts/resolve-lua51.js` reads it first). Then check that a pull request breaking a spec fails it.
- [ ] **The first `site-check` run on an addon-only commit** (e.g. one touching only
  `addon/spec/fixtures/profit_export_v2.txt`): it should run, and `site-deploy` follow it on main.
- [ ] **Delete the old checkout** `C:\Users\Nick\programming\altarmy_tbc` (archived on GitHub; everything in it
  is in `addon/`).

## Changes worth making

In order of value.

### 1. Share the game-data downloads

**Duplication:** both halves download wago.tools DB2 tables and the emulators' world databases:

- the addon's `addon/scripts/generate-recipe-data.py` and `build-recipe-server-facts.py`
- the site's `site/src/altarmy_profit/ingest.py`, `vmangos.py` and `cmangos.py`

The addon already borrows the site's download cache (`site/cache`).

**Change:** one module for the build lookup (`/api/builds/latest`), the table download and its cache, and
the emulator release download, imported by both. It has to stay standard library only, since the addon's
scripts are stdlib only. The site's package could expose it, or it could live in a small root-level
`shared/` folder.

**When:** this is the biggest of these changes, so wait until a game-data change has to touch both
halves anyway.
