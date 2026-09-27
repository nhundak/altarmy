"""Sign the watcher and Alt Army Sync in to the site's Firebase project with an email and password.

The site's public web config (`GET /api/config`: the browser API key, and the Auth emulator's URL when
developing) says where. `sign_in` and `sign_up` call Identity Toolkit's REST API and give a `Session`. Only
its refresh token is saved (never the password); `Credentials` trades it for an ID token, which lasts an
hour, through the Token Service, and uploads send that token as the browser does. The browser key is
restricted to the site's origins (see README), so every request names the site as its Referer.
Standard library only, like `watch`.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REFRESH_EARLY = 300  # seconds before an ID token expires that a new one is fetched

# (url, headers, body or None for a GET) -> (HTTP status, response body); `urllib_transport` or a test double
Transport = Callable[[str, Mapping[str, str], bytes | None], tuple[int, bytes]]

# Identity Toolkit's error codes, as a person should read them. Unlisted codes are shown as they are.
MESSAGES = {
    "INVALID_LOGIN_CREDENTIALS": "Wrong email or password.",
    "INVALID_PASSWORD": "Wrong email or password.",
    "EMAIL_NOT_FOUND": "Wrong email or password.",
    "EMAIL_EXISTS": "That email already has an account: sign in instead.",
    "WEAK_PASSWORD": "Passwords need at least 6 characters.",
    "INVALID_EMAIL": "That doesn't look like an email address.",
    "MISSING_EMAIL": "Enter your email address.",
    "MISSING_PASSWORD": "Enter your password.",
    "TOO_MANY_ATTEMPTS_TRY_LATER": "Too many attempts: wait a few minutes and try again.",
    "USER_DISABLED": "This account is disabled.",
    "OPERATION_NOT_ALLOWED": "The site does not allow signing in with a password.",
}
# Refresh refusals that mean the saved sign-in is gone for good (password changed, account deleted, ...).
SIGNED_OUT = {"TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "USER_DISABLED", "USER_NOT_FOUND"}


class SignInError(Exception):
    """Firebase refused: the message is for the person signing in."""


class SignedOut(Exception):
    """The saved sign-in no longer works (or the server refused its token): sign in again."""


class Unreachable(Exception):
    """The site or Firebase could not be reached, or failed: try again later."""


@dataclass(frozen=True)
class AuthConfig:
    site: str  # the site's URL, no trailing slash: the Referer the browser key allows
    api_key: str
    emulator_url: str | None = None  # the Firebase Auth emulator, when the site is a dev server


@dataclass(frozen=True)
class Session:
    uid: str
    email: str
    id_token: str
    refresh_token: str
    expires_at: float  # time.time() when the ID token expires


def urllib_transport(url: str, headers: Mapping[str, str], body: bytes | None) -> tuple[int, bytes]:
    method = "GET" if body is None else "POST"
    request = urllib.request.Request(url, data=body, headers=dict(headers), method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as res:
            return int(res.status), bytes(res.read())
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _call(transport: Transport, url: str, headers: Mapping[str, str], body: bytes | None) -> tuple[int, Any]:
    try:
        status, text = transport(url, headers, body)
    except (OSError, urllib.error.URLError) as e:
        raise Unreachable(f"could not reach {urllib.parse.urlsplit(url).netloc}: {e}") from e
    if status >= 500 or status == 429:
        raise Unreachable(f"{urllib.parse.urlsplit(url).netloc} answered {status}")
    try:
        return status, json.loads(text)
    except ValueError:
        return status, None


def fetch_config(site: str, transport: Transport = urllib_transport) -> AuthConfig:
    """The Firebase project the site signs in with (its `GET /api/config`)."""
    site = site.rstrip("/")
    status, body = _call(transport, f"{site}/api/config", {"Accept": "application/json"}, None)
    try:
        fb = body["firebase"]
        api_key = str(fb["api_key"])
        emulator = fb.get("emulator_url")
    except (TypeError, KeyError) as e:
        raise Unreachable(f"{site} did not answer like an Alt Army site ({status})") from e
    return AuthConfig(site, api_key, str(emulator).rstrip("/") if emulator else None)


def _base(config: AuthConfig, host: str) -> str:
    return f"{config.emulator_url}/{host}" if config.emulator_url else f"https://{host}"


def _headers(config: AuthConfig, content_type: str) -> dict[str, str]:
    return {"Content-Type": content_type, "Referer": f"{config.site}/", "User-Agent": "altarmy-profit"}


def _error_code(body: Any) -> str:
    """Identity Toolkit's error code, e.g. "WEAK_PASSWORD" from "WEAK_PASSWORD : Password should be ..."."""
    try:
        message = str(body["error"]["message"])
    except (TypeError, KeyError):
        return ""
    return message.split(" : ", 1)[0].strip()


def _refused(status: int, body: Any) -> str:
    code = _error_code(body)
    if status == 403:  # the key's restrictions (a Referer or API it does not allow)
        return f"The site's sign-in refused this app: {code or status}."
    return MESSAGES.get(code, code or f"Sign-in failed ({status}).")


def _account(
    config: AuthConfig, method: str, email: str, password: str, transport: Transport, now: float
) -> Session:
    key = urllib.parse.quote(config.api_key)
    url = f"{_base(config, 'identitytoolkit.googleapis.com')}/v1/accounts:{method}?key={key}"
    payload = json.dumps({"email": email.strip(), "password": password, "returnSecureToken": True}).encode()
    status, body = _call(transport, url, _headers(config, "application/json"), payload)
    if status != 200 or not isinstance(body, dict):
        raise SignInError(_refused(status, body))
    try:
        return Session(
            uid=str(body["localId"]),
            email=str(body.get("email") or email.strip()),
            id_token=str(body["idToken"]),
            refresh_token=str(body["refreshToken"]),
            expires_at=now + float(body.get("expiresIn", 3600)),
        )
    except (KeyError, ValueError) as e:
        raise SignInError("Firebase answered without a sign-in token.") from e


def sign_in(
    config: AuthConfig,
    email: str,
    password: str,
    transport: Transport = urllib_transport,
    now: float | None = None,
) -> Session:
    """Sign in to an existing account; SignInError with a readable reason if refused."""
    return _account(
        config, "signInWithPassword", email, password, transport, time.time() if now is None else now
    )


def sign_up(
    config: AuthConfig,
    email: str,
    password: str,
    transport: Transport = urllib_transport,
    now: float | None = None,
) -> Session:
    """Create an account (it starts empty: a browser's anonymous session is not part of it) and sign in."""
    return _account(config, "signUp", email, password, transport, time.time() if now is None else now)


def refresh(
    config: AuthConfig, session: Session, transport: Transport = urllib_transport, now: float | None = None
) -> Session:
    """A new ID token for the session; SignedOut if its refresh token no longer works."""
    now = time.time() if now is None else now
    key = urllib.parse.quote(config.api_key)
    url = f"{_base(config, 'securetoken.googleapis.com')}/v1/token?key={key}"
    form = urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": session.refresh_token})
    status, body = _call(transport, url, _headers(config, "application/x-www-form-urlencoded"), form.encode())
    if status != 200 or not isinstance(body, dict):
        code = _error_code(body)
        if code in SIGNED_OUT or status in (400, 401):
            raise SignedOut(MESSAGES.get(code, "the saved sign-in no longer works"))
        raise SignInError(_refused(status, body))
    try:
        return Session(
            uid=str(body.get("user_id") or session.uid),
            email=session.email,
            id_token=str(body["id_token"]),
            refresh_token=str(body.get("refresh_token") or session.refresh_token),
            expires_at=now + float(body.get("expires_in", 3600)),
        )
    except (KeyError, ValueError) as e:
        raise SignedOut("Firebase answered without a sign-in token") from e


class Credentials:
    """A saved sign-in (email and refresh token) that hands out a valid ID token: call it for one.

    `on_change` gets the session whenever Firebase rotates its refresh token, so it can be saved again.
    Raises SignedOut when the sign-in is gone and Unreachable when Firebase can't be reached.
    """

    def __init__(
        self,
        config: AuthConfig,
        email: str,
        refresh_token: str,
        transport: Transport = urllib_transport,
        clock: Callable[[], float] = time.time,
        on_change: Callable[[Session], None] | None = None,
    ) -> None:
        self.config = config
        self.session = Session("", email, "", refresh_token, 0.0)
        self.transport = transport
        self.clock = clock
        self.on_change = on_change

    @classmethod
    def of(cls, config: AuthConfig, session: Session, **kwargs: Any) -> Credentials:
        """Credentials that start from a fresh sign-in (no refresh needed until its token expires)."""
        made = cls(config, session.email, session.refresh_token, **kwargs)
        made.session = session
        return made

    @property
    def email(self) -> str:
        return self.session.email

    def __call__(self) -> str:
        if not self.session.id_token or self.clock() >= self.session.expires_at - REFRESH_EARLY:
            try:
                fresh = refresh(self.config, self.session, self.transport, self.clock())
            except SignInError as e:  # e.g. the key's restrictions: nothing the user can retry
                raise SignedOut(str(e)) from e
            rotated = fresh.refresh_token != self.session.refresh_token
            self.session = fresh
            if rotated and self.on_change is not None:
                self.on_change(fresh)
        return self.session.id_token


# --- the CLI watcher's saved sign-in (the tray keeps its own in sync.json) ----------------------------
DEFAULT_AUTH = Path.home() / ".altarmy-profit" / "watch-auth.json"


def load_saved(path: Path, site: str) -> tuple[str, str] | None:
    """(email, refresh token) saved for `site`, or None."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        saved = data[site.rstrip("/")]
        email, token = saved["email"], saved["refresh_token"]
    except (OSError, ValueError, TypeError, KeyError):
        return None
    return (email, token) if isinstance(email, str) and isinstance(token, str) and token else None


def save(path: Path, site: str, session: Session | None) -> None:
    """Save (or with None, forget) the sign-in for `site`: a refresh token, never a password."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    key = site.rstrip("/")
    if session is None:
        data.pop(key, None)
    else:
        data[key] = {"email": session.email, "refresh_token": session.refresh_token}
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1), encoding="utf-8")
    tmp.replace(path)
