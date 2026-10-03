"""The Discord relay: Cloud Monitoring's alert policies and Error Reporting notify a basic-auth webhook
channel ("altarmy Discord", deploy/setup.sh `discord`) pointing at this service (`altarmy-profit
alert-relay`, Cloud Run `altarmy-alerts`), which posts each notification to a Discord channel's webhook
(`DISCORD_WEBHOOK_URL`). Monitoring has no Discord channel, Discord refuses its webhook JSON, and Error
Reporting notifies only email, Slack and webhooks (not Pub/Sub).

Webhooks need a public endpoint, so the service is public and every request must carry the channel's
password (`RELAY_PASSWORD`, secret `alerts-relay-password`) as HTTP basic auth; without it the relay answers
401 with the challenge Monitoring expects. `discord_message` is pure. Needs the `ui` extra (FastAPI).
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import os
import secrets
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

from fastapi import FastAPI, Request, Response
from starlette.concurrency import run_in_threadpool

log = logging.getLogger(__name__)

USERNAME = "altarmy"  # the channel's basic-auth user; the password is the secret
RED = 0xD83C3E
GREEN = 0x3BA55C
GREY = 0x99AAB5
TITLE_MAX = 256  # Discord's limits on an embed
DESCRIPTION_MAX = 4096
FIELD_MAX = 1024
USER_AGENT = "altarmy-alerts (https://github.com/ntower/altarmy, 1)"  # Discord wants one

# a Discord message -> the webhook's HTTP status; OSError when Discord can't be reached
Post = Callable[[dict[str, Any]], int]


def _cut(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _str(value: object) -> str:
    return value if isinstance(value, str) else ""


def _map(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _field(name: str, value: str) -> dict[str, Any]:
    return {"name": _cut(name, TITLE_MAX), "value": _cut(value, FIELD_MAX), "inline": True}


def discord_message(notification: Mapping[str, Any]) -> dict[str, Any]:
    """The Discord message (one embed) for a notification: a Monitoring incident (`incident`), an Error
    Reporting error (`exception_info`), else its JSON."""
    incident = _map(notification.get("incident"))
    if _str(incident.get("policy_name")):
        return {"embeds": [_incident(incident)]}
    if isinstance(notification.get("exception_info"), Mapping):
        return {"embeds": [_error(notification)]}
    text = json.dumps(notification, indent=1, sort_keys=True, default=str)
    body = _cut(text, DESCRIPTION_MAX - 8)
    return {"embeds": [{"title": "Alert", "description": f"```\n{body}\n```", "color": GREY}]}


def _incident(incident: Mapping[str, Any]) -> dict[str, Any]:
    """An alert policy's incident: the policy, its summary and documentation, the resource's labels (which
    job or service, so staging's are told apart) and a link; red while open, green once closed."""
    closed = incident.get("state") == "closed"
    policy = _str(incident.get("policy_name"))
    doc = _str(_map(incident.get("documentation")).get("content"))
    description = "\n\n".join(t for t in (_str(incident.get("summary")), doc) if t)
    labels = _map(_map(incident.get("resource")).get("labels"))
    fields = [_field(str(k), str(v)) for k, v in sorted(labels.items()) if k != "project_id" and v]
    embed: dict[str, Any] = {
        "title": _cut(f"Resolved: {policy}" if closed else policy, TITLE_MAX),
        "description": _cut(description, DESCRIPTION_MAX),
        "color": GREEN if closed else RED,
        "fields": fields[:25],
    }
    url = _str(incident.get("url"))
    if url.startswith("https://"):
        embed["url"] = url
    return embed


def _error(notification: Mapping[str, Any]) -> dict[str, Any]:
    """An Error Reporting notification (a new error group, or a resolved one back): the exception, the
    logged traceback, where it happened and a link to the group."""
    exception = _map(notification.get("exception_info"))
    event = _map(notification.get("event_info"))
    kind, message = _str(exception.get("type")), _str(exception.get("message"))
    headline = f"**{kind}**: {message}" if kind else message
    logged = _str(event.get("log_message"))
    trace = f"\n```\n{_cut(logged, DESCRIPTION_MAX - len(headline) - 16)}\n```" if logged else ""
    request = " ".join(t for t in (_str(event.get("request_method")), _str(event.get("request_url"))) if t)
    fields = [
        _field(name, value)
        for name, value in (
            ("service", _str(event.get("service"))),
            ("version", _str(event.get("version"))),
            ("request", request),
            ("status", str(event.get("response_status") or "")),
        )
        if value
    ]
    embed: dict[str, Any] = {
        "title": _cut(_str(notification.get("subject")) or kind or "Error", TITLE_MAX),
        "description": _cut(headline + trace, DESCRIPTION_MAX),
        "color": RED,
        "fields": fields,
    }
    url = _str(_map(notification.get("group_info")).get("detail_link"))
    if url.startswith("https://"):
        embed["url"] = url
    return embed


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


def authorized(header: str | None, password: str) -> bool:
    """Whether an Authorization header is basic auth as USERNAME with `password`."""
    scheme, _, encoded = (header or "").partition(" ")
    if scheme.lower() != "basic":
        return False
    try:
        user, _, given = base64.b64decode(encoded, validate=True).decode().partition(":")
    except (binascii.Error, UnicodeDecodeError):
        return False
    return secrets.compare_digest(user.encode(), USERNAME.encode()) & secrets.compare_digest(
        given.encode(), password.encode()
    )


def create_relay_app(password: str | None = None, post: Post | None = None) -> FastAPI:
    """The relay: `POST /` takes a notification's JSON from a basic-auth webhook channel. `password`
    defaults to `RELAY_PASSWORD`, `post` to `DISCORD_WEBHOOK_URL`'s webhook (KeyError without either)."""
    password = password or os.environ["RELAY_PASSWORD"]
    send = post or webhook_post(os.environ["DISCORD_WEBHOOK_URL"])
    app = FastAPI(title="altarmy-alerts", docs_url=None, redoc_url=None, openapi_url=None)

    @app.post("/")
    async def relay(request: Request) -> Response:
        if not authorized(request.headers.get("authorization"), password):
            return Response(status_code=401, headers={"WWW-Authenticate": 'Basic realm="altarmy-alerts"'})
        try:
            notification = json.loads(await request.body())
        except ValueError as e:
            log.warning("not JSON: %s", e)
            return Response(status_code=400)
        message = discord_message(
            notification if isinstance(notification, Mapping) else {"data": notification}
        )
        try:
            status = await run_in_threadpool(send, message)
        except OSError as e:
            log.error("Discord unreachable, a notification is lost: %s", e)
            return Response(status_code=502)
        if not 200 <= status < 300:
            log.error("Discord answered %s to a notification: %s", status, json.dumps(message)[:500])
            return Response(status_code=502)
        return Response(status_code=204)

    return app
