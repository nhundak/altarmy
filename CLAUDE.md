# CLAUDE.md

Conventions for AI agents working in the `altarmy` monorepo: Alt Army, one product in two parts.

## Layout

- `site/` – the Alt Army site (`altarmy-profit`: the Python API and CLI jobs, the React front end, and Alt Army
  Sync, the Windows uploader). Its own `CLAUDE.md`, README, venv (`site/.venv`), `package.json` (the dev loop)
  and `frontend/node_modules`. Every command in its docs runs from `site/`.
- `addon/` – the Alt Army addon (`AltArmy_TBC/`, Lua 5.1) with its specs, data scripts and Lua tooling. Its own
  `CLAUDE.md`, README and `package.json`; every `npm` command in its docs runs from `addon/`.
- `.github/workflows/` – all workflows, prefixed by product: `site-check` (on `site/**` changes and the
  addon's side of the contract below), `site-deploy` (prod, after `site-check` on main; staging by hand),
  `sync-release` (`sync-v*` tags), `addon-check` (on `addon/**` changes: `npm run setup:dev`, `npm test`,
  `npm run check` on Ubuntu, the Lua tools cached), `addon-release` (`addon-v*` tags: CurseForge, Wago and a
  GitHub Release) and `addon-recipe-data` (daily PRs on `recipe-data/*`).
- `.githooks/pre-commit` – the addon's Waylaid Crates check, run only for commits touching `addon/` (enabled by
  `npm install` in `addon/`, which sets `core.hooksPath` at this root).
- `.claude/skills/` – the addon's skills (paths inside them are relative to `addon/`).

Nothing is shared between the two toolchains: no root `package.json`, `pyproject.toml` or venv.

## The contract between them

The addon writes what the site reads, and the golden files live with the addon:

- `addon/AltArmy_TBC/Data/ProfitExport.lua` writes the `AAX1` export; `site/src/altarmy_profit/paste.py` decodes
  it; `addon/spec/fixtures/profit_export_v2.txt` is the golden string both test against.
- `addon/AltArmy_TBC/Data/Auctions/AuctionScan.lua` and `AuctionBook.lua` write `AltArmyTBC_AuctionBook`;
  `site/src/altarmy_profit/book.py` reads it; `addon/spec/fixtures/auction_book_v1.lua` is the golden file.
- `AltArmy_TBC.lua` (the addon's main SavedVariable) is read by `site/src/altarmy_profit/altarmy.py`.
- `site/tests/addon_fixtures.py` names the golden files for the site's tests, so a format change is one commit
  that changes the writer, the reader and the fixture, and `site-check` fails if they disagree. `site-check` also
  runs on commits touching only those addon files (the fixtures, the writers, the TOC), so such a commit redeploys
  the site unchanged.
- The TOC's `## Interface:` lists exactly the interfaces of `site/src/altarmy_profit/versions.py`'s versions
  (`site/tests/test_versions.py`): a game patch moving one updates both.
- `addon/scripts/generate-waylaid-crates.py` reads the site's development database (`site/data/altarmy-profit.sqlite`),
  and `site`'s ingest regenerates the addon's Waylaid Crates table (`site/src/altarmy_profit/addon_crates.py`).

## Releases

`python release.py` (at this root; `--dry-run` to see what it would do) asks which part to release and does the
steps below, bumping the addon's version in its TOC, `Core.lua`, `package.json` and `package-lock.json`.

- Addon: tag `addon-vX.Y.Z` (the version in `addon/AltArmy_TBC/AltArmy_TBC.toc`). Only addon releases are the
  repository's Latest, so `releases/latest/download/AltArmy_TBC.zip` is always the addon.
- Alt Army Sync: tag `sync-vX.Y.Z`. Its release is created with `--latest=false`, and the exe is copied onto the
  rolling `sync-latest` release that the Manage page links.
- The site deploys to prod from `main` whenever `site-check` ran and passed, i.e. when something under `site/`
  (or the addon's side of the contract) changed.
