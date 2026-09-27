"""AHledger's crowdsourced auction house prices (https://ahledger.com/developers), polled into the price
store beside users' uploads. Its terms: credit AHledger with a link wherever its prices are shown, and
don't resell them as a feed.

A market (`forever.normal.horde.us`) is one ruleset and faction; `GameVersion.ahledger_realms` names each
ruleset's realm, so a market prices one (realm, faction) auction house. A poll costs one request per
market: the price table. It carries one time, that of its newest scan, and no per-row times, so the last
table is kept (`feed_tables`) and a poll records only the rows that are new or changed since, as seen
when the new table was (its time, never before the previous stamp: the table is cached for minutes). The
very first table of a market is recorded as seen when it was fetched: it starts the market's history, and
uploads come after it. The newest seen_at wins between feed and uploads (`prices.record_snapshot`).

HTTP is the standard library's; the transport is injectable for tests. Bad responses raise ValueError.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import Connection, select

from . import db, prices, schema, versions

API = "https://api.ahledger.com/v1"
REGION = "us"
FACTIONS = ("alliance", "horde")
FEED_TRUST = 0.5  # how far AHledger's tables are trusted when screened (0..1, as an uploader's)
MIN_INTERVAL = 0.25  # seconds between requests: the API allows 300 a minute
MAX_RETRIES = 3  # 429s waited out per request
MAX_WAIT = 60.0  # longest Retry-After honoured, in seconds
TIMEOUT = 30.0

# url, headers -> (status, body, response headers)
Transport = Callable[[str, Mapping[str, str]], tuple[int, bytes, Mapping[str, str]]]


class AHledgerError(Exception):
    """The API could not be reached or answered with an error."""


@dataclass(frozen=True)
class Row:
    min_buyout: int
    median: int
    quantity: int


@dataclass(frozen=True)
class Table:
    market: str
    scanned_at: datetime  # the header's time: that of the newest scan in the table
    rows: dict[int, Row]


def parse_table(text: str) -> Table:
    """A `/v1/pricetable` body: `AHL1|<game>/<ruleset>/<faction>/<region>|<unix time>|<count>`, then one
    `item:median:minBuyout:quantity:median7d:median30d:low30d:high30d` line per item."""
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        raise ValueError("empty AHledger price table")
    head = lines[0].split("|")
    if len(head) != 4 or head[0] != "AHL1":
        raise ValueError(f"not an AHledger price table: {lines[0][:80]!r}")
    market = ".".join(head[1].split("/"))
    try:
        scanned_at = datetime.fromtimestamp(_int(head[2], "time"), UTC)
    except (OverflowError, OSError) as e:
        raise ValueError(f"bad time in AHledger price table: {head[2][:40]!r}") from e
    count = _int(head[3], "count")
    rows: dict[int, Row] = {}
    for line in lines[1:]:
        fields = line.split(":")
        if len(fields) < 4:
            raise ValueError(f"bad AHledger price table row: {line[:80]!r}")
        item, median, min_buyout, quantity = (_int(f, "row") for f in fields[:4])
        if item <= 0 or min_buyout <= 0:
            continue
        rows[item] = Row(min_buyout, median, quantity)
    if count != len(lines) - 1:
        raise ValueError(f"AHledger price table promised {count} rows, has {len(lines) - 1}")
    return Table(market, scanned_at, rows)


def _int(text: str, what: str) -> int:
    try:
        return int(text)
    except ValueError:
        raise ValueError(f"bad {what} in AHledger price table: {text[:40]!r}") from None


# --- HTTP ------------------------------------------------------------------------------------------
def urllib_transport(url: str, headers: Mapping[str, str]) -> tuple[int, bytes, Mapping[str, str]]:
    req = urllib.request.Request(url, headers=dict(headers))
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            return int(res.status), res.read(), dict(res.headers)
    except urllib.error.HTTPError as e:
        return int(e.code), e.read(), dict(e.headers or {})
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise AHledgerError(f"could not reach AHledger: {e}") from e


class Client:
    """The API at `base`, one request at a time, at most one per MIN_INTERVAL; waits out 429s."""

    def __init__(
        self,
        transport: Transport = urllib_transport,
        *,
        api_key: str | None = None,
        base: str = API,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.transport = transport
        self.base = base.rstrip("/")
        self.headers = {"User-Agent": "altarmy-profit", "Accept": "*/*"}
        if api_key:
            self.headers["x-ahl-api-key"] = api_key
        self.sleep = sleep
        self.clock = clock
        self.requests = 0
        self._last: float | None = None

    @classmethod
    def from_env(cls) -> Client:
        return cls(api_key=os.environ.get("AHLEDGER_API_KEY") or None)

    def get(self, path: str) -> bytes:
        """The body of GET `path`; AHledgerError for anything but 200 (after waiting out 429s)."""
        for attempt in range(MAX_RETRIES + 1):
            if self._last is not None:
                wait = MIN_INTERVAL - (self.clock() - self._last)
                if wait > 0:
                    self.sleep(wait)
            status, body, headers = self.transport(self.base + path, self.headers)
            self._last = self.clock()
            self.requests += 1
            if status == 200:
                return body
            if status != 429 or attempt == MAX_RETRIES:
                raise AHledgerError(f"AHledger answered {status} for {path}")
            self.sleep(min(_retry_after(headers), MAX_WAIT))
        raise AssertionError("unreachable")

    def markets(self) -> set[str]:
        try:
            return {str(m["id"]) for m in json.loads(self.get("/markets"))["markets"]}
        except (ValueError, KeyError, TypeError) as e:
            raise ValueError(f"bad AHledger market list: {e}") from e

    def text(self, path: str) -> str:
        try:
            return self.get(path).decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"AHledger's answer for {path} is not text: {e}") from e


def _retry_after(headers: Mapping[str, str]) -> float:
    for name, value in headers.items():
        if name.lower() == "retry-after":
            try:
                return max(0.0, float(value))
            except ValueError:
                break
    return MAX_WAIT


# --- polling ---------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Market:
    id: str  # forever.normal.horde.us
    realm: str
    faction: str  # Horde | Alliance


def markets(game_version: str) -> list[Market]:
    """The AHledger markets of the version's realms (`GameVersion.ahledger_realms`)."""
    version = versions.get(game_version)
    return [
        Market(f"{version.key}.{ruleset}.{faction}.{REGION}", realm, faction.title())
        for ruleset, realm in sorted(version.ahledger_realms.items())
        for faction in FACTIONS
    ]


@dataclass(frozen=True)
class Polled:
    market: str
    auction_house_id: int
    items: int  # rows in AHledger's table
    recorded: int  # rows recorded (new or changed since the last table)
    moved: int  # of them, items whose current price moved
    quarantined: bool = False  # the table's changes were far off recent prices and not used
    unchanged: bool = False  # the table was no newer than the last one

    @property
    def summary(self) -> str:
        if self.unchanged:
            return f"{self.market}: no newer scan"
        if self.quarantined:
            return f"{self.market}: {self.recorded} prices not used: they differ widely from recent scans"
        return f"{self.market}: {self.items} items, {self.recorded} new or changed, {self.moved} moved"


@dataclass(frozen=True)
class _Previous:
    table: Table
    stamped_at: datetime


def poll_market(
    conn: Connection, game_version: str, market: Market, client: Client, now: datetime | None = None
) -> Polled:
    """Record what AHledger's table for `market` has new or changed since the last one (see the module
    doc), and keep it as the market's last table."""
    fetched_at = db.utc(now or db.utcnow())
    ah = prices.auction_house(conn, game_version, market.realm, market.faction)
    body = client.text(f"/pricetable/{market.id}")
    table = parse_table(body)
    if table.market != market.id:
        raise ValueError(f"asked AHledger for {market.id}, got {table.market}")
    previous = _previous(conn, market.id)
    if previous is not None and table.scanned_at <= previous.table.scanned_at:
        return Polled(market.id, ah, len(table.rows), 0, 0, unchanged=True)
    if previous is None:
        stamp, rows = fetched_at, table.rows
    else:
        stamp = max(table.scanned_at, previous.stamped_at)
        rows = {i: r for i, r in table.rows.items() if _changed(r, previous.table.rows.get(i))}
    observations = [prices.Observation(i, r.min_buyout, stamp, r.quantity) for i, r in sorted(rows.items())]
    got = prices.Recorded(0)
    if observations:
        got = prices.record_screened(conn, ah, prices.AHLEDGER, stamp, observations, trust=FEED_TRUST)
        if not got.quarantined:
            prices.record_daily_observations(conn, ah, observations)
    row = {
        "source": prices.AHLEDGER,
        "market": market.id,
        "auction_house_id": ah,
        "scanned_at": table.scanned_at,
        "stamped_at": stamp,
        "fetched_at": fetched_at,
        "body": body,
    }
    db.upsert(conn, schema.feed_tables, [row], ["source", "market"])
    return Polled(market.id, ah, len(table.rows), len(observations), got.moved, got.quarantined)


def _changed(row: Row, before: Row | None) -> bool:
    return before is None or (row.min_buyout, row.quantity) != (before.min_buyout, before.quantity)


def _previous(conn: Connection, market: str) -> _Previous | None:
    t = schema.feed_tables
    found = conn.execute(
        select(t.c.body, t.c.stamped_at).where(t.c.source == prices.AHLEDGER, t.c.market == market)
    ).first()
    if found is None:
        return None
    try:
        return _Previous(parse_table(found.body), db.utc(found.stamped_at))
    except ValueError:
        return None  # unreadable: start over
