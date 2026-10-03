"""Where the game data comes from, shared by the site and the addon: wago.tools' DB2 tables, the emulators'
world databases, and the pins (`data/game-data.json`) saying which build and which release the committed
files were made from.

Standard library only, with no imports from the package: the addon's scripts load this file by its path
(`addon/scripts/generate-recipe-data.py`, `build-recipe-server-facts.py`), and the monorepo's
`game_data.py` drives both halves with it.

The cache (`.cache/` at the repository root locally, `/tmp/cache` in the hosted jobs) holds
`wago/<build>/<table>.csv` and `emulators/<emulator>/<release>/<world database>`.
"""

from __future__ import annotations

import json
import os
import shutil
import urllib.error
import urllib.request
import zipfile
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path

LATEST_URL = "https://wago.tools/api/builds/latest"
TABLE_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "altarmy-game-data/1.0"
# Relative to the working directory, like versions.DATA_DIR: the site runs from site/, the image from /app
PINS = Path("data") / "game-data.json"
# The repository root's cache, for local runs (this file is site/src/altarmy_profit/gamedata.py)
REPO_CACHE = Path(__file__).resolve().parents[3] / ".cache"

Fetch = Callable[[str], bytes]


@dataclass(frozen=True)
class Emulator:
    name: str
    title: str
    release_url: str  # GitHub's JSON for the rolling release that carries the SQLite dump
    world_db: str  # the SQLite file inside the dump's zip

    def asset(self, assets: list[dict[str, object]]) -> tuple[str, str] | None:
        """(release id, download URL) of the SQLite dump among a release's assets: cmangos' by its upload
        date, vmangos' by its db-sqlite-<commit> file name."""
        for a in assets:
            name = str(a["name"])
            if self.name == "cmangos" and name == "tbc-sqlite-db.zip":
                return str(a["updated_at"])[:10], str(a["browser_download_url"])
            if self.name == "vmangos" and name.startswith("db-sqlite-") and name.endswith(".zip"):
                return name.removesuffix(".zip"), str(a["browser_download_url"])
        return None


EMULATORS = {
    "vmangos": Emulator(
        "vmangos",
        "vmangos",
        "https://api.github.com/repos/vmangos/core/releases/tags/db_latest",
        "mangos.sqlite",
    ),
    "cmangos": Emulator(
        "cmangos",
        "cmangos tbc-db",
        "https://api.github.com/repos/cmangos/tbc-db/releases/tags/latest",
        "tbcmangos.sqlite",
    ),
}


@dataclass(frozen=True)
class Pin:
    """What one game version's committed data was made from."""

    build: str  # the wago.tools DB2 build
    emulator: str  # a key of EMULATORS
    release: str  # that emulator's world database release


def fetch(url: str) -> bytes:
    """GET `url`. GitHub API calls carry GITHUB_TOKEN (or GH_TOKEN) when set: Actions runners share IPs,
    and anonymous calls get rate-limited."""
    headers = {"User-Agent": USER_AGENT}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300) as resp:
        data: bytes = resp.read()
    return data


def parse_latest_build(payload: bytes, product: str) -> str:
    """Pick `product`'s version out of wago.tools' /api/builds/latest JSON."""
    builds = json.loads(payload)
    if product not in builds:
        raise ValueError(f"no {product} build in wago.tools' latest builds")
    return str(builds[product]["version"])


def latest_build(product: str, get: Fetch = fetch) -> str:
    """The newest build of a wago.tools product (wow_classic_beta, wow_anniversary)."""
    return parse_latest_build(get(LATEST_URL), product)


def download_table(
    table: str, build: str, cache_dir: Path, optional: bool = False, get: Fetch = fetch
) -> Path:
    """The table's CSV for the build, downloaded once into `cache_dir`/wago/<build>/. An `optional` table
    the build does not serve (4xx) is cached as an empty file, which reads as no rows."""
    dest = cache_dir / "wago" / build / f"{table}.csv"
    if dest.exists():
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = get(TABLE_URL.format(table=table, build=build))
    except urllib.error.HTTPError as e:
        if not optional or not 400 <= e.code < 500:
            raise
        data = b""
    part = dest.with_name(dest.name + ".part")
    part.write_bytes(data)
    os.replace(part, dest)
    return dest


def parse_release(emulator: str, payload: bytes) -> tuple[str, str]:
    """(release id, download URL) of the SQLite dump in an emulator's release JSON."""
    found = EMULATORS[emulator].asset(json.loads(payload)["assets"])
    if found is None:
        raise ValueError(f"no SQLite database in {EMULATORS[emulator].title}'s latest release")
    return found


def latest_release(emulator: str, get: Fetch = fetch) -> tuple[str, str]:
    """(release id, download URL) of an emulator's newest world database."""
    return parse_release(emulator, get(EMULATORS[emulator].release_url))


def cached_world_db(emulator: str, release: str, cache_dir: Path) -> Path:
    return cache_dir / "emulators" / emulator / release / EMULATORS[emulator].world_db


def world_db(emulator: str, cache_dir: Path, release: str | None = None, get: Fetch = fetch) -> Path:
    """An emulator's world database: `release` (else the newest) from the cache, else downloaded.

    The emulators publish rolling releases, so only the newest can be downloaded: a `release` that is
    neither cached nor the newest is a LookupError."""
    if release is not None:
        world = cached_world_db(emulator, release, cache_dir)
        if world.exists():
            return world
    newest, url = latest_release(emulator, get)
    if release is not None and release != newest:
        raise LookupError(
            f"{EMULATORS[emulator].title} release {release} is not cached and no longer published "
            f"(the newest is {newest}): regenerate from it (game_data.py update --to latest)"
        )
    world = cached_world_db(emulator, newest, cache_dir)
    if world.exists():
        return world
    world.parent.mkdir(parents=True, exist_ok=True)
    archive = world.parent / "download.zip"
    archive.write_bytes(get(url))
    name = EMULATORS[emulator].world_db
    with zipfile.ZipFile(archive) as z:
        member = next((m for m in z.namelist() if m == name or m.endswith("/" + name)), None)
        if member is None:
            raise ValueError(f"no {name} in {url}")
        part = world.with_name(world.name + ".part")
        with z.open(member) as src, open(part, "wb") as out:
            shutil.copyfileobj(src, out)
    os.replace(part, world)
    archive.unlink()
    return world


def read_pins(path: Path = PINS) -> dict[str, Pin]:
    """Each game version's pin, from the pins file."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {key: Pin(**value) for key, value in raw.items()}


def write_pins(pins: dict[str, Pin], path: Path = PINS) -> None:
    text = json.dumps({key: asdict(pins[key]) for key in sorted(pins)}, indent=2) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
