# Unit testing with Busted

This project uses [busted](https://lunarmodules.github.io/busted/) for Lua unit tests.

## Prerequisites

- **Lua 5.1** — same as for luacheck (e.g. [Lua for Windows](https://github.com/rjpcomputing/luaforwindows) at `C:\Program Files (x86)\Lua\5.1`, or set `LUA_51_PATH`).

Busted and its Lua dependencies (say, luassert, mediator_lua, term/system stubs) are **vendored** in `busted-2.1.1/`, so you do **not** need LuaRocks or a system-wide busted install. The folder is git-ignored; set it up once per clone as below.

## Setup (first time or after clone)

From the project root, create the vendored busted tree so `npm test` works.

1. **Download busted and extract**
   - Get [busted v2.1.1](https://github.com/lunarmodules/busted/archive/refs/tags/v2.1.1.zip) and extract the archive so the top-level folder is named `busted-2.1.1` (rename `busted-2.1.1` from the zip if needed).

2. **Add Lua dependencies into `busted-2.1.1/`**
   - **say** — [say v1.4.1](https://github.com/lunarmodules/say/archive/refs/tags/v1.4.1.zip): extract, then copy the `say/` folder from inside `say-1.4.1/src/` into `busted-2.1.1/`.
   - **luassert** — [luassert v1.9.0](https://github.com/lunarmodules/luassert/archive/refs/tags/v1.9.0.zip): extract, then copy all of `luassert-1.9.0/src/` (including `init.lua`, `assert.lua`, `formatters/`, `languages/`, `matchers/`, etc.) into `busted-2.1.1/luassert/`.
   - **mediator_lua** — [mediator_lua](https://github.com/olivine-labs/mediator_lua/archive/refs/heads/master.zip): extract, then copy `mediator_lua-master/src/mediator.lua` into `busted-2.1.1/`.

3. **Add stubs in `busted-2.1.1/`**
   - **term.lua** — create `busted-2.1.1/term.lua` that returns `{ isatty = function() return false end }`.
   - **system.lua** — create `busted-2.1.1/system.lua` that returns `{ gettime = os.time, monotime = os.clock, sleep = function() end }`.

After this, `busted-2.1.1/` should contain the busted core, `say/`, `luassert/`, `mediator.lua`, `term.lua`, and `system.lua`. Then run `npm test`.

## Run tests

```bash
npm test
```

This runs `node scripts/run-busted.js`, which invokes Lua 5.1 with the busted runner on the `AltArmy_TBC` folder (finds all `*_spec.lua` files). You can pass extra busted options:

```bash
npm test -- --verbose
npm test -- AltArmy_TBC/Data/DataStore_spec.lua
npm test -- -t "sometag"
```

## Layout

- **Tests live next to code** — name spec files `*_spec.lua` (e.g. `DataStore_spec.lua` next to `DataStore.lua`). `npm test` runs busted on the `AltArmy_TBC` folder so all `*_spec.lua` files are found recursively.
- **`.busted`** — busted config (verbose, pattern `_spec`, recursive).

## Writing tests

Name specs like `*_spec.lua` and use `describe` / `it` and `assert`:

```lua
describe("MyModule", function()
  it("does something", function()
    assert.are.same(expected, actual)
  end)
end)
```

See the [busted overview](https://lunarmodules.github.io/busted/#overview) and [Defining Tests](https://lunarmodules.github.io/busted/#defining-tests) for more.
