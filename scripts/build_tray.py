"""Build the tray uploader as one Windows exe: dist/altarmy-profit-tray.exe.

Usage (Windows, in the venv with the tray and build-tray extras: pip install -e ".[tray,build-tray]"):
    python scripts/build_tray.py
CI does the same on a `tray-v*` tag (.github/workflows/tray.yml) and attaches the exe to a GitHub Release.
The exe is unsigned, so Windows SmartScreen warns the first time it runs.
"""

import sys
import tempfile
from pathlib import Path

import PyInstaller.__main__

from altarmy_profit import tray

ROOT = Path(__file__).resolve().parents[1]
NAME = "altarmy-profit-tray"


def main() -> None:
    if sys.platform != "win32":
        sys.exit("The tray uploader is built on Windows.")
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        icon = work / "icon.ico"
        tray._icon_image().save(icon, sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
        entry = work / "tray_entry.py"
        entry.write_text("from altarmy_profit.tray import main\n\nmain()\n", encoding="utf-8")
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
                # pull in) out of the exe
                *[
                    f"--exclude-module={m}"
                    for m in ("sqlalchemy", "alembic", "fastapi", "uvicorn", "psycopg", "numpy")
                ],
            ]
        )
    print(f"Built {ROOT / 'dist' / (NAME + '.exe')}")


if __name__ == "__main__":
    main()
