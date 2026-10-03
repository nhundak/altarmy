"""The game data sources both halves share: wago.tools builds and tables, emulator releases, the pins."""

import ast
import io
import json
import sys
import urllib.error
import zipfile
from pathlib import Path

import pytest

from altarmy_profit import gamedata, ingest, versions
from altarmy_profit.gamedata import Pin


def test_gamedata_imports_only_the_standard_library() -> None:
    """The addon's scripts load gamedata.py by its path, without the package or the site's venv."""
    tree = ast.parse(Path(gamedata.__file__).read_text(encoding="utf-8"))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found |= {alias.name.split(".")[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom):
            assert node.level == 0, "no relative imports"
            found.add((node.module or "").split(".")[0])
    assert found - set(sys.stdlib_module_names) == set()


def test_parse_latest_build_picks_product() -> None:
    payload = json.dumps(
        {
            "wow": {"product": "wow", "version": "12.1.0.69933"},
            "wow_classic_beta": {"product": "wow_classic_beta", "version": "1.60.1.69977"},
        }
    ).encode()
    assert gamedata.parse_latest_build(payload, "wow_classic_beta") == "1.60.1.69977"
    assert gamedata.parse_latest_build(payload, "wow") == "12.1.0.69933"
    with pytest.raises(ValueError, match="wow_nope"):
        gamedata.parse_latest_build(payload, "wow_nope")


def test_download_caches_tables_and_an_optional_table_the_build_lacks(tmp_path: Path) -> None:
    urls: list[str] = []

    def get(url: str) -> bytes:
        urls.append(url)
        if "ItemArmorShield" in url or "Missing" in url:
            raise urllib.error.HTTPError(url, 400, "Bad Request", None, None)  # type: ignore[arg-type]
        return b"ID\n1\n"

    path = gamedata.download_table("Item", "1.0", tmp_path, get=get)
    assert path == tmp_path / "wago" / "1.0" / "Item.csv"
    assert gamedata.download_table("Item", "1.0", tmp_path, get=get) == path  # cached: no second fetch
    assert urls == ["https://wago.tools/db2/Item/csv?build=1.0"]
    empty = gamedata.download_table("ItemArmorShield", "1.0", tmp_path, optional=True, get=get)
    assert empty.read_bytes() == b""
    assert list(ingest._optional_rows({"ItemArmorShield": empty}, "ItemArmorShield")) == []
    assert list(ingest._optional_rows({}, "ItemArmorShield")) == []
    with pytest.raises(urllib.error.HTTPError):
        gamedata.download_table("Missing", "1.0", tmp_path, get=get)


def test_parse_release_picks_each_emulators_sqlite_dump() -> None:
    cmangos = {
        "assets": [
            {"name": "tbc-world-db.zip", "updated_at": "2026-09-24T11:01:00Z", "browser_download_url": "x"},
            {"name": "tbc-sqlite-db.zip", "updated_at": "2026-09-24T11:00:59Z", "browser_download_url": "y"},
        ]
    }
    vmangos = {
        "assets": [
            {"name": "db-13b49dc.zip", "browser_download_url": "https://example/db.zip"},
            {"name": "db-sqlite-13b49dc.zip", "browser_download_url": "https://example/db-sqlite.zip"},
        ]
    }
    assert gamedata.parse_release("cmangos", json.dumps(cmangos).encode()) == ("2026-09-24", "y")
    assert gamedata.parse_release("vmangos", json.dumps(vmangos).encode()) == (
        "db-sqlite-13b49dc",
        "https://example/db-sqlite.zip",
    )
    for emulator in gamedata.EMULATORS:
        with pytest.raises(ValueError):
            gamedata.parse_release(emulator, b'{"assets": []}')


def _zipped(member: str, content: bytes) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr(member, content)
    return buf.getvalue()


def test_world_db_downloads_the_newest_once_and_refuses_a_release_gone(tmp_path: Path) -> None:
    release = {"assets": [{"name": "db-sqlite-abc.zip", "browser_download_url": "https://example/abc.zip"}]}
    urls: list[str] = []

    def get(url: str) -> bytes:
        urls.append(url)
        if url == gamedata.EMULATORS["vmangos"].release_url:
            return json.dumps(release).encode()
        return _zipped("db/mangos.sqlite", b"world")

    world = gamedata.world_db("vmangos", tmp_path, get=get)
    assert world == tmp_path / "emulators" / "vmangos" / "db-sqlite-abc" / "mangos.sqlite"
    assert world.read_bytes() == b"world"
    assert not (world.parent / "download.zip").exists()
    assert len(urls) == 2
    assert gamedata.world_db("vmangos", tmp_path, "db-sqlite-abc", get=get) == world  # cached: no network
    assert len(urls) == 2
    with pytest.raises(LookupError, match="db-sqlite-old"):
        gamedata.world_db("vmangos", tmp_path, "db-sqlite-old", get=get)


def test_pins_round_trip(tmp_path: Path) -> None:
    pins = {
        "tbc": Pin("2.5.6.1", "cmangos", "2026-09-24"),
        "forever": Pin("1.60.1.2", "vmangos", "db-sqlite-abc"),
    }
    path = tmp_path / "game-data.json"
    gamedata.write_pins(pins, path)
    assert gamedata.read_pins(path) == pins
    assert list(json.loads(path.read_text(encoding="utf-8"))) == ["forever", "tbc"]
    assert ingest.pinned_build(versions.VERSIONS["tbc"], path) == "2.5.6.1"


def test_the_committed_pins_cover_every_version() -> None:
    pins = gamedata.read_pins()
    assert pins.keys() == versions.VERSIONS.keys()
    assert pins["forever"].emulator == "vmangos"
    assert pins["tbc"].emulator == "cmangos"
    for key, pin in pins.items():
        assert versions.version_of_build(pin.build) == key
