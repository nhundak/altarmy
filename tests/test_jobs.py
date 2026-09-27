"""Job runs: recording a CLI job's run, and reading them back for the Admin page."""

import sys
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import Connection, select

from altarmy_profit import db, jobs, schema

from .conftest import FOREVER

T0 = datetime(2026, 9, 27, 12, 0, tzinfo=UTC)


def runs(conn: Connection) -> list[tuple[str, str | None, bool | None, str, bool]]:
    t = schema.job_runs
    rows = conn.execute(
        select(t.c.job, t.c.game_version, t.c.ok, t.c.summary, t.c.finished_at.is_not(None)).order_by(t.c.id)
    )
    return [(r[0], r[1], r[2], r[3], r[4]) for r in rows]


def test_a_run_is_recorded_with_what_the_job_said(
    database: db.Database, conn: Connection, capsys: pytest.CaptureFixture[str]
) -> None:
    with jobs.recording(database, "ingest", FOREVER) as run:
        assert runs(conn) == [("ingest", FOREVER, None, "", False)]  # running
        run.say("one")
        run.say("two")
    assert capsys.readouterr().out == "one\ntwo\n"
    assert runs(conn) == [("ingest", FOREVER, True, "one\ntwo", True)]


def test_a_failing_run_is_recorded_and_the_failure_raised(database: db.Database, conn: Connection) -> None:
    with pytest.raises(RuntimeError), jobs.recording(database, "merge") as run:
        run.say("started")
        raise RuntimeError("boom")
    with pytest.raises(SystemExit), jobs.recording(database, "ahledger"):
        sys.exit("1 of 4 AHledger markets failed.")
    with pytest.raises(SystemExit), jobs.recording(database, "prune"):
        sys.exit(2)
    with pytest.raises(SystemExit), jobs.recording(database, "prune"):
        sys.exit(0)
    assert runs(conn) == [
        ("merge", None, False, "started\nRuntimeError: boom", True),
        ("ahledger", None, False, "1 of 4 AHledger markets failed.", True),
        ("prune", None, False, "Exit code 2", True),
        ("prune", None, True, "", True),
    ]


def test_a_long_summary_keeps_its_end(conn: Connection) -> None:
    run_id = jobs.start(conn, "merge", now=T0)
    jobs.finish(conn, run_id, False, "x" * jobs.SUMMARY_MAX + "the error", now=T0)
    (run,) = jobs.recent(conn, FOREVER)
    assert len(run.summary) == jobs.SUMMARY_MAX
    assert run.summary.startswith("…") and run.summary.endswith("the error")


def test_recent_and_latest_cover_the_version_and_every_version(conn: Connection) -> None:
    def ran(job: str, version: str | None, hours: int, ok: bool = True) -> int:
        run_id = jobs.start(conn, job, version, now=T0 + timedelta(hours=hours))
        jobs.finish(conn, run_id, ok, f"{job} {hours}", now=T0 + timedelta(hours=hours, minutes=1))
        return run_id

    ran("ingest", "tbc", 0)
    ran("ingest", FOREVER, 1)
    ran("merge", None, 2, ok=False)
    ran("merge", None, 3)
    jobs.start(conn, "prune", now=T0 + timedelta(hours=4))  # still running
    assert [r.summary for r in jobs.recent(conn, FOREVER)] == ["", "merge 3", "merge 2", "ingest 1"]
    assert [r.summary for r in jobs.recent(conn, FOREVER, limit=2)] == ["", "merge 3"]
    latest = jobs.latest(conn, FOREVER)
    assert sorted(latest) == ["ingest", "merge", "prune"]
    assert (latest["ingest"].game_version, latest["ingest"].started_at) == (FOREVER, T0 + timedelta(hours=1))
    assert (latest["merge"].ok, latest["merge"].summary) == (True, "merge 3")
    assert (latest["prune"].ok, latest["prune"].finished_at) == (None, None)
    assert jobs.latest(conn, "tbc")["ingest"].summary == "ingest 0"


def test_late_is_twice_the_cadence(conn: Connection) -> None:
    assert jobs.late("merge", None, T0)
    assert not jobs.late("merge", T0 - timedelta(hours=2), T0)
    assert jobs.late("merge", T0 - timedelta(hours=2, minutes=1), T0)
    assert not jobs.late("ingest", T0 - timedelta(hours=47), T0)
    assert set(jobs.CADENCE) == set(schema.JOBS)
