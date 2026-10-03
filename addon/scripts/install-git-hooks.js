#!/usr/bin/env node
// Point git at the repo's tracked hooks in .githooks/ (runs on `npm install` via the `prepare` script).
// Does nothing outside a git checkout, e.g. in an extracted addon zip.
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
if (!fs.existsSync(path.join(root, ".git"))) {
  process.exit(0);
}
try {
  execFileSync("git", ["config", "core.hooksPath", ".githooks"], { cwd: root, stdio: "inherit" });
  console.log("Git hooks enabled from .githooks/ (pre-commit: Waylaid Crates data check).");
} catch (err) {
  console.warn(`Could not enable git hooks: ${err.message}`);
}
