#!/usr/bin/env node
// Point git at the monorepo's tracked hooks in <repo root>/.githooks/ (runs on `npm install` via the `prepare`
// script). Does nothing outside a git checkout, e.g. in an extracted addon zip.
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const addon = path.join(__dirname, "..");
let root;
try {
  root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: addon, stdio: ["ignore", "pipe", "ignore"] })
    .toString()
    .trim();
} catch {
  process.exit(0);
}
if (!root || !fs.existsSync(path.join(root, ".githooks"))) {
  process.exit(0);
}
try {
  execFileSync("git", ["config", "core.hooksPath", ".githooks"], { cwd: root, stdio: "inherit" });
  console.log(
    "Git hooks enabled from .githooks/ (pre-commit: Waylaid Crates and Craftsman's Writs data checks for addon/)."
  );
} catch (err) {
  console.warn(`Could not enable git hooks: ${err.message}`);
}
