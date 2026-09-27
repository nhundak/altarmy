"""Signing the watcher and Alt Army Sync in with an email and password, against a fake Firebase."""

import json
import urllib.parse
from collections.abc import Mapping
from pathlib import Path

import pytest

from altarmy_profit import signin
from altarmy_profit.signin import AuthConfig, Session

SITE = "https://site.test"
CONFIG = AuthConfig(SITE, "browser-key")


class FakeFirebase:
    """The site's /api/config and Firebase Auth's REST API, as a `signin.Transport`: accounts are
    {email: password}; ID tokens are "id:<email>:<n>" and refresh tokens "rt:<email>:<n>"."""

    def __init__(self, accounts: Mapping[str, str] | None = None, emulator: str | None = None) -> None:
        self.accounts = dict(accounts or {"me@example.com": "hunter22"})
        self.emulator = emulator
        self.seen: list[tuple[str, Mapping[str, str], bytes | None]] = []
        self.issued = 0
        self.revoked: set[str] = set()
        self.rotate = False  # refreshes hand out a new refresh token

    def _tokens(self, email: str) -> tuple[str, str]:
        self.issued += 1
        return f"id:{email}:{self.issued}", f"rt:{email}:{self.issued}"

    def __call__(self, url: str, headers: Mapping[str, str], body: bytes | None) -> tuple[int, bytes]:
        self.seen.append((url, headers, body))
        parts = urllib.parse.urlsplit(url)
        if parts.path == "/api/config":
            fb = {
                "api_key": "browser-key",
                "auth_domain": "x",
                "project_id": "p",
                "emulator_url": self.emulator,
            }
            return 200, json.dumps({"firebase": fb}).encode()
        if urllib.parse.parse_qs(parts.query).get("key") != ["browser-key"]:
            return 400, b'{"error": {"message": "API key not valid. Please pass a valid API key."}}'
        if parts.path.endswith("/v1/token"):
            form = urllib.parse.parse_qs((body or b"").decode())
            token = form["refresh_token"][0]
            email = token.split(":")[1]
            if token in self.revoked:
                return 400, b'{"error": {"message": "TOKEN_EXPIRED"}}'
            id_token, refresh = self._tokens(email)
            answer = {"id_token": id_token, "refresh_token": refresh if self.rotate else token}
            return 200, json.dumps({**answer, "expires_in": "3600", "user_id": f"uid-{email}"}).encode()
        data = json.loads(body or b"{}")
        email, password = data["email"], data["password"]
        if parts.path.endswith("accounts:signUp"):
            if email in self.accounts:
                return 400, b'{"error": {"message": "EMAIL_EXISTS"}}'
            if len(password) < 6:
                msg = "WEAK_PASSWORD : Password should be at least 6 characters"
                return 400, json.dumps({"error": {"message": msg}}).encode()
            self.accounts[email] = password
        elif self.accounts.get(email) != password:
            return 400, b'{"error": {"message": "INVALID_LOGIN_CREDENTIALS"}}'
        id_token, refresh = self._tokens(email)
        answer = {"localId": f"uid-{email}", "email": email, "idToken": id_token, "refreshToken": refresh}
        return 200, json.dumps({**answer, "expiresIn": "3600"}).encode()


def test_config_comes_from_the_site() -> None:
    fb = FakeFirebase()
    assert signin.fetch_config(SITE + "/", fb) == CONFIG
    fb.emulator = "http://127.0.0.1:9099/"
    assert signin.fetch_config(SITE, fb).emulator_url == "http://127.0.0.1:9099"
    with pytest.raises(signin.Unreachable, match="did not answer like an Alt Army site"):
        signin.fetch_config(SITE, lambda url, headers, body: (200, b"<html>"))


def test_signs_in_as_the_site_does() -> None:
    fb = FakeFirebase()
    session = signin.sign_in(CONFIG, " me@example.com ", "hunter22", fb, now=1000)
    assert session == Session(
        "uid-me@example.com", "me@example.com", "id:me@example.com:1", "rt:me@example.com:1", 4600
    )
    url, headers, body = fb.seen[-1]
    assert url == "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=browser-key"
    assert headers["Referer"] == "https://site.test/"  # the browser key only answers the site's origins
    assert json.loads(body or b"") == {
        "email": "me@example.com",
        "password": "hunter22",
        "returnSecureToken": True,
    }


def test_the_emulator_is_used_when_the_site_names_one() -> None:
    fb = FakeFirebase()
    signin.sign_in(AuthConfig(SITE, "browser-key", "http://127.0.0.1:9099"), "me@example.com", "hunter22", fb)
    assert fb.seen[-1][0].startswith(
        "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?"
    )


def test_refusals_read_like_the_site() -> None:
    fb = FakeFirebase()
    with pytest.raises(signin.SignInError, match="^Wrong email or password.$"):
        signin.sign_in(CONFIG, "me@example.com", "wrong", fb)
    with pytest.raises(signin.SignInError, match="already has an account"):
        signin.sign_up(CONFIG, "me@example.com", "hunter22", fb)
    with pytest.raises(signin.SignInError, match="at least 6 characters"):
        signin.sign_up(CONFIG, "new@example.com", "abc", fb)

    def blocked(url: str, headers: Mapping[str, str], body: bytes | None) -> tuple[int, bytes]:
        msg = "Requests from referer <empty> are blocked."
        return 403, json.dumps({"error": {"message": msg, "status": "PERMISSION_DENIED"}}).encode()

    with pytest.raises(signin.SignInError, match="refused this app"):
        signin.sign_in(CONFIG, "me@example.com", "hunter22", blocked)


def test_sign_up_makes_an_account_and_signs_in() -> None:
    fb = FakeFirebase()
    session = signin.sign_up(CONFIG, "new@example.com", "secret1", fb)
    assert (session.email, fb.accounts["new@example.com"]) == ("new@example.com", "secret1")
    assert fb.seen[-1][0].endswith("/v1/accounts:signUp?key=browser-key")


def test_unreachable_is_retried_not_signed_out() -> None:
    def down(url: str, headers: Mapping[str, str], body: bytes | None) -> tuple[int, bytes]:
        raise OSError("no network")

    with pytest.raises(signin.Unreachable, match="identitytoolkit.googleapis.com"):
        signin.sign_in(CONFIG, "me@example.com", "hunter22", down)
    with pytest.raises(signin.Unreachable, match="503"):
        signin.sign_in(CONFIG, "me@example.com", "hunter22", lambda u, h, b: (503, b""))


def test_credentials_refresh_an_hourly_token_and_save_rotated_ones() -> None:
    fb = FakeFirebase()
    now = [1000.0]
    saved: list[Session] = []
    creds = signin.Credentials(
        CONFIG, "me@example.com", "rt:me@example.com:0", fb, lambda: now[0], saved.append
    )
    assert creds() == "id:me@example.com:1"  # no ID token yet: refreshed
    assert fb.seen[-1][0] == "https://securetoken.googleapis.com/v1/token?key=browser-key"
    assert fb.seen[-1][1]["Content-Type"] == "application/x-www-form-urlencoded"
    now[0] += 3000
    assert creds() == "id:me@example.com:1"  # still valid
    now[0] += 400  # within REFRESH_EARLY of expiring
    assert creds() == "id:me@example.com:2"
    assert saved == []  # Firebase kept the refresh token: nothing to save
    fb.rotate = True
    now[0] += 3600
    assert creds() == "id:me@example.com:3"
    assert [s.refresh_token for s in saved] == ["rt:me@example.com:3"]


def test_a_revoked_sign_in_signs_out() -> None:
    fb = FakeFirebase()
    fb.revoked.add("rt:me@example.com:0")
    creds = signin.Credentials(CONFIG, "me@example.com", "rt:me@example.com:0", fb)
    with pytest.raises(signin.SignedOut):
        creds()


def test_credentials_from_a_fresh_sign_in_need_no_refresh() -> None:
    fb = FakeFirebase()
    session = signin.sign_in(CONFIG, "me@example.com", "hunter22", fb, now=1000)
    creds = signin.Credentials.of(CONFIG, session, transport=fb, clock=lambda: 1000.0)
    assert (creds(), creds.email, len(fb.seen)) == ("id:me@example.com:1", "me@example.com", 1)


def test_saved_sign_ins_per_site(tmp_path: Path) -> None:
    path = tmp_path / "sub" / "auth.json"
    assert signin.load_saved(path, SITE) is None
    signin.save(path, SITE + "/", Session("u", "me@example.com", "id", "rt", 0))
    signin.save(path, "https://other.test", Session("u", "alt@example.com", "id", "rt2", 0))
    assert signin.load_saved(path, SITE) == ("me@example.com", "rt")
    assert "hunter22" not in path.read_text() and '"id"' not in path.read_text()  # only the refresh token
    signin.save(path, SITE, None)
    assert signin.load_saved(path, SITE) is None
    assert signin.load_saved(path, "https://other.test") == ("alt@example.com", "rt2")
    path.write_text("not json")
    assert signin.load_saved(path, SITE) is None
