# Unit testing with Busted

This project uses [busted](https://lunarmodules.github.io/busted/) for Lua unit tests.

## One-time setup

From the repo root:

```bash
npm run setup:dev
```

This installs (into gitignored folders):

- `.lua51/` — Lua 5.1 plus penlight / lua_cliargs (builds Lua from source on macOS/Linux; on Windows uses Lua for Windows if installed)
- `busted-2.1.1/` — vendored busted + dependencies
- `luacheck-src/` — vendored luacheck (also used by `npm run check`)

After that, `npm test` and `npm run check` work with **no** `LUA_51_PATH` required.

Optional override: set `LUA_51_PATH` to a directory containing `lua` / `lua.exe`.

## Run tests

```bash
npm test
```

Pass busted options after `--`:

```bash
npm test -- --verbose
npm test -- --filter=GetDefaultListSort
```

## Layout

- Specs live under `spec/` as `*_spec.lua`.
- `.busted` configures verbose mode, the `_spec` pattern, and `ROOT = { "spec" }`.
