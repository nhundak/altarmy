#!/usr/bin/env node
"use strict";
/**
 * Compile every addon .lua file with Lua 5.1 to catch bytecode limits that
 * luacheck cannot see — especially "main function has more than 200 local variables".
 *
 * Usage: node scripts/check-lua51-compile.js [path...]
 * Default target: AltArmy_TBC
 */
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { resolveLua51, missingLua51Message } = require("./resolve-lua51");

const root = path.resolve(__dirname, "..");
const args = process.argv.slice(2);
const targets = args.length ? args : ["AltArmy_TBC"];

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

function collectLuaFiles(targetPath) {
  const abs = path.resolve(root, targetPath);
  if (!fs.existsSync(abs)) {
    fail(`Path not found: ${targetPath}`);
  }
  const out = [];
  const walk = (dir) => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      if (ent.name === "Libs" || ent.name === "node_modules") continue;
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(full);
      } else if (ent.isFile() && ent.name.toLowerCase().endsWith(".lua")) {
        out.push(full);
      }
    }
  };
  const st = fs.statSync(abs);
  if (st.isDirectory()) walk(abs);
  else if (st.isFile()) out.push(abs);
  return out;
}

const resolved = resolveLua51(root);
if (!resolved) {
  fail(missingLua51Message(root));
}

const files = [];
for (const t of targets) {
  files.push(...collectLuaFiles(t));
}
files.sort();

// loadfile compiles without executing. Fail on first error with a clear prefix.
const relPaths = files.map((f) => path.relative(root, f).replace(/\\/g, "/"));
const luaChunk = `
local files = {${relPaths.map((p) => JSON.stringify(p)).join(",")}}
local failed = 0
for i = 1, #files do
  local path = files[i]
  local fn, err = loadfile(path)
  if not fn then
    failed = failed + 1
    io.stderr:write("LUA51_COMPILE: " .. tostring(err) .. "\\n")
  end
end
if failed > 0 then
  io.stderr:write(string.format("LUA51_COMPILE: %d file(s) failed to compile under Lua 5.1\\n", failed))
  os.exit(1)
end
print(string.format("LUA51_COMPILE: %d file(s) ok", #files))
`;

const result = spawnSync(resolved.luaExe, ["-e", luaChunk], {
  cwd: root,
  env: resolved.env,
  encoding: "utf8",
});

if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.status !== 0) {
  process.exit(result.status || 1);
}
