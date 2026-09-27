"""Alt Army Sync's testable part: its settings file, status line and start-with-Windows command."""

from datetime import datetime
from pathlib import Path

import pytest

from altarmy_profit import signin, tray_core
from altarmy_profit.tray_core import TrayConfig


def test_the_live_site_by_default_and_staging_or_another_on_request() -> None:
    assert tray_core.parse_args([]) == tray_core.PROD
    assert tray_core.PROD.server == "https://alt-army.com"
    assert tray_core.PROD.config_path.name == "sync.json"
    assert tray_core.PROD.run_value == "altarmy-sync"
    assert tray_core.PROD.title == "Alt Army Sync"

    staging = tray_core.parse_args(["--staging"])
    assert staging.server == tray_core.STAGING_SERVER
    assert (staging.config_path.name, staging.log_path.name) == ("sync-staging.json", "sync-staging.log")
    assert staging.mutex == "Local\\altarmy-sync-staging"
    assert staging.run_value == "altarmy-sync-staging"
    assert staging.title == "Alt Army Sync (staging)"
    assert staging.args == ("--staging",)

    dev = tray_core.parse_args(["--server", "http://127.0.0.1:8600/"])
    assert (dev.server, dev.name, dev.args) == (
        "http://127.0.0.1:8600",
        "dev",
        ("--server", "http://127.0.0.1:8600"),
    )


def test_a_bad_command_line_stops(capsys: pytest.CaptureFixture[str]) -> None:
    for argv in (["--staging", "--server", "http://x"], ["--server", "localhost"], ["--nope"]):
        with pytest.raises(SystemExit):
            tray_core.parse_args(argv)


def test_config_defaults_to_signed_out(tmp_path: Path) -> None:
    config = tray_core.load_config(tmp_path / "missing.json")
    assert config == TrayConfig()
    assert not config.signed_in


def test_config_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "sub" / "sync.json"
    tray_core.save_config(path, TrayConfig("me@example.com", "rt"))
    loaded = tray_core.load_config(path)
    assert loaded == TrayConfig("me@example.com", "rt")
    assert loaded.signed_in


def test_a_broken_or_old_config_falls_back_to_signed_out(tmp_path: Path) -> None:
    path = tmp_path / "sync.json"
    for text in ("not json", "[1]", '{"server": 5, "email": ["x"]}'):
        path.write_text(text, encoding="utf-8")
        assert tray_core.load_config(path) == TrayConfig()
    path.write_text('{"server": "https://example.test", "key": "ak_old"}', encoding="utf-8")
    assert tray_core.load_config(path) == TrayConfig()  # API keys are gone: sign in; the flags pick the site
    path.write_text('{"email": "me@example.com", "refresh_token": "  "}', encoding="utf-8")
    assert not tray_core.load_config(path).signed_in  # an email alone is not a sign-in


def test_the_sign_in_form_is_checked_before_asking_firebase() -> None:
    assert tray_core.form_problem("me@example.com", "pw", None) is None
    assert tray_core.form_problem("me", "pw", None) == "Enter your email address."
    assert tray_core.form_problem("me@example.com", "", None) == "Enter your password."
    assert tray_core.form_problem("me@example.com", "abc", "abc") == "Passwords need at least 6 characters."
    assert tray_core.form_problem("me@example.com", "secret1", "secret2") == "The passwords don't match."
    assert tray_core.form_problem("me@example.com", "secret1", "secret1") is None


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


def test_autostart_command_runs_the_exe_or_the_module_with_the_target_flags() -> None:
    assert tray_core.autostart_command(r"C:\Apps\altarmy-sync.exe", frozen=True) == (
        r'"C:\Apps\altarmy-sync.exe"'
    )
    assert tray_core.autostart_command(r"C:\venv\Scripts\python.exe", frozen=False) == (
        r'"C:\venv\Scripts\pythonw.exe" -m altarmy_profit.tray'
    )
    assert tray_core.autostart_command(r"C:\Apps\altarmy-sync.exe", frozen=True, args=("--staging",)) == (
        r'"C:\Apps\altarmy-sync.exe" --staging'
    )
    assert (
        tray_core.autostart_command(
            r"C:\Apps\altarmy-sync.exe", frozen=True, args=("--server", "http://my host")
        )
        == r'"C:\Apps\altarmy-sync.exe" --server "http://my host"'
    )


def test_config_remembers_the_version_it_last_announced(tmp_path: Path) -> None:
    path = tmp_path / "sync.json"
    tray_core.save_config(path, TrayConfig(notified_version="0.3.0"))
    assert tray_core.load_config(path) == TrayConfig(notified_version="0.3.0")
    tray_core.save_config(path, TrayConfig("me@example.com", "rt", "0.3.0"))
    assert tray_core.load_config(path) == TrayConfig("me@example.com", "rt", "0.3.0")
    path.write_text('{"email": "me@example.com", "refresh_token": "rt"}', encoding="utf-8")
    assert tray_core.load_config(path) == TrayConfig("me@example.com", "rt")  # a file from before


def test_versions_are_compared_as_numbers() -> None:
    assert tray_core.parse_version("sync-v1.2.3") == (1, 2, 3)
    assert tray_core.parse_version("0.10.0") == (0, 10, 0)
    for junk in ("dev", "", "v1.2", "sync-v1.x", "1..2", "sync-v"):
        assert tray_core.parse_version(junk) is None
    release = tray_core.Release("0.10.0", "https://github.com/r/0.10.0")
    assert tray_core.newer("0.9.0", release)
    assert not tray_core.newer("0.10.0", release)
    assert not tray_core.newer("0.11.0", release)
    assert not tray_core.newer("dev", release)  # running from source: never outdated
    assert not tray_core.newer("0.9.0", None)


def _release(tag: str, **extra: object) -> dict[str, object]:
    url = f"https://github.com/r/{tag}"
    return {"tag_name": tag, "html_url": url, "draft": False, "prerelease": False, **extra}


def test_the_latest_release_is_the_highest_published_sync_tag() -> None:
    payload = [
        _release("sync-v0.9.0"),
        _release("sync-v0.11.0", draft=True),
        _release("sync-v0.12.0", prerelease=True),
        _release("v9.0.0"),
        _release("sync-v0.10.0"),
        {"tag_name": 5},
        "junk",
    ]
    assert tray_core.latest_release(payload) == tray_core.Release(
        "0.10.0", "https://github.com/r/sync-v0.10.0"
    )
    no_url: list[object] = [{"tag_name": "sync-v1.0.0", "draft": False, "prerelease": False}]
    bad: object
    for bad in (
        None,
        {},
        "x",
        [],
        no_url,
        [{"tag_name": "sync-v1.0.0", "html_url": 3, "draft": False, "prerelease": False}],
    ):
        assert tray_core.latest_release(bad) is None


def test_checking_for_an_update_never_raises() -> None:
    import json
    from collections.abc import Mapping

    seen: list[Mapping[str, str]] = []

    def answering(status: int, body: bytes) -> signin.Transport:
        def transport(url: str, headers: Mapping[str, str], data: bytes | None) -> tuple[int, bytes]:
            assert url == tray_core.RELEASES_URL and data is None
            seen.append(headers)
            return status, body

        return transport

    releases = json.dumps([_release("sync-v0.4.0")]).encode()
    found = tray_core.check_for_update("0.3.0", answering(200, releases))
    assert found == tray_core.Release("0.4.0", "https://github.com/r/sync-v0.4.0")
    assert seen[0]["User-Agent"] == "altarmy-sync/0.3.0"
    assert tray_core.check_for_update("0.4.0", answering(200, releases)) is None
    assert tray_core.check_for_update("0.3.0", answering(403, b'{"message": "rate limited"}')) is None
    assert tray_core.check_for_update("0.3.0", answering(200, b"not json")) is None

    def offline(url: str, headers: Mapping[str, str], data: bytes | None) -> tuple[int, bytes]:
        raise OSError("no network")

    assert tray_core.check_for_update("0.3.0", offline) is None
