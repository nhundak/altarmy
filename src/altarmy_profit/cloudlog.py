"""Logs on Cloud Run as Cloud Logging's structured JSON lines: one line per record, with its severity, so a
multi-line traceback stays one entry, and every record carrying an exception is an Error Reporting event
(`@type` ReportedErrorEvent, grouped per service or job), which notifies the Discord relay (`alerts`).

`configure` does it for the service (`api.create_app`) and the jobs (`cli.main`), and only on Cloud Run
(`K_SERVICE` or `CLOUD_RUN_JOB` set): elsewhere logs stay plain text.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from types import TracebackType

ERROR_EVENT = "type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent"
# the loggers uvicorn's default logging config gives handlers of their own and stops propagating
UVICORN = ("uvicorn", "uvicorn.access")

log = logging.getLogger(__name__)


class JsonFormatter(logging.Formatter):
    """A record as one JSON line. An exception's traceback follows the message, which Error Reporting
    reads, and `service` names the group's service."""

    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        message = record.getMessage()
        out: dict[str, object] = {"severity": record.levelname, "message": message, "logger": record.name}
        if record.exc_info:
            out["message"] = f"{message}\n{self.formatException(record.exc_info)}"
            out["@type"] = ERROR_EVENT
            out["serviceContext"] = {"service": self.service}
        return json.dumps(out)


def cloud_run_name() -> str | None:
    """The Cloud Run service or job this runs as, else None."""
    return os.environ.get("K_SERVICE") or os.environ.get("CLOUD_RUN_JOB") or None


def configure() -> str | None:
    """On Cloud Run, log JSON lines to stderr (the root and uvicorn's loggers, at INFO) and log uncaught
    exceptions through them; the service or job's name, else None (and nothing changed). Run uvicorn with
    `log_config=None` afterwards, or its own config replaces uvicorn's handlers."""
    service = cloud_run_name()
    if not service:
        return None
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter(service))
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)
    for name in UVICORN:  # each line once: through the root's handler alone
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
    sys.excepthook = _log_uncaught
    return service


def _log_uncaught(kind: type[BaseException], value: BaseException, traceback: TracebackType | None) -> None:
    if issubclass(kind, KeyboardInterrupt):
        sys.__excepthook__(kind, value, traceback)
        return
    log.critical("uncaught %s", kind.__name__, exc_info=(kind, value, traceback))
