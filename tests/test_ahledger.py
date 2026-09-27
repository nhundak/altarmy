"""AHledger's price tables: parsing, and polls that cost one request per market and record only what
changed since the last table, dated by the tables, so that the newest capture wins between its prices and
uploads."""

import contextlib
import json
import random
from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import Connection, select

from altarmy_profit import ahledger, cli, db, prices, schema

from .conftest import FOREVER
from .test_auctionator import _mangled

T0 = datetime(2026, 9, 27, 7, 0, tzinfo=UTC)
HORDE = ahledger.Market("forever.normal.horde.us", "Classic Beta PvE", "Horde")


def table_text(market: str, at: datetime, rows: Mapping[int, tuple[int, int]]) -> str:
    """A price table as AHledger serves it; rows are item -> (min buyout, quantity)."""
    game, ruleset, faction, region = market.split(".")
    head = f"AHL1|{game}/{ruleset}/{faction}/{region}|{int(at.timestamp())}|{len(rows)}"
    lines = [f"{i}:{p + 1}:{p}:{q}:{p}:{p}:{p}:{p}" for i, (p, q) in rows.items()]
    return "\n".join([head, *lines]) + "\n"


class FakeAHledger:
    """A transport serving the market list and one price table per market."""

    def __init__(self) -> None:
        self.tables: dict[str, str] = {}
        self.urls: list[str] = []
        self.throttle = 0  # how many requests to answer 429 first

    def set(self, market: str, at: datetime, rows: Mapping[int, tuple[int, int]]) -> None:
        self.tables[market] = table_text(market, at, rows)

    def __call__(self, url: str, headers: Mapping[str, str]) -> tuple[int, bytes, Mapping[str, str]]:
        self.urls.append(url)
        if self.throttle:
            self.throttle -= 1
            return 429, b"slow down", {"Retry-After": "2"}
        path = url.removeprefix(ahledger.API)
        if path == "/markets":
            ids = [{"id": m.id} for m in ahledger.markets(FOREVER)]
            return 200, json.dumps({"markets": ids}).encode(), {}
        text = self.tables.get(path.removeprefix("/pricetable/"))
        return (200, text.encode(), {}) if text else (404, b"", {})


@pytest.fixture
def api() -> FakeAHledger:
    return FakeAHledger()


def client(api: FakeAHledger) -> ahledger.Client:
    return ahledger.Client(api, sleep=lambda _: None)


def current(conn: Connection, ah: int) -> dict[int, tuple[int, datetime]]:
    pc = schema.price_current
    rows = conn.execute(select(pc.c.item_id, pc.c.price, pc.c.seen_at).where(pc.c.auction_house_id == ah))
    return {r.item_id: (r.price, db.utc(r.seen_at)) for r in rows}


def test_parse_table_reads_median_before_min_buyout() -> None:
    got = ahledger.parse_table(
        "AHL1|forever/normal/horde/us|1790493156|2\n117:3:2:208:29:29:1:40\n118:7:4:1138\n"
    )
    assert got.market == "forever.normal.horde.us"
    assert got.scanned_at == datetime(2026, 9, 27, 7, 12, 36, tzinfo=UTC)
    assert got.rows == {117: ahledger.Row(2, 3, 208), 118: ahledger.Row(4, 7, 1138)}


@pytest.mark.parametrize(
    "text",
    [
        "",
        "hello",
        "AHL2|forever/normal/horde/us|1|0",
        "AHL1|forever/normal/horde/us|soon|0",
        "AHL1|forever/normal/horde/us|99999999999999999999|0",
        "AHL1|forever/normal/horde/us|1|2\n1:2:3:4",  # a row short
        "AHL1|forever/normal/horde/us|1|1\n1:2:x:4",
        "AHL1|forever/normal/horde/us|1|1\n1:2",
    ],
)
def test_bad_tables_raise_value_error(text: str) -> None:
    with pytest.raises(ValueError):
        ahledger.parse_table(text)


def test_mangled_answers_only_raise_value_error() -> None:
    rng = random.Random(2)
    tables = [table_text(HORDE.id, T0, {1: (5, 2), 2: (70, 1)}).encode()]
    for _ in range(1500):
        with contextlib.suppress(ValueError):
            ahledger.parse_table(_mangled(tables, rng).decode("latin-1"))


def test_markets_are_each_ruleset_realms_factions() -> None:
    assert [(m.id, m.realm, m.faction) for m in ahledger.markets(FOREVER)] == [
        ("forever.normal.alliance.us", "Classic Beta PvE", "Alliance"),
        ("forever.normal.horde.us", "Classic Beta PvE", "Horde"),
        ("forever.pvp.alliance.us", "Classic Beta PvP 2", "Alliance"),
        ("forever.pvp.horde.us", "Classic Beta PvP 2", "Horde"),
    ]
    assert ahledger.markets("tbc") == []


FETCHED = T0 + timedelta(minutes=10)  # when the first table was fetched


def poll(conn: Connection, api: FakeAHledger, now: datetime) -> ahledger.Polled:
    return ahledger.poll_market(conn, FOREVER, HORDE, client(api), now=now)


def test_a_first_table_is_recorded_as_seen_when_fetched(conn: Connection, api: FakeAHledger) -> None:
    api.set(HORDE.id, T0, {1: (20, 5), 2: (100, 1)})
    got = poll(conn, api, FETCHED)
    assert (got.items, got.recorded, got.moved) == (2, 2, 2)
    ah = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    assert ah == got.auction_house_id
    assert current(conn, ah) == {1: (20, FETCHED), 2: (100, FETCHED)}
    assert [d[1:] for d in prices.daily(conn, ah, 1)] == [(20, 20, 5)]
    assert api.urls == [f"{ahledger.API}/pricetable/{HORDE.id}"]  # one request, never one per item

    again = poll(conn, api, FETCHED + timedelta(hours=1))  # the same table
    assert again.unchanged and again.recorded == 0
    assert again.summary == "forever.normal.horde.us: no newer scan"
    assert conn.execute(select(schema.price_snapshots.c.source)).scalars().all() == ["ahledger"]


def test_a_newer_table_records_only_what_changed_at_its_time(conn: Connection, api: FakeAHledger) -> None:
    api.set(HORDE.id, T0, {1: (100, 1), 2: (100, 1), 3: (100, 1)})
    poll(conn, api, FETCHED)
    t1 = T0 + timedelta(hours=1)
    # 1: a new price, 2: the same price but a new quantity, 3: unchanged, 4: new to the table
    api.set(HORDE.id, t1, {1: (90, 1), 2: (100, 7), 3: (100, 1), 4: (55, 2)})
    got = poll(conn, api, t1 + timedelta(minutes=3))
    assert got.recorded == 3
    assert current(conn, got.auction_house_id) == {
        1: (90, t1),
        2: (100, FETCHED),  # the same price: current doesn't move (the observation is kept)
        3: (100, FETCHED),
        4: (55, t1),
    }
    assert got.summary == "forever.normal.horde.us: 4 items, 3 new or changed, 2 moved"


def test_a_cached_table_never_dates_changes_before_the_last_stamp(
    conn: Connection, api: FakeAHledger
) -> None:
    api.set(HORDE.id, T0, {1: (100, 1)})
    poll(conn, api, FETCHED)
    t1 = T0 + timedelta(minutes=5)  # a scan the first fetch's cached table didn't have yet
    api.set(HORDE.id, t1, {1: (80, 1)})
    got = poll(conn, api, FETCHED + timedelta(hours=1))
    assert current(conn, got.auction_house_id) == {1: (80, FETCHED)}  # not lost to the first table's stamp


def test_the_newest_capture_wins_between_uploads_and_ahledger(conn: Connection, api: FakeAHledger) -> None:
    api.set(HORDE.id, T0, {1: (10, 1), 2: (20, 1)})
    ah = poll(conn, api, FETCHED).auction_house_id
    upload_at = FETCHED + timedelta(minutes=20)  # uploads come after the first load
    prices.record_snapshot(
        conn,
        ah,
        "auctionator",
        upload_at,
        [prices.Observation(1, 50, upload_at), prices.Observation(2, 50, upload_at)],
    )
    assert current(conn, ah) == {1: (50, upload_at), 2: (50, upload_at)}
    t1 = T0 + timedelta(hours=1)  # AHledger's next scan, after the upload, changed item 2 only
    api.set(HORDE.id, t1, {1: (10, 1), 2: (30, 4)})
    poll(conn, api, t1 + timedelta(minutes=5))
    assert current(conn, ah) == {1: (50, upload_at), 2: (30, t1)}


def test_a_wild_table_is_quarantined_and_not_judged_again(conn: Connection, api: FakeAHledger) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    items = range(1, 31)
    prices.record_snapshot(conn, ah, "auctionator", T0, [prices.Observation(i, 100, T0) for i in items])
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=100, scans_7d=5))  # as the merge would
    api.set(HORDE.id, T0, dict.fromkeys(items, (10000, 1)))
    got = poll(conn, api, FETCHED)
    assert got.quarantined and got.moved == 0
    assert set(prices.load_current(conn, ah).values()) == {100}
    assert poll(conn, api, FETCHED + timedelta(hours=1)).unchanged


def test_ahledger_scans_show_in_coverage(conn: Connection, api: FakeAHledger) -> None:
    api.set(HORDE.id, T0, {1: (20, 5)})
    poll(conn, api, FETCHED)
    (row,) = prices.coverage(conn, FOREVER, now=FETCHED)
    assert (row.realm, row.faction, row.sources) == ("Classic Beta PvE", "Horde", ("ahledger",))


def test_the_client_waits_out_rate_limits(api: FakeAHledger) -> None:
    waits: list[float] = []
    c = ahledger.Client(api, sleep=waits.append, api_key="k")
    api.throttle = 2
    assert "forever.normal.horde.us" in c.markets()
    assert 2.0 in waits and c.requests == 3
    api.throttle = ahledger.MAX_RETRIES + 1
    with pytest.raises(ahledger.AHledgerError, match="429"):
        c.markets()
    with pytest.raises(ahledger.AHledgerError, match="404"):
        c.text("/pricetable/forever.rp.horde.us")


def test_the_cli_polls_every_market(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], api: FakeAHledger
) -> None:
    for market in ahledger.markets(FOREVER):
        api.set(market.id, T0, {1: (20, 5)})
    del api.tables["forever.pvp.alliance.us"]  # nobody scanned there
    monkeypatch.setattr(ahledger.Client, "from_env", classmethod(lambda cls: client(api)))
    dbfile = str(tmp_path / "x.sqlite")
    with pytest.raises(SystemExit, match="1 of 4 AHledger markets failed"):
        cli.main(["--db", dbfile, "ahledger"])
    out = capsys.readouterr().out
    assert "forever.normal.horde.us: 1 items, 1 new or changed, 1 moved" in out
    assert "5 requests to AHledger." in out  # the market list and one table per market
    assert "forever.pvp.alliance.us: AHledger answered 404" in out
    with db.Database(db.sqlite_url(Path(dbfile))).begin() as conn:
        assert len(prices.coverage(conn, FOREVER)) == 3
