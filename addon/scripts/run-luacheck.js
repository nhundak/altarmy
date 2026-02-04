#!/usr/bin/env node
"use strict";
/**
 * Run luacheck from source using Lua 5.1 (Lua for Windows).
 * Requires: Lua 5.1 at "C:\\Program Files (x86)\\Lua\\5.1" (or LUA_51_PATH env).
 * Luacheck source in ./luacheck-src, argparse in ./luacheck-src/argparse.lua.
 */
const path = require("path");
const { execSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const lua51Path = process.env.LUA_51_PATH || "C:\\Program Files (x86)\\Lua\\5.1";
const luaExe = path.join(lua51Path, "lua.exe");
const luacheckSrc = path.join(root, "luacheck-src");
const srcPath = path.join(luacheckSrc, "src");
const binScript = path.join(luacheckSrc, "bin", "luacheck.lua");

const packagePath = [
  path.join(srcPath, "?.lua"),
  path.join(srcPath, "?", "init.lua"),
  path.join(luacheckSrc, "?.lua"),
]
  .join(";")
  .replace(/\\/g, "/");

const args = process.argv.slice(2);
const target = args.length ? args.join(" ") : "AltArmy_TBC";

try {
  execSync(
    `"${luaExe}" -e "package.path='${packagePath};'..package.path" "${binScript}" -q ${target}`,
    { cwd: root, stdio: "inherit", shell: true }
  );
} catch (e) {
  process.exit(e.status || 1);
}
