"""The tray app's pure parts (`tray.py` is the Windows UI around them): its settings file, the status line
its menu shows, and the command that starts it with Windows. Standard library only."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path, PureWindowsPath

DEFAULT_SERVER = "https://alt-army-prod.web.app"
CONFIG_PATH = Path.home() / ".altarmy-profit" / "tray.json"
STATUS_MAX = 90  # characters of status in the menu
PROBLEMS = ("Upload failed", "Stopped", "Rejected")  # watch.py's log lines that need the user's attention


@dataclass(frozen=True)
class TrayConfig:
    server: str  # the site's URL, no trailing slash
    key: str | None  # an ak_ API key from the site's Manage tab; stored in plain text in the user's profile


def load_config(path: Path = CONFIG_PATH) -> TrayConfig:
    """The saved settings; defaults (the live site, no key) for a missing or broken file."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    server, key = data.get("server"), data.get("key")
    return TrayConfig(
        server.rstrip("/") if isinstance(server, str) and server.strip() else DEFAULT_SERVER,
        key.strip() if isinstance(key, str) and key.strip() else None,
    )


def save_config(path: Path, config: TrayConfig) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"server": config.server.rstrip("/"), "key": config.key}), encoding="utf-8")
    tmp.replace(path)


@dataclass
class Status:
    """The newest thing the watcher logged, for the tray menu; `problem` while it needs attention."""

    text: str = "Watching for WoW's SavedVariables"
    problem: str | None = None
    history: list[str] = field(default_factory=list)  # newest last, a few lines

    def log(self, message: str, now: datetime | None = None) -> None:
        stamped = f"{(now or datetime.now()):%H:%M} {message}"
        self.text = stamped if len(stamped) <= STATUS_MAX else stamped[: STATUS_MAX - 1] + "…"
        self.problem = message if message.startswith(PROBLEMS) else None
        self.history = [*self.history[-19:], stamped]


def autostart_command(executable: str, *, frozen: bool) -> str:
    """What Windows runs at sign-in: the packaged exe itself, else this module under pythonw (no console)."""
    if frozen:
        return f'"{executable}"'
    pythonw = PureWindowsPath(executable).with_name("pythonw.exe")
    return f'"{pythonw}" -m altarmy_profit.tray'
