#!/usr/bin/env node
"use strict";
/**
 * Run busted (Lua unit tests) using Lua 5.1.
 * Uses vendored busted in busted-2.1.1/.
 * Lua is resolved via scripts/resolve-lua51.js (see npm run setup:dev).
 */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const { resolveLua51, missingLua51Message } = require("./resolve-lua51");

const root = path.resolve(__dirname, "..");
const bustedSrc = path.join(root, "busted-2.1.1");
const bootstrap = path.join(root, "scripts", "busted_bootstrap.lua");
const args = process.argv.slice(2);

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

const resolved = resolveLua51(root);
if (!resolved) {
  fail(missingLua51Message(root));
}
if (!fs.existsSync(path.join(bustedSrc, "busted", "runner.lua"))) {
  fail(
    `Vendored busted missing at ${bustedSrc}.\nRun \`npm run setup:dev\` to download it.`
  );
}

const bustedArgs = args.length ? args : [];
const cmd = [
  `"${resolved.luaExe}"`,
  `"${bootstrap}"`,
  ...bustedArgs.map((a) => `"${a}"`),
].join(" ");

try {
  execSync(cmd, { cwd: root, stdio: "inherit", shell: true, env: resolved.env });
} catch (e) {
  process.exit(e.status || 1);
}
