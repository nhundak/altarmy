# Next steps after the monorepo move

The site and the addon moved into this repository on 2026-10-03 (`site/`, `addon/`; see `CLAUDE.md`). The
move itself is finished. This file lists what is left to confirm. Delete each item once it is done.

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
- [ ] **The game-data workflow.** Add the `GAME_DATA_TOKEN` secret (a fine-grained token for this repository:
  Contents and Pull requests, read and write), then run `game-data` by hand. Its first run should land Forever
  `1.60.1.70205` and cmangos `2026-10-03` on main; check that site-check and site-deploy follow, and that the
  deploy's ingest loads the new build (the Admin page's jobs). It will not release the addon until the hand-written
  addon work since `addon-v2.2.0` has gone out in a manual release. Close any open `recipe-data/*` PRs and delete
  their branches.
- [ ] **Delete the old checkout** `C:\Users\Nick\programming\altarmy_tbc` (archived on GitHub; everything in it
  is in `addon/`).
