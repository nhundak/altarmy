#!/usr/bin/env node
"use strict";
/**
 * Run luacheck from source using Lua 5.1.
 * Requires luacheck-src/ (see npm run setup:dev).
 * Lua is resolved via scripts/resolve-lua51.js.
 */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const { resolveLua51, missingLua51Message } = require("./resolve-lua51");

const root = path.resolve(__dirname, "..");
const luacheckSrc = path.join(root, "luacheck-src");
const srcPath = path.join(luacheckSrc, "src");
const binScript = path.join(luacheckSrc, "bin", "luacheck.lua");
const args = process.argv.slice(2);
const target = args.length ? args.join(" ") : "AltArmy_TBC";

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

const resolved = resolveLua51(root);
if (!resolved) {
  fail(missingLua51Message(root));
}
if (!fs.existsSync(binScript)) {
  fail(
    `Luacheck source missing at ${binScript}.\nRun \`npm run setup:dev\` to download it.`
  );
}

const packagePath = [
  path.join(srcPath, "?.lua"),
  path.join(srcPath, "?", "init.lua"),
  path.join(luacheckSrc, "?.lua"),
]
  .join(";")
  .replace(/\\/g, "/");

try {
  execSync(
    `"${resolved.luaExe}" -e "package.path='${packagePath};'..package.path" "${binScript}" -q ${target}`,
    { cwd: root, stdio: "inherit", shell: true, env: resolved.env }
  );
} catch (e) {
  process.exit(e.status || 1);
}
