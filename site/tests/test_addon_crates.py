"""Regenerating the Alt Army addon's Waylaid Crates table after a local Forever ingest."""

import subprocess
from pathlib import Path
from typing import Any

import pytest

from altarmy_site import addon_crates, db


def fake_addon(tmp_path: Path, body: str = "print('wrote WaylaidCrates.lua: 31 crates')") -> Path:
    root = tmp_path / "altarmy_tbc"
    script = root / addon_crates.SCRIPT
    script.parent.mkdir(parents=True)
    script.write_text("import sys\nassert sys.argv[1] == '--db'\n" + body + "\n", encoding="utf-8")
    return root


def sqlite(tmp_path: Path) -> db.Database:
    return db.Database(db.sqlite_url(tmp_path / "game.sqlite"), migrate=False)


def test_runs_the_addon_script_on_the_sqlite_file(tmp_path: Path) -> None:
    calls: list[list[str]] = []

    def run(cmd: list[str], **kw: Any) -> "subprocess.CompletedProcess[str]":
        calls.append(cmd)
        assert kw["cwd"] == tmp_path / "altarmy_tbc"
        return subprocess.CompletedProcess(cmd, 0, stdout="wrote it: 31 crates\n", stderr="")

    note = addon_crates.regenerate(sqlite(tmp_path), "forever", addon=fake_addon(tmp_path), run=run)
    assert note == "Alt Army Waylaid Crates: wrote it: 31 crates"
    assert calls[0][1:] == [
        str(tmp_path / "altarmy_tbc" / addon_crates.SCRIPT),
        "--db",
        str((tmp_path / "game.sqlite").resolve()),
    ]


def test_really_runs_the_script(tmp_path: Path) -> None:
    note = addon_crates.regenerate(sqlite(tmp_path), "forever", addon=fake_addon(tmp_path))
    assert note == "Alt Army Waylaid Crates: wrote WaylaidCrates.lua: 31 crates"


def test_runs_the_writs_generator_too_when_it_is_there(tmp_path: Path) -> None:
    addon = fake_addon(tmp_path)
    (addon / addon_crates.WRITS_SCRIPT).write_text(
        "import sys\nassert sys.argv[1] == '--db'\nprint('wrote Writs.lua: 150 writs')\n", encoding="utf-8"
    )
    note = addon_crates.regenerate(sqlite(tmp_path), "forever", addon=addon)
    assert note == (
        "Alt Army Waylaid Crates: wrote WaylaidCrates.lua: 31 crates\n"
        "Alt Army Craftsman's Writs: wrote Writs.lua: 150 writs"
    )


def test_reports_a_failing_script_without_raising(tmp_path: Path) -> None:
    addon = fake_addon(tmp_path, "sys.exit('expected 31 Waylaid Crates, found 0')")
    note = addon_crates.regenerate(sqlite(tmp_path), "forever", addon=addon)
    assert note == "Alt Army Waylaid Crates not regenerated: expected 31 Waylaid Crates, found 0"


def test_skips_other_games_postgres_and_a_missing_addon(tmp_path: Path) -> None:
    addon = fake_addon(tmp_path)
    assert addon_crates.regenerate(sqlite(tmp_path), "tbc", addon=addon) is None
    pg = db.Database("postgresql+psycopg://u:p@localhost/x", migrate=False)
    assert addon_crates.regenerate(pg, "forever", addon=addon) is None
    assert addon_crates.regenerate(sqlite(tmp_path), "forever", addon=tmp_path / "nope") is None


def test_the_addon_sits_next_to_this_repo_unless_told(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.delenv(addon_crates.ADDON_DIR_ENV, raising=False)
    assert addon_crates.addon_dir() == addon_crates.REPO_ROOT.parent / "addon"
    monkeypatch.setenv(addon_crates.ADDON_DIR_ENV, str(tmp_path))
    assert addon_crates.addon_dir() == tmp_path
