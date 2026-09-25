"""The tray app's testable part: its settings file, status line and start-with-Windows command."""

from datetime import datetime
from pathlib import Path

from altarmy_profit import tray_core
from altarmy_profit.tray_core import TrayConfig


def test_config_defaults_to_the_live_site_without_a_key(tmp_path: Path) -> None:
    assert tray_core.load_config(tmp_path / "missing.json") == TrayConfig(tray_core.DEFAULT_SERVER, None)


def test_config_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "sub" / "tray.json"
    tray_core.save_config(path, TrayConfig("https://example.test/", "ak_x"))
    assert tray_core.load_config(path) == TrayConfig("https://example.test", "ak_x")  # no trailing slash


def test_a_broken_config_falls_back_to_defaults(tmp_path: Path) -> None:
    path = tmp_path / "tray.json"
    for text in ("not json", "[1]", '{"server": 5, "key": ["x"]}'):
        path.write_text(text, encoding="utf-8")
        assert tray_core.load_config(path) == TrayConfig(tray_core.DEFAULT_SERVER, None)
    path.write_text('{"key": "  "}', encoding="utf-8")
    assert tray_core.load_config(path).key is None  # a blank key is no key


def test_status_keeps_the_last_event_with_its_time() -> None:
    status = tray_core.Status()
    assert status.text == "Watching for WoW's SavedVariables"
    status.log(
        "Uploaded tbc Auctionator.lua: Dreamscythe Horde: 9431 prices, 12 changed",
        datetime(2026, 9, 25, 14, 5),
    )
    assert status.text == "14:05 Uploaded tbc Auctionator.lua: Dreamscythe Horde: 9431 prices, 12 changed"
    assert status.problem is None
    status.log("Upload failed (server busy); retrying.", datetime(2026, 9, 25, 14, 6))
    assert status.problem == "Upload failed (server busy); retrying."
    status.log("x" * 200, datetime(2026, 9, 25, 14, 7))
    assert len(status.text) <= tray_core.STATUS_MAX
    assert status.problem is None  # cleared by a later event that isn't a problem


def test_autostart_command_runs_the_exe_or_the_module() -> None:
    assert tray_core.autostart_command(r"C:\Apps\altarmy-profit-tray.exe", frozen=True) == (
        r'"C:\Apps\altarmy-profit-tray.exe"'
    )
    assert tray_core.autostart_command(r"C:\venv\Scripts\python.exe", frozen=False) == (
        r'"C:\venv\Scripts\pythonw.exe" -m altarmy_profit.tray'
    )
