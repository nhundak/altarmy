#!/usr/bin/env node
"use strict";
/**
 * Bootstrap local Lua 5.1 tooling used by npm test / npm run check:
 *   .lua51/          — Lua 5.1 + penlight + lua_cliargs (gitignored)
 *   busted-2.1.1/    — vendored busted + deps (gitignored)
 *   luacheck-src/    — vendored luacheck + argparse (gitignored)
 *
 * Safe to re-run; skips steps that are already present.
 */
const fs = require("fs");
const path = require("path");
const https = require("https");
const http = require("http");
const { spawnSync } = require("child_process");
const { resolveLua51 } = require("./resolve-lua51");

const root = path.resolve(__dirname, "..");
const tmpDir = path.join(root, ".setup-dev-tmp");

const URLS = {
  lua515: "https://www.lua.org/ftp/lua-5.1.5.tar.gz",
  busted: "https://github.com/lunarmodules/busted/archive/refs/tags/v2.1.1.zip",
  say: "https://github.com/lunarmodules/say/archive/refs/tags/v1.4.1.zip",
  luassert: "https://github.com/lunarmodules/luassert/archive/refs/tags/v1.9.0.zip",
  mediator: "https://github.com/olivine-labs/mediator_lua/archive/refs/heads/master.zip",
  luacheck: "https://github.com/lunarmodules/luacheck/archive/refs/tags/v1.2.0.zip",
  argparse: "https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua",
  penlight: "https://github.com/lunarmodules/Penlight/archive/refs/tags/1.14.0.zip",
  cliargs: "https://github.com/amireh/lua_cliargs/archive/refs/tags/v3.0.2.zip",
};

function log(msg) {
  console.log(`[setup:dev] ${msg}`);
}

function fail(msg) {
  console.error(`[setup:dev] ${msg}`);
  process.exit(1);
}

function exists(p) {
  try {
    return fs.existsSync(p);
  } catch (_) {
    return false;
  }
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function rmrf(p) {
  fs.rmSync(p, { recursive: true, force: true });
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    ensureDir(path.dirname(dest));
    const file = fs.createWriteStream(dest);
    const get = url.startsWith("https:") ? https.get : http.get;
    const req = get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        file.close();
        fs.unlinkSync(dest);
        download(res.headers.location, dest).then(resolve, reject);
        return;
      }
      if (res.statusCode !== 200) {
        file.close();
        fs.unlinkSync(dest);
        reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        return;
      }
      res.pipe(file);
      file.on("finish", () => file.close(() => resolve(dest)));
    });
    req.on("error", (err) => {
      try {
        file.close();
        fs.unlinkSync(dest);
      } catch (_) {
        /* ignore */
      }
      reject(err);
    });
  });
}

function run(cmd, opts = {}) {
  const result = spawnSync(cmd, {
    shell: true,
    cwd: opts.cwd || root,
    stdio: opts.stdio || "inherit",
    env: opts.env || process.env,
  });
  if (result.status !== 0) {
    fail(`Command failed (${result.status}): ${cmd}`);
  }
}

function unzip(zipPath, destDir) {
  ensureDir(destDir);
  if (process.platform === "win32") {
    run(
      `powershell -NoProfile -Command "Expand-Archive -Force -Path '${zipPath}' -DestinationPath '${destDir}'"`
    );
  } else {
    run(`unzip -qo "${zipPath}" -d "${destDir}"`);
  }
}

function untarGz(archive, destDir) {
  ensureDir(destDir);
  run(`tar -xzf "${archive}" -C "${destDir}"`);
}

function writeFile(p, contents) {
  ensureDir(path.dirname(p));
  fs.writeFileSync(p, contents);
}

async function ensureBusted() {
  const bustedRoot = path.join(root, "busted-2.1.1");
  const marker = path.join(bustedRoot, "busted", "runner.lua");
  if (exists(marker) && exists(path.join(bustedRoot, "say", "init.lua"))) {
    log("busted-2.1.1 already present");
    return;
  }
  log("Downloading busted + dependencies…");
  ensureDir(tmpDir);
  const bustedZip = path.join(tmpDir, "busted.zip");
  const sayZip = path.join(tmpDir, "say.zip");
  const luassertZip = path.join(tmpDir, "luassert.zip");
  const mediatorZip = path.join(tmpDir, "mediator.zip");
  await Promise.all([
    download(URLS.busted, bustedZip),
    download(URLS.say, sayZip),
    download(URLS.luassert, luassertZip),
    download(URLS.mediator, mediatorZip),
  ]);

  const extract = path.join(tmpDir, "extract-busted");
  rmrf(extract);
  ensureDir(extract);
  unzip(bustedZip, extract);
  unzip(sayZip, extract);
  unzip(luassertZip, extract);
  unzip(mediatorZip, extract);

  rmrf(bustedRoot);
  fs.renameSync(path.join(extract, "busted-2.1.1"), bustedRoot);
  fs.cpSync(path.join(extract, "say-1.4.1", "src", "say"), path.join(bustedRoot, "say"), {
    recursive: true,
  });
  fs.cpSync(
    path.join(extract, "luassert-1.9.0", "src"),
    path.join(bustedRoot, "luassert"),
    { recursive: true }
  );
  fs.cpSync(
    path.join(extract, "mediator_lua-master", "src", "mediator.lua"),
    path.join(bustedRoot, "mediator.lua")
  );
  writeFile(
    path.join(bustedRoot, "term.lua"),
    "return { isatty = function() return false end }\n"
  );
  writeFile(
    path.join(bustedRoot, "system.lua"),
    "return { gettime = os.time, monotime = os.clock, sleep = function() end }\n"
  );
  log("busted-2.1.1 ready");
}

async function ensureLuacheck() {
  const luacheckRoot = path.join(root, "luacheck-src");
  const marker = path.join(luacheckRoot, "bin", "luacheck.lua");
  if (exists(marker) && exists(path.join(luacheckRoot, "argparse.lua"))) {
    log("luacheck-src already present");
    return;
  }
  log("Downloading luacheck + argparse…");
  ensureDir(tmpDir);
  const zip = path.join(tmpDir, "luacheck.zip");
  const argparseDest = path.join(tmpDir, "argparse.lua");
  await Promise.all([download(URLS.luacheck, zip), download(URLS.argparse, argparseDest)]);

  const extract = path.join(tmpDir, "extract-luacheck");
  rmrf(extract);
  ensureDir(extract);
  unzip(zip, extract);

  rmrf(luacheckRoot);
  // Upstream archive top-level is luacheck-1.2.0
  const srcTree = path.join(extract, "luacheck-1.2.0");
  if (!exists(srcTree)) {
    fail(`Unexpected luacheck archive layout under ${extract}`);
  }
  fs.renameSync(srcTree, luacheckRoot);
  fs.cpSync(argparseDest, path.join(luacheckRoot, "argparse.lua"));
  log("luacheck-src ready");
}

async function ensureLuaRocksLibs() {
  const share = path.join(root, ".lua51", "share", "lua", "5.1");
  const hasPenlight = exists(path.join(share, "pl", "init.lua"));
  const hasCliargs = exists(path.join(share, "cliargs.lua"));
  if (hasPenlight && hasCliargs) {
    log("penlight + lua_cliargs already present in .lua51");
    return;
  }
  log("Downloading penlight + lua_cliargs into .lua51…");
  ensureDir(tmpDir);
  const penZip = path.join(tmpDir, "penlight.zip");
  const cliZip = path.join(tmpDir, "cliargs.zip");
  await Promise.all([download(URLS.penlight, penZip), download(URLS.cliargs, cliZip)]);
  const extract = path.join(tmpDir, "extract-rocks");
  rmrf(extract);
  ensureDir(extract);
  unzip(penZip, extract);
  unzip(cliZip, extract);
  ensureDir(share);
  if (!hasPenlight) {
    fs.cpSync(path.join(extract, "Penlight-1.14.0", "lua", "pl"), path.join(share, "pl"), {
      recursive: true,
    });
  }
  if (!hasCliargs) {
    const cliSrc = path.join(extract, "lua_cliargs-3.0.2", "src");
    // Package may ship as src/cliargs.lua or src/cliargs/...
    if (exists(path.join(cliSrc, "cliargs.lua"))) {
      fs.cpSync(path.join(cliSrc, "cliargs.lua"), path.join(share, "cliargs.lua"));
    }
    if (exists(path.join(cliSrc, "cliargs"))) {
      fs.cpSync(path.join(cliSrc, "cliargs"), path.join(share, "cliargs"), { recursive: true });
    }
  }
  log("Lua rocks libs ready");
}

function ensureLuaExeShim(binDir) {
  const lua = path.join(binDir, "lua");
  const luaExe = path.join(binDir, "lua.exe");
  if (process.platform !== "win32" && exists(lua) && !exists(luaExe)) {
    try {
      fs.symlinkSync("lua", luaExe);
    } catch (_) {
      fs.copyFileSync(lua, luaExe);
    }
  }
}

async function ensureLua51() {
  if (resolveLua51(root)) {
    const bin = path.join(root, ".lua51", "bin");
    if (exists(bin)) ensureLuaExeShim(bin);
    log("Lua 5.1 already available");
    await ensureLuaRocksLibs();
    return;
  }

  if (process.platform === "win32") {
    fail(
      [
        "Lua 5.1 not found.",
        "Install Lua for Windows (e.g. winget install rjpcomputing.luaforwindows),",
        "or place a Lua 5.1 build under .lua51/bin, then re-run npm run setup:dev.",
      ].join("\n")
    );
  }

  log("Building Lua 5.1.5 into .lua51…");
  ensureDir(tmpDir);
  const archive = path.join(tmpDir, "lua-5.1.5.tar.gz");
  await download(URLS.lua515, archive);
  const extract = path.join(tmpDir, "extract-lua");
  rmrf(extract);
  ensureDir(extract);
  untarGz(archive, extract);
  const src = path.join(extract, "lua-5.1.5");
  const platform = process.platform === "darwin" ? "macosx" : "linux";
  run(`make ${platform}`, { cwd: src });
  const prefix = path.join(root, ".lua51");
  run(`make install INSTALL_TOP="${prefix}"`, { cwd: src });
  ensureLuaExeShim(path.join(prefix, "bin"));
  await ensureLuaRocksLibs();
  log("Lua 5.1 ready at .lua51");
}

async function main() {
  log("Bootstrapping local Lua test/lint tooling…");
  ensureDir(tmpDir);
  try {
    await ensureLua51();
    await ensureBusted();
    await ensureLuacheck();
  } finally {
    rmrf(tmpDir);
  }

  const resolved = resolveLua51(root);
  if (!resolved) {
    fail("Setup finished but Lua 5.1 still not resolvable.");
  }
  if (!exists(path.join(root, "busted-2.1.1", "busted", "runner.lua"))) {
    fail("Setup finished but busted-2.1.1 is incomplete.");
  }
  if (!exists(path.join(root, "luacheck-src", "bin", "luacheck.lua"))) {
    fail("Setup finished but luacheck-src is incomplete.");
  }

  log("Done. You can run: npm test && npm run check");
  log(`Using Lua: ${resolved.luaExe}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
