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
- [ ] **Delete the old checkout** `C:\Users\Nick\programming\altarmy_tbc` (archived on GitHub; everything in it
  is in `addon/`).

## Changes worth making

In order of value. The first three are small and close gaps the two-repo setup hid; they fit in one change.

### 1. Run the site's tests when the addon's formats change

**Gap:** `site/tests/addon_fixtures.py` reads the addon's golden files, but `site-check` runs only on
`site/**` changes. An addon commit that changes the export or scan format, and updates its fixture, never
runs the site parser tests that would catch the mismatch.

**Change:** in `.github/workflows/site-check.yml`, add to both `paths` lists:

```yaml
- "addon/spec/fixtures/**"
- "addon/AltArmy_TBC/Data/ProfitExport.lua"
- "addon/AltArmy_TBC/Data/Auctions/AuctionBook.lua"
- "addon/AltArmy_TBC/Data/Auctions/AuctionScan.lua"
```

**Trade-off:** `site-deploy` follows a passing `site-check` on main, so such a commit also redeploys the site
with no code change. That is harmless. If it becomes noise, have `site-deploy` skip when
`git diff --quiet HEAD~1 -- site` holds.

**Done when:** a commit touching only `addon/spec/fixtures/profit_export_v2.txt` triggers `site-check`.

### 2. CI for the addon

**Gap:** the addon has no CI. Its specs (busted, about 2800) and luacheck only run on a developer's machine.

**Change:** `.github/workflows/addon-check.yml`, on push and pull request with `paths: ["addon/**",
".github/workflows/addon-check.yml"]`, `defaults.run.working-directory: addon`: `npm ci`, `npm run setup:dev`,
`npm test`, `npm run check`.

**Unknown:** `npm run setup:dev` (`addon/scripts/setup-dev-tools.js`) builds Lua 5.1, busted and luacheck
locally. It has only run on Windows. Try it once on `ubuntu-latest`. If the build is slow, cache
`addon/.lua51`, `addon/busted-2.1.1` and `addon/luacheck-src` keyed on the script's hash, or install
`lua5.1` with apt and point `LUA_51_PATH` at it (`resolve-lua51.js` reads it first).

**Done when:** a pull request that breaks a spec fails `addon-check`.

### 3. The addon and the site agree on the game versions

**Gap:** the client interface numbers live in two places: `addon/AltArmy_TBC/AltArmy_TBC.toc`
(`## Interface: 20506, 16001`) and `site/src/altarmy_profit/versions.py` (each `GameVersion`'s interface).
When a game patch moves one, nothing says the other needs updating.

**Change:** a pytest in `site/tests/` that reads the TOC's `## Interface:` line (path relative to the
repository, like `tests/addon_fixtures.py`) and asserts it lists exactly the interface numbers of the
versions in `versions.VERSIONS`.

**Done when:** changing either number alone fails `site-check` (so item 1's paths should also list the TOC).

### 4. Share the game-data downloads

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

### 5. Keep server code out of Alt Army Sync

**Gap:** Alt Army Sync is built from `site/src/altarmy_profit` (`tray`, `tray_core`, `watch`, `signin`,
`wowfiles`, `versions`). Only a comment ("standard library only") and a hand-kept exclusion list in
`site/scripts/build_sync.py` keep the server's packages out of the exe. A stray import would be bundled
silently.

**Change:** a pytest that walks those modules' imports (`ast`) and allows only the standard library, each
other, and the `tray` extras (`pystray`, `PIL`).

**Done when:** adding `from . import db` to `watch.py` fails the test.
