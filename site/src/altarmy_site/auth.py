"""Who is asking, and what their tier lets them see. No database or HTTP here.

Every visitor is signed in with Firebase (anonymously at first); the front end sends the Firebase ID
token and a `TokenVerifier` turns it into claims. Linking an email account keeps the uid and moves the
user from the free to the linked tier. Development signs in against the Firebase Auth emulator.

Site admins carry the custom claim `admin: true`, which only the Admin SDK sets (`altarmy-site admin
grant`): it is never stored in the database, and a token shows it once it is issued after the grant.
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
    admin: bool = False  # the Firebase custom claim `admin: true`: sees the Admin page

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


@runtime_checkable
class AdminRoster(Protocol):
    """Who is a site admin: the `admin` custom claim on sign-in accounts."""

    def set_admin(self, email: str, on: bool) -> str:
        """Grant (`on`) or revoke the claim on the account with `email`; returns its uid. AccountError if
        there is no such account or the sign-in provider failed."""
        ...

    def admins(self) -> list[tuple[str, str]]:
        """(uid, email) of every account with the claim, by email."""
        ...


def user_from_claims(claims: Mapping[str, Any]) -> User:
    """Linked unless the token came from an anonymous sign-in; an admin if a linked account's token carries
    the custom claim `admin: true` (custom claims are top-level keys of the decoded token)."""
    uid = claims.get("uid") or claims.get("sub")
    if not isinstance(uid, str) or not uid:
        raise InvalidToken("token has no uid")
    firebase = claims.get("firebase")
    provider = firebase.get("sign_in_provider") if isinstance(firebase, Mapping) else None
    anonymous = provider == "anonymous"
    return User(uid, "free" if anonymous else "linked", admin=not anonymous and claims.get("admin") is True)


@dataclass(frozen=True)
class FirebaseConfig:
    """What the front end needs to sign in (public values), plus the emulator when developing."""

    project_id: str
    api_key: str
    auth_domain: str
    emulator_host: str | None  # host:port of the Firebase Auth emulator, e.g. 127.0.0.1:9099
    firestore_emulator_host: str | None = None  # host:port of the Firestore emulator (price signals)

    @classmethod
    def from_env(cls) -> FirebaseConfig:
        """`FIREBASE_PROJECT_ID` (required), `FIREBASE_API_KEY`, `FIREBASE_AUTH_DOMAIN` and the emulators'
        `FIREBASE_AUTH_EMULATOR_HOST` and `FIRESTORE_EMULATOR_HOST`, which firebase-admin reads too."""
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
            firestore_emulator_host=os.environ.get("FIRESTORE_EMULATOR_HOST") or None,
        )


class FirebaseVerifier:
    """Verifies Firebase ID tokens with firebase-admin (the `ui` extra), deletes accounts and keeps the
    admin roster. Verifying needs only the project id (the signing keys are Google's public certificates);
    the rest needs credentials with Firebase Auth admin rights (on Cloud Run, the service account's; from
    the CLI, Application Default Credentials). With `FIREBASE_AUTH_EMULATOR_HOST` set, firebase-admin talks
    to the emulator instead."""

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

    def set_admin(self, email: str, on: bool) -> str:
        from firebase_admin import auth, exceptions

        try:
            user = auth.get_user_by_email(email, app=self._app)
            claims = {k: v for k, v in (user.custom_claims or {}).items() if k != "admin"}
            if on:
                claims["admin"] = True
            auth.set_custom_user_claims(user.uid, claims or None, app=self._app)
        except auth.UserNotFoundError as e:
            raise AccountError(f"no account has the email {email}") from e
        except (ValueError, exceptions.FirebaseError) as e:
            raise AccountError(str(e)) from e
        return str(user.uid)

    def admins(self) -> list[tuple[str, str]]:
        from firebase_admin import auth, exceptions

        try:
            found = [
                (str(u.uid), str(u.email or ""))
                for u in auth.list_users(app=self._app).iterate_all()
                if (u.custom_claims or {}).get("admin") is True
            ]
        except (ValueError, exceptions.FirebaseError) as e:
            raise AccountError(str(e)) from e
        return sorted(found, key=lambda a: (a[1], a[0]))
