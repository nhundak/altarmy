"""Starting jobs on demand: Cloud Run's jobs hosted, a thread in development."""

import threading
from pathlib import Path

import pytest
from sqlalchemy import Connection

from altarmy_profit import addon_crates, db, jobs, launch, service
from altarmy_profit.versions import VERSIONS, GameVersion

from .conftest import FOREVER

LOCATION = "projects/alt-army-prod/locations/us-central1"


class FakeLauncher:
    """Records the versions whose ingest it was asked to start; raises `error` if set."""

    def __init__(self, error: str | None = None) -> None:
        self.started: list[str] = []
        self.error = error

    def ingest(self, version: GameVersion) -> str:
        if self.error:
            raise launch.LaunchError(self.error)
        self.started.append(version.key)
        return f"Started {version.key}."


def posting(status: int, text: str = "") -> tuple[list[str], launch.Transport]:
    posted: list[str] = []

    def post(url: str) -> tuple[int, str]:
        posted.append(url)
        return status, text

    return posted, post


def test_cloud_run_starts_the_environments_ingest_job() -> None:
    posted, post = posting(200, '{"name": "operations/1"}')
    said = launch.CloudRunJobs(LOCATION, "altarmy-staging", post).ingest(VERSIONS["forever"])
    assert posted == [f"https://run.googleapis.com/v2/{LOCATION}/jobs/altarmy-staging-ingest-forever:run"]
    assert "altarmy-staging-ingest-forever" in said


@pytest.mark.parametrize(
    ("status", "says"), [(403, "roles/run.invoker"), (404, "no Cloud Run job"), (500, "(500): down")]
)
def test_cloud_run_says_why_it_could_not_start_a_job(status: int, says: str) -> None:
    _, post = posting(status, "down")
    with pytest.raises(launch.LaunchError, match=says.replace("(", r"\(").replace(")", r"\)")):
        launch.CloudRunJobs(LOCATION, "altarmy", post).ingest(VERSIONS["tbc"])


def test_cloud_run_unreachable_is_a_launch_error() -> None:
    def post(url: str) -> tuple[int, str]:
        raise OSError("no credentials")

    with pytest.raises(launch.LaunchError, match="no credentials"):
        launch.CloudRunJobs(LOCATION, "altarmy", post).ingest(VERSIONS["forever"])


def test_from_env_prefers_cloud_run_and_never_runs_jobs_in_a_hosted_service(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("CLOUD_RUN_LOCATION", raising=False)
    monkeypatch.delenv("JOB_PREFIX", raising=False)
    sqlite = db.Database("sqlite:///dev.sqlite", migrate=False)
    postgres = db.Database("postgresql+psycopg://u:p@localhost/x", migrate=False)
    assert isinstance(launch.from_env(sqlite), launch.InProcessJobs)  # development
    assert launch.from_env(postgres) is None
    monkeypatch.setenv("CLOUD_RUN_LOCATION", LOCATION)
    monkeypatch.setenv("JOB_PREFIX", "altarmy")
    found = launch.from_env(postgres)
    assert isinstance(found, launch.CloudRunJobs)
    assert (found.location, found.prefix) == (LOCATION, "altarmy")


def test_in_process_runs_and_records_the_ingest_one_at_a_time(
    database: db.Database, conn: Connection, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    go = threading.Event()
    calls: list[tuple[str, bool]] = []

    def update(
        c: Connection, version: GameVersion, cache_dir: Path, *, only_if_new: bool = False
    ) -> tuple[str, bool, dict[str, int]]:
        assert go.wait(5)
        calls.append((version.key, only_if_new))
        return "1.2.3", False, {}

    monkeypatch.setattr(service, "update_game_data", update)
    monkeypatch.setattr(addon_crates, "regenerate", lambda database, game_version: None)
    launcher = launch.InProcessJobs(database, tmp_path)
    assert "Forever" in launcher.ingest(VERSIONS["forever"])
    with pytest.raises(launch.LaunchError, match="still running"):
        launcher.ingest(VERSIONS["forever"])
    go.set()
    finish()
    assert calls == [(FOREVER, True)]  # the newest build, unless it is loaded already
    run = jobs.latest(conn, FOREVER)["ingest"]
    assert (run.ok, run.summary) == (True, f"{VERSIONS['forever'].label} build 1.2.3 already loaded.")
    launcher.ingest(VERSIONS["forever"])  # free again
    finish()


def finish() -> None:
    """Wait for the in-process ingest thread."""
    for t in threading.enumerate():
        if t.name == "ingest-forever":
            t.join(5)
