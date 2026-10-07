"""After a local ingest of WoW: Forever's game data, regenerate the Alt Army addon's tables built from this
database by the addon's own scripts: the Waylaid Crates (`AltArmy_TBC/Data/Economy/WaylaidCrates.lua`) and
the Craftsman's Writs with their crafting trees (`AltArmy_TBC/Data/Economy/Writs.lua`).

Runs only where it can: Forever, a SQLite database (the scripts read the file) and the addon checked out
next to the site (the monorepo's `addon/`, or `ALTARMY_ADDON_DIR`). The hosted jobs (Postgres, no addon) skip
it. The files then show up as changes to commit under `addon/`, which the pre-commit hook checks too.
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
WRITS_SCRIPT = Path("scripts") / "generate-writs.py"
SCRIPTS = (("Alt Army Waylaid Crates", SCRIPT), ("Alt Army Craftsman's Writs", WRITS_SCRIPT))
REPO_ROOT = Path(__file__).resolve().parents[2]

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


def addon_dir() -> Path:
    """The Alt Army addon checkout: `ALTARMY_ADDON_DIR`, else the monorepo's `addon/` next to the site."""
    env = os.environ.get(ADDON_DIR_ENV)
    return Path(env) if env else REPO_ROOT.parent / "addon"


def _run_script(label: str, script: Path, root: Path, db_file: Path, run: Runner) -> str:
    try:
        result = run(
            [sys.executable, str(script), "--db", str(db_file)],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (OSError, subprocess.SubprocessError) as e:
        return f"{label} not regenerated: {e}"
    output = (result.stdout or result.stderr or "").strip()
    if result.returncode != 0:
        return f"{label} not regenerated: {output or f'exit {result.returncode}'}"
    return f"{label}: {output}"


def regenerate(
    database: db.Database, game_version: str, *, addon: Path | None = None, run: Runner = subprocess.run
) -> str | None:
    """Run the addon's generators against `database`; what happened (one line each), or None when none
    applies here. Never raises: a failure is reported, not fatal to the ingest."""
    if game_version != "forever" or not database.is_sqlite or not database.url.database:
        return None
    root = addon or addon_dir()
    db_file = Path(database.url.database).resolve()
    notes = [
        _run_script(label, root / script, root, db_file, run)
        for label, script in SCRIPTS
        if (root / script).is_file()
    ]
    return "\n".join(notes) if notes else None
