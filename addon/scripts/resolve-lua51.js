"use strict";
/**
 * Resolve Lua 5.1 for npm test / npm run check without per-session env thrashing.
 *
 * Search order for the bin directory:
 *   1. LUA_51_PATH
 *   2. <repo>/.lua51/bin
 *   3. Windows Lua for Windows default paths
 *
 * When <repo>/.lua51/share/lua/5.1 exists, LUA_PATH / LUA_CPATH are prepended
 * so penlight and lua_cliargs resolve for busted.
 */
const fs = require("fs");
const path = require("path");

const WINDOWS_DEFAULTS = [
  "C:\\Program Files (x86)\\Lua\\5.1",
  "C:\\Program Files\\Lua\\5.1",
];

function pathExists(p) {
  try {
    return fs.existsSync(p);
  } catch (_) {
    return false;
  }
}

function luaBinaryNames() {
  return process.platform === "win32" ? ["lua.exe", "lua"] : ["lua", "lua.exe"];
}

function findLuaInDir(binDir) {
  if (!binDir || !pathExists(binDir)) return null;
  for (const name of luaBinaryNames()) {
    const exe = path.join(binDir, name);
    if (pathExists(exe)) return exe;
  }
  return null;
}

function joinLuaPath(parts) {
  return parts.filter(Boolean).join(";");
}

/**
 * @param {string} root repo root
 * @returns {{ binDir: string, luaExe: string, env: NodeJS.ProcessEnv } | null}
 */
function resolveLua51(root) {
  const candidates = [];
  if (process.env.LUA_51_PATH) {
    candidates.push(process.env.LUA_51_PATH);
  }
  candidates.push(path.join(root, ".lua51", "bin"));
  if (process.platform === "win32") {
    candidates.push(...WINDOWS_DEFAULTS);
  }

  let binDir = null;
  let luaExe = null;
  for (const dir of candidates) {
    const found = findLuaInDir(dir);
    if (found) {
      binDir = dir;
      luaExe = found;
      break;
    }
  }
  if (!luaExe) return null;

  const env = { ...process.env };
  const share = path.join(root, ".lua51", "share", "lua", "5.1");
  const lib = path.join(root, ".lua51", "lib", "lua", "5.1");
  if (pathExists(share)) {
    env.LUA_PATH = joinLuaPath([
      path.join(share, "?.lua").replace(/\\/g, "/"),
      path.join(share, "?", "init.lua").replace(/\\/g, "/"),
      env.LUA_PATH,
    ]);
  }
  if (pathExists(lib)) {
    env.LUA_CPATH = joinLuaPath([
      path.join(lib, "?.so").replace(/\\/g, "/"),
      path.join(lib, "?.dll").replace(/\\/g, "/"),
      env.LUA_CPATH,
    ]);
  }
  // So child processes and docs that read LUA_51_PATH stay consistent.
  env.LUA_51_PATH = binDir;
  return { binDir, luaExe, env };
}

function missingLua51Message(root) {
  const setup = "npm run setup:dev";
  return [
    "Lua 5.1 not found.",
    `Run \`${setup}\` from the repo root, or set LUA_51_PATH to a directory containing lua/lua.exe.`,
    `Expected project tree: ${path.join(root, ".lua51", "bin")}`,
  ].join("\n");
}

module.exports = {
  resolveLua51,
  missingLua51Message,
  findLuaInDir,
};
