"""The Discord relay: Cloud Monitoring's Pub/Sub notifications as Discord messages."""

import base64
import json
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


def envelope(payload: object) -> dict[str, Any]:
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    return {"message": {"data": data, "messageId": "1"}, "subscription": "projects/p/subscriptions/s"}


def relay(status: int | Exception) -> tuple[TestClient, list[dict[str, Any]]]:
    posted: list[dict[str, Any]] = []

    def post(message: dict[str, Any]) -> int:
        if isinstance(status, Exception):
            raise status
        posted.append(message)
        return status

    return TestClient(alerts.create_relay_app(post)), posted


def test_relay_posts_a_notification_once() -> None:
    client, posted = relay(204)
    r = client.post("/", json=envelope(incident()))
    assert r.status_code == 204
    assert [embed(m)["title"] for m in posted] == ["altarmy job failed"]


def test_relay_acknowledges_what_it_cannot_read() -> None:
    client, posted = relay(204)
    for body in [b"not json", json.dumps({"message": {}}).encode(), json.dumps(envelope("x")).encode()]:
        assert client.post("/", content=body).status_code == 204
    bad_data = {"message": {"data": "%%%"}}
    assert client.post("/", json=bad_data).status_code == 204
    # "x" is valid JSON: posted as a generic embed; the rest never reached Discord
    assert len(posted) == 1


def test_relay_drops_what_discord_refuses() -> None:
    client, _ = relay(400)
    assert client.post("/", json=envelope(incident())).status_code == 204


def test_relay_asks_for_a_retry_when_discord_is_down() -> None:
    for status in (429, 500, OSError("no network")):
        client, _ = relay(status)
        assert client.post("/", json=envelope(incident())).status_code == 503
