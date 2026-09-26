"""Who is asking, and what their tier lets them see. No database or HTTP here.

Every visitor is signed in with Firebase (anonymously at first); the front end sends the Firebase ID
token and a `TokenVerifier` turns it into claims. Linking an email account keeps the uid and moves the
user from the free to the linked tier. Development signs in against the Firebase Auth emulator.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Literal, Protocol, runtime_checkable

Tier = Literal["free", "linked"]


@dataclass(frozen=True)
class User:
    uid: str
    tier: Tier

    @property
    def linked(self) -> bool:
        return self.tier == "linked"


class InvalidToken(Exception):
    """The ID token is missing, malformed, expired or not for this project."""


class TokenVerifier(Protocol):
    def verify(self, token: str) -> Mapping[str, Any]:
        """The token's claims; InvalidToken if it does not verify."""
        ...


class AccountError(Exception):
    """The sign-in provider could not delete the account."""


@runtime_checkable
class AccountAdmin(Protocol):
    def delete_user(self, uid: str) -> None:
        """Delete the sign-in account (already gone is fine); AccountError if that failed."""
        ...


def user_from_claims(claims: Mapping[str, Any]) -> User:
    """Linked unless the token came from an anonymous sign-in."""
    uid = claims.get("uid") or claims.get("sub")
    if not isinstance(uid, str) or not uid:
        raise InvalidToken("token has no uid")
    firebase = claims.get("firebase")
    provider = firebase.get("sign_in_provider") if isinstance(firebase, Mapping) else None
    return User(uid, "free" if provider == "anonymous" else "linked")


@dataclass(frozen=True)
class FirebaseConfig:
    """What the front end needs to sign in (public values), plus the emulator when developing."""

    project_id: str
    api_key: str
    auth_domain: str
    emulator_host: str | None  # host:port of the Firebase Auth emulator, e.g. 127.0.0.1:9099

    @classmethod
    def from_env(cls) -> FirebaseConfig:
        """`FIREBASE_PROJECT_ID` (required), `FIREBASE_API_KEY`, `FIREBASE_AUTH_DOMAIN` and the emulator's
        `FIREBASE_AUTH_EMULATOR_HOST`, which firebase-admin reads too."""
        project_id = os.environ.get("FIREBASE_PROJECT_ID")
        if not project_id:
            raise ValueError(
                "FIREBASE_PROJECT_ID is not set (npm run dev sets demo-altarmy and the Auth emulator;"
                " the deploy sets the real project)."
            )
        emulator = os.environ.get("FIREBASE_AUTH_EMULATOR_HOST") or None
        return cls(
            project_id=project_id,
            # the emulator accepts any API key
            api_key=os.environ.get("FIREBASE_API_KEY") or ("emulator" if emulator else ""),
            auth_domain=os.environ.get("FIREBASE_AUTH_DOMAIN") or f"{project_id}.firebaseapp.com",
            emulator_host=emulator,
        )


class FirebaseVerifier:
    """Verifies Firebase ID tokens with firebase-admin (the `ui` extra), and deletes accounts. Verifying
    needs only the project id (the signing keys are Google's public certificates); deleting needs
    credentials with Firebase Auth admin rights (on Cloud Run, the service account's). With
    `FIREBASE_AUTH_EMULATOR_HOST` set, firebase-admin talks to the emulator instead."""

    def __init__(self, project_id: str) -> None:
        import firebase_admin

        name = f"altarmy-{project_id}"
        try:
            self._app = firebase_admin.get_app(name)
        except ValueError:
            self._app = firebase_admin.initialize_app(options={"projectId": project_id}, name=name)

    def verify(self, token: str) -> Mapping[str, Any]:
        from firebase_admin import auth

        try:
            claims: Mapping[str, Any] = auth.verify_id_token(token, app=self._app)
        except (ValueError, auth.InvalidIdTokenError, auth.ExpiredIdTokenError) as e:
            raise InvalidToken(str(e)) from e
        return claims

    def delete_user(self, uid: str) -> None:
        from firebase_admin import auth, exceptions

        try:
            auth.delete_user(uid, app=self._app)
        except auth.UserNotFoundError:
            pass
        except (ValueError, exceptions.FirebaseError) as e:
            raise AccountError(str(e)) from e
