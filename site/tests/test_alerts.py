"""The Discord relay: Cloud Monitoring's and Error Reporting's webhook notifications as Discord messages."""

import base64
from typing import Any

from fastapi.testclient import TestClient

from altarmy_profit import alerts


def incident(**changes: Any) -> dict[str, Any]:
    """A notification in Cloud Monitoring's Pub/Sub schema (version 1.2), for a log-based policy."""
    body: dict[str, Any] = {
        "incident_id": "0.abc",
        "url": "https://console.cloud.google.com/monitoring/alerting/incidents/0.abc?project=alt-army-prod",
        "state": "open",
        "summary": "Log match condition fired for Cloud Run Job with {job_name=altarmy-staging-merge}",
        "policy_name": "altarmy job failed",
        "condition_name": "a job execution failed",
        "resource": {"type": "cloud_run_job", "labels": {"job_name": "altarmy-staging-merge"}},
        "documentation": {"content": "A Cloud Run job failed.", "mime_type": "text/markdown"},
    }
    body.update(changes)
    return {"version": "1.2", "incident": body}


def embed(message: dict[str, Any]) -> dict[str, Any]:
    (only,) = message["embeds"]
    assert isinstance(only, dict)
    return only


def test_open_incident() -> None:
    e = embed(alerts.discord_message(incident()))
    assert e["title"] == "altarmy job failed"
    assert e["url"].startswith("https://console.cloud.google.com/monitoring/alerting/incidents/")
    assert e["color"] == alerts.RED
    assert "Log match condition fired" in e["description"]
    assert "A Cloud Run job failed." in e["description"]
    assert {"name": "job_name", "value": "altarmy-staging-merge", "inline": True} in e["fields"]


def test_closed_incident_says_resolved() -> None:
    e = embed(alerts.discord_message(incident(state="closed")))
    assert e["title"] == "Resolved: altarmy job failed"
    assert e["color"] == alerts.GREEN


def test_long_texts_are_cut_to_discords_limits() -> None:
    e = embed(alerts.discord_message(incident(policy_name="p" * 400, summary="s" * 9000)))
    assert len(e["title"]) <= alerts.TITLE_MAX
    assert len(e["description"]) <= alerts.DESCRIPTION_MAX
    assert e["description"].endswith("…")


def test_an_unknown_payload_is_posted_as_its_json() -> None:
    e = embed(alerts.discord_message({"something": "else", "count": 3}))
    assert e["title"] == "Alert"
    assert '"something": "else"' in e["description"]
    assert len(e["description"]) <= alerts.DESCRIPTION_MAX


def error_report(**changes: Any) -> dict[str, Any]:
    """An Error Reporting webhook notification (version 1.0)."""
    body: dict[str, Any] = {
        "version": "1.0",
        "subject": "[alt-army-prod] New error in altarmy-ingest-forever: ProgrammingError",
        "group_info": {
            "project_id": "alt-army-prod",
            "detail_link": "https://console.cloud.google.com/errors/detail/abc?project=alt-army-prod",
        },
        "exception_info": {"type": "ProgrammingError", "message": 'column "area" does not exist'},
        "event_info": {
            "log_message": "uncaught ProgrammingError\nTraceback (most recent call last):\n  ...",
            "request_method": "",
            "request_url": "",
            "service": "altarmy-ingest-forever",
            "version": "",
            "response_status": "0",
        },
    }
    body.update(changes)
    return body


def test_an_error_report() -> None:
    e = embed(alerts.discord_message(error_report()))
    assert e["title"] == "[alt-army-prod] New error in altarmy-ingest-forever: ProgrammingError"
    assert e["url"].startswith("https://console.cloud.google.com/errors/detail/")
    assert e["color"] == alerts.RED
    assert e["description"].startswith('**ProgrammingError**: column "area" does not exist\n```\nuncaught')
    assert {"name": "service", "value": "altarmy-ingest-forever", "inline": True} in e["fields"]
    assert not any(f["name"] in ("version", "request") for f in e["fields"])


def test_a_long_traceback_is_cut_to_fit() -> None:
    long = error_report(event_info={"log_message": "x" * 9000, "service": "altarmy"})
    e = embed(alerts.discord_message(long))
    assert len(e["description"]) <= alerts.DESCRIPTION_MAX
    assert e["description"].endswith("```")


def basic(user: str, password: str) -> dict[str, str]:
    return {"Authorization": "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()}


AUTH = basic(alerts.USERNAME, "s3cret")


def relay(status: int | Exception) -> tuple[TestClient, list[dict[str, Any]]]:
    posted: list[dict[str, Any]] = []

    def post(message: dict[str, Any]) -> int:
        if isinstance(status, Exception):
            raise status
        posted.append(message)
        return status

    return TestClient(alerts.create_relay_app("s3cret", post)), posted


def test_relay_posts_a_notification_once() -> None:
    client, posted = relay(204)
    assert client.post("/", json=incident(), headers=AUTH).status_code == 204
    assert client.post("/", json=error_report(), headers=AUTH).status_code == 204
    assert [embed(m)["title"][:18] for m in posted] == ["altarmy job failed", "[alt-army-prod] Ne"]


def test_relay_challenges_without_the_password() -> None:
    client, posted = relay(204)
    for headers in [
        {},
        basic(alerts.USERNAME, "wrong"),
        basic("someone", "s3cret"),
        {"Authorization": "Basic %%"},
    ]:
        r = client.post("/", json=incident(), headers=headers)
        assert r.status_code == 401
        assert r.headers["WWW-Authenticate"].startswith("Basic ")
    assert posted == []


def test_relay_refuses_what_is_not_json() -> None:
    client, posted = relay(204)
    assert client.post("/", content=b"not json", headers=AUTH).status_code == 400
    assert client.post("/", json="x", headers=AUTH).status_code == 204  # JSON: posted as a generic embed
    assert len(posted) == 1


def test_relay_says_when_discord_failed() -> None:
    for status in (400, 429, 500, OSError("no network")):
        client, _ = relay(status)
        assert client.post("/", json=incident(), headers=AUTH).status_code == 502
