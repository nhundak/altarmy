"""Price signals: tell open browsers that an auction house's prices changed, through Firestore.

Each auction house has a document `priceSignals/<auction house id>` holding only its `price_version` (the
counter `prices.record_snapshot` and the merge bump), never prices. The front end listens to the selected
house's document and refetches when the version passes the one it has (`lib/signals.ts`); the security
rules (`firestore.rules`) let signed-in users read these documents and nobody write them: only the Admin
SDK here does.

Publish after the transaction that moved the version committed, so a browser that refetches at once sees
the new prices. A signal is a nudge: failing to send one is logged and never fails the upload or job (the
browser's status poll still catches up).
"""

from __future__ import annotations

import logging
import os
from collections.abc import Mapping
from typing import Any, Protocol

log = logging.getLogger(__name__)

COLLECTION = "priceSignals"


class Signals(Protocol):
    def publish(self, auction_house_id: int, game_version: str, version: int) -> None:
        """Announce the auction house's new price version; may raise on a network failure."""
        ...


class NoSignals:
    """Sends nothing: a CLI run without a Firebase project, or `PRICE_SIGNALS=off`."""

    def publish(self, auction_house_id: int, game_version: str, version: int) -> None:
        pass


def document(game_version: str, version: int) -> dict[str, Any]:
    """A signal document's fields."""
    from firebase_admin import firestore

    return {"version": version, "game_version": game_version, "updated_at": firestore.SERVER_TIMESTAMP}


class FirestoreSignals:
    """Writes signal documents with firebase-admin (the `ui` extra) in the Firebase project's Firestore:
    on Cloud Run with the service account's credentials, from the CLI with Application Default
    Credentials. With `FIRESTORE_EMULATOR_HOST` set, the client talks to the emulator instead. The client
    is made on first use, so building one costs nothing."""

    def __init__(self, project_id: str) -> None:
        self.project_id = project_id
        self._client: Any = None

    def _db(self) -> Any:
        if self._client is None:
            import firebase_admin
            from firebase_admin import firestore

            name = f"altarmy-{self.project_id}"  # the app `auth.FirebaseVerifier` uses too
            try:
                app = firebase_admin.get_app(name)
            except ValueError:
                app = firebase_admin.initialize_app(options={"projectId": self.project_id}, name=name)
            self._client = firestore.client(app)
        return self._client

    def publish(self, auction_house_id: int, game_version: str, version: int) -> None:
        self._db().collection(COLLECTION).document(str(auction_house_id)).set(document(game_version, version))


def for_project(project_id: str | None) -> Signals:
    """Firestore signals in the project, else none (also with `PRICE_SIGNALS=off`: a development API
    signed in against another environment's Firebase project must not signal that environment)."""
    if not project_id or os.environ.get("PRICE_SIGNALS") == "off":
        return NoSignals()
    return FirestoreSignals(project_id)


def from_env() -> Signals:
    """Signals in `FIREBASE_PROJECT_ID`'s project (the CLI's jobs), see `for_project`."""
    return for_project(os.environ.get("FIREBASE_PROJECT_ID"))


def publish_all(signals: Signals, game_version: str, versions: Mapping[int, int]) -> int:
    """Publish {auction house id: price version}, in id order; returns how many were sent. Failures are
    logged, never raised."""
    sent = 0
    for ah, version in sorted(versions.items()):
        try:
            signals.publish(ah, game_version, version)
        except Exception as e:  # a nudge: never fail the caller over it
            log.warning("price signal for auction house %s not sent: %s", ah, e)
        else:
            sent += 1
    return sent
