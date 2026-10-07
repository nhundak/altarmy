"""Build Alt Army Sync as one Windows exe: dist/altarmy-sync.exe.

Usage (Windows, in the venv with the tray and build-tray extras: pip install -e ".[tray,build-tray]"):
    python scripts/build_sync.py [--version 1.2.3]
CI does the same on a `sync-v*` tag (.github/workflows/sync.yml), passing the tag's version, and attaches the
exe to a GitHub Release. The exe checks GitHub for a newer release; built without --version it never does.
The exe is unsigned, so Windows SmartScreen warns the first time it runs.
"""

import argparse
import sys
import tempfile
from pathlib import Path

import PyInstaller.__main__

from altarmy_site import tray, tray_core

ROOT = Path(__file__).resolve().parents[1]
NAME = "altarmy-sync"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build dist/altarmy-sync.exe.")
    parser.add_argument("--version", default="dev", help="the release, e.g. 1.2.3 (default: dev)")
    version = parser.parse_args().version
    if version != "dev" and tray_core.parse_version(version) is None:
        parser.error("--version needs three numbers, e.g. 1.2.3")
    if sys.platform != "win32":
        sys.exit("Alt Army Sync is built on Windows.")
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        icon = work / "icon.ico"
        tray._icon_image().save(icon, sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
        entry = work / "tray_entry.py"
        entry.write_text(
            "from altarmy_site import tray_core\n"
            f"tray_core.VERSION = {version!r}\n"
            "from altarmy_site.tray import main\n\nmain()\n",
            encoding="utf-8",
        )
        PyInstaller.__main__.run(
            [
                str(entry),
                "--name",
                NAME,
                "--onefile",
                "--windowed",
                "--noconfirm",
                "--clean",
                "--icon",
                str(icon),
                "--distpath",
                str(ROOT / "dist"),
                "--workpath",
                str(work / "build"),
                "--specpath",
                str(work),
                # the tray needs only the watcher: keep the server's packages (and numpy, which Pillow would
                # pull in) out of the exe, and Pillow's extensions the icon doesn't use (AVIF alone is 4 MB)
                *[
                    f"--exclude-module={m}"
                    for m in (
                        "sqlalchemy",
                        "alembic",
                        "fastapi",
                        "uvicorn",
                        "psycopg",
                        "numpy",
                        *tray_core.PILLOW_UNUSED,
                    )
                ],
            ]
        )
    print(f"Built {ROOT / 'dist' / (NAME + '.exe')} ({version})")


if __name__ == "__main__":
    main()
