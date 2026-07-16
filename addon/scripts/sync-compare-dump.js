#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const localPath = path.join(root, ".cursor", "local.json");
const outDir = path.join(root, "debug", "compare-dump-source");
const outFile = path.join(outDir, "AltArmy_TBC.lua");

function readLocalConfig() {
  if (!fs.existsSync(localPath)) {
    console.error(
      "Missing .cursor/local.json — copy .cursor/local.json.example and set wowSavedVariables."
    );
    process.exit(1);
  }
  let config;
  try {
    config = JSON.parse(fs.readFileSync(localPath, "utf8"));
  } catch (err) {
    console.error("Invalid .cursor/local.json:", err.message);
    process.exit(1);
  }
  const src = config.wowSavedVariables;
  if (!src || typeof src !== "string") {
    console.error(".cursor/local.json must include wowSavedVariables (string path).");
    process.exit(1);
  }
  return src;
}

function countDumpEntries(text, marker) {
  const idx = text.indexOf(marker);
  if (idx === -1) return 0;
  const slice = text.slice(idx);
  const matches = slice.match(/\["timestamp"\]\s*=/g);
  return matches ? matches.length : 0;
}

const src = readLocalConfig();
if (!fs.existsSync(src)) {
  console.error("SavedVariables file not found:", src);
  console.error("Log in, capture a dump (/altarmy debug on → Dump → /reload), then retry.");
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });
fs.copyFileSync(src, outFile);

const text = fs.readFileSync(outFile, "utf8");
const dumpCount = countDumpEntries(text, '["comparePanelDumps"]');
const guildUndecodableCount = countDumpEntries(text, '["guildShareUndecodableDumps"]');
console.log("Synced:", outFile);
console.log("Source:", src);
console.log("comparePanelDumps entries (approx):", dumpCount);
console.log("guildShareUndecodableDumps entries (approx):", guildUndecodableCount);
if (dumpCount === 0 && guildUndecodableCount === 0) {
  console.warn(
    "No dumps found — compare: debug on → Dump; guild share: verbose on + wait for undecodable → /reload."
  );
}
