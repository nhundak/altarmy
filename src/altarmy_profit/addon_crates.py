"""After a local ingest of WoW: Forever's game data, regenerate the Alt Army addon's Waylaid Crates table
(`AltArmy_TBC/Data/Economy/WaylaidCrates.lua`), which the addon's own script builds from this database.

Runs only where it can: Forever, a SQLite database (the script reads the file) and the addon checked out
next to this repo (`../altarmy_tbc`, or `ALTARMY_ADDON_DIR`). The hosted jobs (Postgres, no addon) skip it.
The file then shows up as a change to commit in the addon repo, whose pre-commit hook checks it too.
"""

from __future__ import annotations

import os
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

from . import db

ADDON_DIR_ENV = "ALTARMY_ADDON_DIR"
SCRIPT = Path("scripts") / "generate-waylaid-crates.py"
REPO_ROOT = Path(__file__).resolve().parents[2]

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


def addon_dir() -> Path:
    """The Alt Army addon checkout: `ALTARMY_ADDON_DIR`, else `altarmy_tbc` next to this repo."""
    env = os.environ.get(ADDON_DIR_ENV)
    return Path(env) if env else REPO_ROOT.parent / "altarmy_tbc"


def regenerate(
    database: db.Database, game_version: str, *, addon: Path | None = None, run: Runner = subprocess.run
) -> str | None:
    """Run the addon's generator against `database`; what happened, or None when it doesn't apply here.
    Never raises: a failure is reported, not fatal to the ingest."""
    if game_version != "forever" or not database.is_sqlite or not database.url.database:
        return None
    root = addon or addon_dir()
    script = root / SCRIPT
    if not script.is_file():
        return None
    db_file = Path(database.url.database).resolve()
    try:
        result = run(
            [sys.executable, str(script), "--db", str(db_file)],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (OSError, subprocess.SubprocessError) as e:
        return f"Alt Army Waylaid Crates not regenerated: {e}"
    output = (result.stdout or result.stderr or "").strip()
    if result.returncode != 0:
        return f"Alt Army Waylaid Crates not regenerated: {output or f'exit {result.returncode}'}"
    return f"Alt Army Waylaid Crates: {output}"
