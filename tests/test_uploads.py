"""Uploaded addon files: characters replace the uploader's, prices pool per auction house."""

import gzip
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import Connection, select

from altarmy_profit import altarmy, prices, schema, service, store, uploads, users
from altarmy_profit.auth import User

from .conftest import FOREVER, ME
from .test_altarmy import ALTARMY_SV
from .test_auctionator import _entry, _saved_variables

NOW = datetime(2026, 9, 24, 20, 0, tzinfo=UTC)
OTHER = "other-user"
PASTE = (Path(__file__).parent / "fixtures" / "altarmy_export_v1.txt").read_text(encoding="utf-8")


@pytest.fixture
def other(conn: Connection) -> str:
    users.ensure_user(conn, User(OTHER, "free"))
    return OTHER


def scan(realms: dict[str, dict[str, object]]) -> bytes:
    return _saved_variables(realms)


def test_altarmy_upload_replaces_only_the_uploaders_characters(conn: Connection, other: str) -> None:
    store.save_characters(conn, other, FOREVER, store.load_characters(conn, ME, FOREVER))  # nothing yet
    got = uploads.ingest(conn, ME, FOREVER, "altarmy", ALTARMY_SV, None, now=NOW)
    assert got.characters == 4
    assert got.groups == (
        ("Classic Beta PvE", "Alliance", 1),
        ("Classic Beta PvE", "Horde", 1),
        ("Dreamscythe", "Horde", 2),
    )
    assert "4 characters" in got.detail
    assert store.count_characters(conn, ME, FOREVER) == 4
    assert store.count_characters(conn, other, FOREVER) == 0
    assert service.data_version(conn, ME, FOREVER) == 1


def test_auctionator_upload_records_every_realm_named_like_the_characters(conn: Connection) -> None:
    uploads.ingest(conn, ME, FOREVER, "altarmy", ALTARMY_SV, None, now=NOW)
    data = scan({"ClassicBetaPvE": {"1": _entry(20)}, "Dreamscythe Horde": {"1": _entry(5)}, "Empty": {}})
    got = uploads.ingest(conn, ME, FOREVER, "auctionator", data, NOW - timedelta(hours=1), now=NOW)
    names = [(r.key, r.realm, r.faction, r.items, r.skipped) for r in got.realms]
    assert names == [
        # Forever's houses are per faction, Auctionator's key names none, and ME has both there
        ("ClassicBetaPvE", "", "", 1, uploads.BOTH_FACTIONS),
        ("Dreamscythe Horde", "Dreamscythe", "Horde", 1, None),
    ]
    assert len(got.auction_house_ids) == 1
    assert "ClassicBetaPvE: 1 prices not used: You have Horde and Alliance" in got.detail
    assert prices.find_auction_house(conn, FOREVER, "Empty", "") is None  # realms without prices are skipped
    assert prices.load_current(conn, service.selected_auction_house(conn, ME, FOREVER)) == {1: 5}
    snap = schema.price_snapshots
    assert set(conn.execute(select(snap.c.uploader_uid)).scalars()) == {ME}
    assert set(conn.execute(select(schema.auction_houses.c.faction)).scalars()) == {"Horde"}


def _characters(*where: tuple[str, str]) -> list[altarmy.Character]:
    return [
        altarmy.Character(realm, f"Char{i}", faction, "MAGE", 60, ())
        for i, (realm, faction) in enumerate(where)
    ]


def test_a_forever_scan_goes_to_the_uploaders_faction(conn: Connection, other: str) -> None:
    store.save_characters(
        conn, ME, FOREVER, _characters(("Classic Beta PvE", "Horde"), ("Classic Beta PvE", "Horde"))
    )
    store.save_characters(conn, other, FOREVER, _characters(("Classic Beta PvE", "Alliance")))
    uploads.ingest(
        conn, ME, FOREVER, "auctionator", scan({"ClassicBetaPvE": {"1": _entry(20)}}), None, now=NOW
    )
    uploads.ingest(
        conn, other, FOREVER, "auctionator", scan({"ClassicBetaPvE": {"1": _entry(30)}}), None, now=NOW
    )
    horde = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    alliance = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Alliance")
    assert horde is not None and alliance is not None and horde != alliance
    assert prices.load_current(conn, horde) == {1: 20}
    assert prices.load_current(conn, alliance) == {1: 30}
    assert prices.find_auction_house_by_key(conn, FOREVER, "ClassicBetaPvE") is None  # ambiguous: no alias
    assert service.selected_auction_house(conn, ME, FOREVER) == horde


def test_a_forever_scan_before_any_characters_is_skipped(conn: Connection) -> None:
    got = uploads.ingest(
        conn, ME, FOREVER, "auctionator", scan({"ClassicBetaPvE": {"1": _entry(20)}}), None, now=NOW
    )
    (realm,) = got.realms
    assert realm.skipped == uploads.NO_CHARACTERS and realm.auction_house_id is None
    assert prices.coverage(conn, FOREVER) == []
    assert service.data_version(conn, ME, FOREVER) == 0


def test_uploads_pool_and_the_newest_scan_wins(conn: Connection, other: str) -> None:
    def latest(price: int) -> bytes:  # no day history: seen at the file's scan time
        return scan({"Dreamscythe Horde": {"1": {"m": price}}})

    uploads.ingest(conn, ME, FOREVER, "auctionator", latest(5), NOW - timedelta(hours=2), now=NOW)
    uploads.ingest(conn, other, FOREVER, "auctionator", latest(9), NOW - timedelta(hours=1), now=NOW)
    ah = prices.find_auction_house(conn, FOREVER, "Dreamscythe", "Horde")
    assert prices.load_current(conn, ah) == {1: 9}  # another user's newer scan
    uploads.ingest(conn, ME, FOREVER, "auctionator", latest(7), NOW - timedelta(hours=3), now=NOW)
    assert prices.load_current(conn, ah) == {1: 9}  # an older file doesn't win


def test_a_wildly_off_scan_is_quarantined_and_costs_trust(conn: Connection, other: str) -> None:
    def latest(price: int) -> bytes:
        return scan({"Dreamscythe Horde": {str(i): {"m": price} for i in range(1, 31)}})

    uploads.ingest(conn, ME, FOREVER, "auctionator", latest(100), NOW - timedelta(hours=2), now=NOW)
    ah = prices.find_auction_house(conn, FOREVER, "Dreamscythe", "Horde")
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=100, scans_7d=5))  # as the merge job would

    got = uploads.ingest(
        conn, other, FOREVER, "auctionator", latest(10_000), NOW - timedelta(hours=1), now=NOW
    )
    (realm,) = got.realms
    assert realm.quarantined and realm.moved == 0
    assert got.detail == "Dreamscythe Horde: 30 prices not used: they differ widely from recent scans"
    assert set(prices.load_current(conn, ah).values()) == {100}
    assert users.trust(conn, other) == 0.5

    got = uploads.ingest(conn, ME, FOREVER, "auctionator", latest(110), NOW, now=NOW)
    assert not got.realms[0].quarantined
    assert users.trust(conn, ME) == 1.0  # capped


def test_trust_halves_on_quarantine_and_recovers(conn: Connection, other: str) -> None:
    assert users.trust(conn, other) == 1.0
    assert users.adjust_trust(conn, other, quarantined=True) == 0.5
    assert users.adjust_trust(conn, other, quarantined=True) == 0.25
    assert users.adjust_trust(conn, other, quarantined=False) == pytest.approx(0.35)
    assert users.trust(conn, "nobody") == 1.0


def test_a_pasted_export_replaces_the_characters(conn: Connection) -> None:
    got = uploads.ingest_paste(conn, ME, "tbc", PASTE)
    assert (got.kind, got.characters) == ("altarmy", 2)
    assert got.groups == (("Dreamscythe", "Horde", 1),)  # a character never scanned has no faction group
    assert [c.name for c in store.load_characters(conn, ME, "tbc")] == ["Tailor Guy", "Frell"]
    assert service.data_version(conn, ME, "tbc") == 1


def test_a_pasted_export_of_the_other_game_is_refused(conn: Connection) -> None:
    with pytest.raises(ValueError, match="This is a TBC Anniversary export; this site serves WoW: Forever"):
        uploads.ingest_paste(conn, ME, FOREVER, PASTE)
    assert store.count_characters(conn, ME, FOREVER) == 0


def test_scan_time_is_clamped() -> None:
    assert uploads.scan_time(None, NOW) == NOW
    assert uploads.scan_time(NOW + timedelta(days=1), NOW) == NOW
    assert uploads.scan_time(NOW - timedelta(days=90), NOW) == NOW - uploads.SCAN_WINDOW
    assert uploads.scan_time(NOW - timedelta(hours=1), NOW) == NOW - timedelta(hours=1)


def test_bad_files_raise_value_error(conn: Connection) -> None:
    with pytest.raises(ValueError, match="AltArmyTBC_Data"):
        uploads.ingest(conn, ME, FOREVER, "altarmy", b"Foo = {}", None, now=NOW)
    with pytest.raises(ValueError, match="AUCTIONATOR_PRICE_DATABASE"):
        uploads.ingest(conn, ME, FOREVER, "auctionator", ALTARMY_SV, None, now=NOW)


def test_history_and_rate_limit(conn: Connection) -> None:
    for i in range(uploads.RATE_LIMIT):
        uploads.check_rate(conn, ME, now=NOW)
        uploads.record_upload(conn, ME, FOREVER, "altarmy", "browser", 10, "accepted", f"#{i}", now=NOW)
    with pytest.raises(uploads.RateLimited):
        uploads.check_rate(conn, ME, now=NOW)
    uploads.check_rate(conn, ME, now=NOW + timedelta(hours=1, seconds=1))  # an hour later
    recent = uploads.recent(conn, ME)
    assert len(recent) == 20 and recent[0].detail.startswith("#")
    assert uploads.recent(conn, "local-nobody") == []


def test_import_status_from_the_upload_history(conn: Connection) -> None:
    assert uploads.import_status(conn, ME, FOREVER) == uploads.ImportStatus(None, None, None)
    earlier, later = NOW - timedelta(days=2), NOW - timedelta(hours=1)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "watcher", 10, "accepted", "", now=earlier)
    uploads.record_upload(conn, ME, FOREVER, "auctionator", "watcher", 10, "accepted", "", now=later)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "paste", 10, "accepted", "", now=later)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "browser", 10, "rejected", "bad", now=NOW)
    uploads.record_upload(conn, ME, "tbc", "altarmy", "watcher", 10, "accepted", "", now=NOW)
    users.ensure_user(conn, User("someone-else", "linked"))
    uploads.record_upload(conn, "someone-else", FOREVER, "altarmy", "watcher", 10, "accepted", "", now=NOW)
    status = uploads.import_status(conn, ME, FOREVER)
    # The characters came from the newest accepted Alt Army upload; the watcher sent a price scan later.
    assert status == uploads.ImportStatus(imported_at=later, imported_via="paste", auto_import_at=later)


def test_decompress_limits_the_size() -> None:
    assert uploads.decompress(gzip.compress(b"x" * 100), 1000) == b"x" * 100
    assert uploads.decompress(b"plain", 1000) == b"plain"
    with pytest.raises(uploads.TooLarge):
        uploads.decompress(gzip.compress(b"x" * 5000), 1000)
    with pytest.raises(uploads.TooLarge):
        uploads.decompress(b"y" * 5000, 1000)
    with pytest.raises(ValueError, match="gzip"):
        uploads.decompress(b"\x1f\x8b" + b"not gzip", 1000)


def test_every_users_uploads_and_their_counts(conn: Connection, other: str) -> None:
    def upload(uid: str, version: str, outcome: str, detail: str, days: int) -> None:
        when = NOW - timedelta(days=days)
        uploads.record_upload(conn, uid, version, "auctionator", "watcher", 10, outcome, detail, now=when)

    upload(ME, FOREVER, "accepted", "mine", 0)
    upload(other, FOREVER, "rejected", "bad", 6)
    upload(other, FOREVER, "accepted", "old", 8)
    upload(other, "tbc", "accepted", "tbc", 0)
    got = uploads.recent_all(conn, FOREVER)
    assert [(u.user_uid, u.detail) for u in got] == [(ME, "mine"), (other, "bad"), (other, "old")]
    assert uploads.recent_all(conn, FOREVER, limit=1)[0].detail == "mine"
    assert uploads.stats(conn, FOREVER, NOW) == uploads.UploadStats(1, 0, 1, 1, 2)
    assert uploads.stats(conn, "tbc", NOW + timedelta(days=30)) == uploads.UploadStats(0, 0, 0, 0, 0)
