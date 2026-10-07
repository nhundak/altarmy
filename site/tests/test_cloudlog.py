"""Structured logs on Cloud Run: one JSON line per record, exceptions as Error Reporting events."""

import json
import logging
import sys
from collections.abc import Iterator

import pytest

from altarmy_site import cloudlog

LOGGERS = ("", "uvicorn", "uvicorn.error", "uvicorn.access")


def record(exc: bool) -> logging.LogRecord:
    exc_info = None
    if exc:
        try:
            raise RuntimeError("boom")
        except RuntimeError:
            exc_info = sys.exc_info()
    return logging.LogRecord("altarmy_site.x", logging.ERROR, __file__, 1, "it %s", ("failed",), exc_info)


def test_a_record_is_one_json_line() -> None:
    line = cloudlog.JsonFormatter("altarmy").format(record(exc=False))
    assert "\n" not in line
    out = json.loads(line)
    assert out == {"severity": "ERROR", "message": "it failed", "logger": "altarmy_site.x"}


def test_an_exception_is_an_error_reporting_event() -> None:
    out = json.loads(cloudlog.JsonFormatter("altarmy-merge").format(record(exc=True)))
    assert out["@type"] == cloudlog.ERROR_EVENT
    assert out["serviceContext"] == {"service": "altarmy-merge"}
    assert out["message"].startswith("it failed\nTraceback (most recent call last):")
    assert "RuntimeError: boom" in out["message"]


@pytest.fixture
def saved_logging() -> Iterator[None]:
    loggers = [logging.getLogger(name) for name in LOGGERS]
    saved = [(lg.handlers[:], lg.level, lg.propagate) for lg in loggers]
    hook = sys.excepthook
    yield
    for lg, (handlers, level, propagate) in zip(loggers, saved, strict=True):
        lg.handlers[:] = handlers
        lg.setLevel(level)
        lg.propagate = propagate
    sys.excepthook = hook


@pytest.mark.usefixtures("saved_logging")
def test_configure_does_nothing_off_cloud_run(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("K_SERVICE", raising=False)
    monkeypatch.delenv("CLOUD_RUN_JOB", raising=False)
    before = logging.getLogger().handlers[:]
    assert cloudlog.configure() is None
    assert logging.getLogger().handlers == before


@pytest.mark.usefixtures("saved_logging")
def test_configure_on_cloud_run(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CLOUD_RUN_JOB", raising=False)
    monkeypatch.setenv("K_SERVICE", "altarmy-staging")
    assert cloudlog.configure() == "altarmy-staging"
    (handler,) = logging.getLogger().handlers
    assert isinstance(handler.formatter, cloudlog.JsonFormatter)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):  # each line once, through the root
        assert not logging.getLogger(name).handlers
        assert logging.getLogger(name).propagate
    assert sys.excepthook is not sys.__excepthook__


@pytest.mark.usefixtures("saved_logging")
def test_an_uncaught_exception_is_logged(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("CLOUD_RUN_JOB", "altarmy-merge")
    cloudlog.configure()
    try:
        raise ValueError("bad")
    except ValueError:
        sys.excepthook(*sys.exc_info())
    lines = [json.loads(line) for line in capsys.readouterr().err.splitlines()]
    assert lines[-1]["severity"] == "CRITICAL"
    assert lines[-1]["serviceContext"] == {"service": "altarmy-merge"}
    assert "ValueError: bad" in lines[-1]["message"]
