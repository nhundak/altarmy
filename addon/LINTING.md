# Linting and static analysis (Luacheck)

This project uses [Luacheck](https://github.com/lunarmodules/luacheck) for linting and static analysis of Lua code. Configuration is in [`.luacheckrc`](.luacheckrc) at the repo root.

## One-time setup

```bash
npm run setup:dev
```

Same bootstrap as tests: resolves Lua 5.1 under `.lua51/` and downloads `luacheck-src/` (plus argparse). No system-wide luacheck install is required.

## Run Luacheck

```bash
npm run check
# or
npm run lint
```

`npm run check` runs **luacheck** and a **Lua 5.1 compile pass** (`npm run check:compile`). The compile pass catches bytecode limits luacheck cannot see — especially `main function has more than 200 local variables` in large tab files.

Or run pieces separately:

```bash
node scripts/run-luacheck.js AltArmy_TBC
node scripts/check-lua51-compile.js AltArmy_TBC
```

Luacheck reports undefined globals, unused variables, line length, etc. Add any new WoW API or addon globals to `.luacheckrc` under `read_globals` or `globals` as needed.
