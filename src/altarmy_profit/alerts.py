"""The Discord relay: Cloud Monitoring notifies a Pub/Sub topic (its alert policies and Error Reporting),
whose push subscription calls this service (`altarmy-profit alert-relay`, Cloud Run `altarmy-alerts`;
deploy/setup.sh `discord`), which posts each notification to a Discord channel's webhook
(`DISCORD_WEBHOOK_URL`). Monitoring has no Discord channel, and Discord refuses its webhook channel's JSON.

`discord_message` is pure. The relay acknowledges (2xx) whatever it cannot read or Discord refuses, so a bad
message is not redelivered for a day, and asks for a retry (503) only while Discord is unreachable. Needs
the `ui` extra (FastAPI), like the API.
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import os
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

from fastapi import FastAPI, Request, Response
from starlette.concurrency import run_in_threadpool

log = logging.getLogger(__name__)

RED = 0xD83C3E
GREEN = 0x3BA55C
GREY = 0x99AAB5
TITLE_MAX = 256  # Discord's limits on an embed
DESCRIPTION_MAX = 4096
FIELD_MAX = 1024
USER_AGENT = "altarmy-alerts (https://github.com/ntower/altarmy-profit, 1)"  # Discord wants one

# a Discord message -> the webhook's HTTP status; OSError when Discord can't be reached
Post = Callable[[dict[str, Any]], int]


def _cut(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _str(value: object) -> str:
    return value if isinstance(value, str) else ""


def discord_message(notification: Mapping[str, Any]) -> dict[str, Any]:
    """The Discord message (one embed) for a Cloud Monitoring notification: the policy, its summary and
    documentation, the resource's labels (which job or service, so staging's are told apart) and a link to
    the incident; red while open, green once closed. Anything else is posted as its JSON."""
    incident = notification.get("incident")
    if not isinstance(incident, Mapping) or not _str(incident.get("policy_name")):
        text = json.dumps(notification, indent=1, sort_keys=True, default=str)
        body = _cut(text, DESCRIPTION_MAX - 8)
        return {"embeds": [{"title": "Alert", "description": f"```\n{body}\n```", "color": GREY}]}
    closed = incident.get("state") == "closed"
    policy = _str(incident.get("policy_name"))
    documentation = incident.get("documentation")
    doc = _str(documentation.get("content")) if isinstance(documentation, Mapping) else ""
    description = "\n\n".join(t for t in (_str(incident.get("summary")), doc) if t)
    resource = incident.get("resource")
    labels = resource.get("labels") if isinstance(resource, Mapping) else None
    fields = [
        {"name": _cut(str(k), TITLE_MAX), "value": _cut(str(v), FIELD_MAX), "inline": True}
        for k, v in sorted(labels.items() if isinstance(labels, Mapping) else [])
        if k != "project_id" and v
    ]
    embed: dict[str, Any] = {
        "title": _cut(f"Resolved: {policy}" if closed else policy, TITLE_MAX),
        "description": _cut(description, DESCRIPTION_MAX),
        "color": GREEN if closed else RED,
        "fields": fields[:25],
    }
    url = _str(incident.get("url"))
    if url.startswith("https://"):
        embed["url"] = url
    return {"embeds": [embed]}


def webhook_post(url: str) -> Post:
    """POSTs messages to a Discord webhook; HTTP errors come back as their status."""

    def post(message: dict[str, Any]) -> int:
        request = urllib.request.Request(
            url,
            data=json.dumps(message).encode(),
            headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return int(response.status)
        except urllib.error.HTTPError as e:
            return e.code

    return post


def _notification(body: bytes) -> Any:
    """The notification in a Pub/Sub push envelope; ValueError if there is none."""
    try:
        envelope = json.loads(body)
        data = envelope["message"]["data"]
        return json.loads(base64.b64decode(data, validate=True))
    except (ValueError, KeyError, TypeError, binascii.Error) as e:
        raise ValueError(f"not a Pub/Sub push envelope: {e}") from e


def create_relay_app(post: Post | None = None) -> FastAPI:
    """The relay: `POST /` takes Pub/Sub push envelopes. `post` defaults to `DISCORD_WEBHOOK_URL`'s
    webhook (KeyError without it). Cloud Run lets only the subscription's service account call it."""
    send = post or webhook_post(os.environ["DISCORD_WEBHOOK_URL"])
    app = FastAPI(title="altarmy-alerts", docs_url=None, redoc_url=None, openapi_url=None)

    @app.post("/")
    async def relay(request: Request) -> Response:
        try:
            notification = _notification(await request.body())
        except ValueError as e:
            log.warning("dropped a message: %s", e)
            return Response(status_code=204)
        message = discord_message(
            notification if isinstance(notification, Mapping) else {"data": notification}
        )
        try:
            status = await run_in_threadpool(send, message)
        except OSError as e:
            log.warning("Discord unreachable, to be retried: %s", e)
            return Response(status_code=503)
        if status == 429 or status >= 500:
            log.warning("Discord answered %s, to be retried", status)
            return Response(status_code=503)
        if not 200 <= status < 300:
            log.error("Discord refused a message (%s): %s", status, json.dumps(message)[:500])
        return Response(status_code=204)

    return app
