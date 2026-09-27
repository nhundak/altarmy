"""Alt Army Sync's pure parts (`tray.py` is the Windows UI around them): which site it uploads to (the
command line), its settings file, the status line its menu shows, the command that starts it with
Windows, and the check for a newer release (GitHub Releases, `sync-v*` tags). Standard library only."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path, PureWindowsPath

from . import signin

VERSION = "dev"  # the packaged exe's release, set by its entry script (scripts/build_sync.py)
RELEASES_URL = "https://api.github.com/repos/ntower/altarmy-profit/releases?per_page=30"
RELEASE_TAG = "sync-v"
PROD_SERVER = "https://alt-army-prod.web.app"
STAGING_SERVER = "https://alt-army-prod--staging-hn1s06um.web.app"  # the Hosting `staging` preview channel
SETTINGS_DIR = Path.home() / ".altarmy-profit"
STATUS_MAX = 90  # characters of status in the menu
PROBLEMS = ("Upload failed", "Stopped", "Rejected")  # watch.py's log lines that need the user's attention


@dataclass(frozen=True)
class Target:
    """The site the app uploads to. Each one but the live site has its own settings, log, single-instance
    mutex and Start with Windows entry, so a staging copy never touches the live sign-in and both can run."""

    server: str  # the site's URL, no trailing slash
    name: str = ""  # "" for the live site, else "staging" or "dev"
    args: tuple[str, ...] = ()  # the command-line flags that chose it, repeated by Start with Windows

    @property
    def _suffix(self) -> str:
        return f"-{self.name}" if self.name else ""

    @property
    def config_path(self) -> Path:
        return SETTINGS_DIR / f"sync{self._suffix}.json"

    @property
    def log_path(self) -> Path:
        return SETTINGS_DIR / f"sync{self._suffix}.log"

    @property
    def mutex(self) -> str:
        return f"Local\\altarmy-sync{self._suffix}"

    @property
    def run_value(self) -> str:
        return f"altarmy-sync{self._suffix}"

    @property
    def title(self) -> str:
        return f"Alt Army Sync ({self.name})" if self.name else "Alt Army Sync"


PROD = Target(PROD_SERVER)


def parse_args(argv: list[str]) -> Target:
    """The live site by default; `--staging` for the staging site, `--server URL` for another (a dev server).
    A bad command line raises SystemExit (argparse)."""
    parser = argparse.ArgumentParser(
        prog="altarmy-sync", description="Upload WoW SavedVariables to Alt Army."
    )
    where = parser.add_mutually_exclusive_group()
    where.add_argument("--staging", action="store_true", help=f"use the staging site ({STAGING_SERVER})")
    where.add_argument("--server", metavar="URL", help="use another site, e.g. http://127.0.0.1:8600")
    ns = parser.parse_args(argv)
    if ns.staging:
        return Target(STAGING_SERVER, "staging", ("--staging",))
    if ns.server:
        server = ns.server.strip().rstrip("/")
        if not server.startswith(("http://", "https://")):
            parser.error("--server needs an http:// or https:// URL")
        return Target(server, "dev", ("--server", server))
    return PROD


@dataclass(frozen=True)
class TrayConfig:
    email: str | None = None  # the account signed in, shown in the menu
    # Firebase's refresh token for that account (never the password), in plain text in the user's profile;
    # None: not signed in
    refresh_token: str | None = None
    notified_version: str | None = None  # the newest release the user has been told about, told only once

    @property
    def signed_in(self) -> bool:
        return self.email is not None and self.refresh_token is not None


def _text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def load_config(path: Path) -> TrayConfig:
    """The saved sign-in; signed out for a missing or broken file. An old file's API key and server are
    ignored: the app signs in with an email now, and the command line picks the site."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    email, token = _text(data.get("email")), _text(data.get("refresh_token"))
    notified = _text(data.get("notified_version"))
    return TrayConfig(email, token, notified) if email and token else TrayConfig(notified_version=notified)


def save_config(path: Path, config: TrayConfig) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    data = {
        "email": config.email,
        "refresh_token": config.refresh_token,
        "notified_version": config.notified_version,
    }
    tmp.write_text(json.dumps(data), encoding="utf-8")
    tmp.replace(path)


def form_problem(email: str, password: str, confirm: str | None) -> str | None:
    """What is wrong with the sign-in dialog's fields before asking Firebase (`confirm`: the repeated
    password when creating an account, else None); None if nothing."""
    if "@" not in email.strip():
        return "Enter your email address."
    if not password:
        return "Enter your password."
    if confirm is not None:
        if len(password) < 6:
            return "Passwords need at least 6 characters."
        if confirm != password:
            return "The passwords don't match."
    return None


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


def autostart_command(executable: str, *, frozen: bool, args: tuple[str, ...] = ()) -> str:
    """What Windows runs at sign-in: the packaged exe itself, else this module under pythonw (no console),
    with `args` (the target's flags)."""
    if frozen:
        command = f'"{executable}"'
    else:
        command = f'"{PureWindowsPath(executable).with_name("pythonw.exe")}" -m altarmy_profit.tray'
    return " ".join([command, *(f'"{a}"' if " " in a else a for a in args)])


# --- a newer release ------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Release:
    version: str  # "1.2.3", without the tag's prefix
    url: str  # its GitHub page, where the exe is


def parse_version(text: str) -> tuple[int, ...] | None:
    """`sync-v1.2.3` or `1.2.3` as (1, 2, 3); None for anything else (a source run's "dev")."""
    text = text.removeprefix(RELEASE_TAG)
    return tuple(int(part) for part in text.split(".")) if re.fullmatch(r"\d+(\.\d+){2}", text) else None


def latest_release(payload: object) -> Release | None:
    """The highest published (not draft, not prerelease) `sync-v*` release in GitHub's release list; None
    if there is none or the answer is not what GitHub sends."""
    best: tuple[tuple[int, ...], Release] | None = None
    for entry in payload if isinstance(payload, list) else []:
        if not isinstance(entry, dict) or entry.get("draft") is not False:
            continue
        if entry.get("prerelease") is not False:
            continue
        tag, url = entry.get("tag_name"), entry.get("html_url")
        if not (isinstance(tag, str) and tag.startswith(RELEASE_TAG) and isinstance(url, str)):
            continue
        number = parse_version(tag)
        if number is not None and (best is None or number > best[0]):
            best = (number, Release(tag.removeprefix(RELEASE_TAG), url))
    return best[1] if best else None


def newer(current: str, release: Release | None) -> bool:
    """Whether `release` is newer than the running `current` version (never for a source run)."""
    mine = parse_version(current)
    theirs = parse_version(release.version) if release else None
    return mine is not None and theirs is not None and theirs > mine


def check_for_update(current: str, transport: signin.Transport = signin.urllib_transport) -> Release | None:
    """The newest release if it is newer than `current`; None otherwise, and whenever GitHub can't be reached
    or answers something else (it only means no news)."""
    headers = {"User-Agent": f"altarmy-sync/{current}", "Accept": "application/vnd.github+json"}
    try:
        status, body = transport(RELEASES_URL, headers, None)
        payload = json.loads(body) if status == 200 else None
    except (OSError, ValueError):
        return None
    release = latest_release(payload)
    return release if newer(current, release) else None
