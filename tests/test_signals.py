from collections.abc import Mapping
from typing import Any

import pytest

from altarmy_profit import signals


class FakeSignals:
    """Records what would be published: (auction house id, game version, price version)."""

    def __init__(self) -> None:
        self.published: list[tuple[int, str, int]] = []

    def publish(self, auction_house_id: int, game_version: str, version: int) -> None:
        self.published.append((auction_house_id, game_version, version))


class BrokenSignals:
    def publish(self, auction_house_id: int, game_version: str, version: int) -> None:
        raise RuntimeError("Firestore is down")


def test_the_document_holds_only_the_version() -> None:
    doc: Mapping[str, Any] = signals.document("forever", 7)
    assert {k: v for k, v in doc.items() if k != "updated_at"} == {"game_version": "forever", "version": 7}
    assert "updated_at" in doc  # the server's time, set by Firestore


def test_publish_all_sends_every_house_and_never_raises(caplog: pytest.LogCaptureFixture) -> None:
    fake = FakeSignals()
    assert signals.publish_all(fake, "forever", {3: 2, 1: 5}) == 2
    assert fake.published == [(1, "forever", 5), (3, "forever", 2)]
    assert signals.publish_all(BrokenSignals(), "forever", {1: 5}) == 0
    assert "Firestore is down" in caplog.text


def test_from_env_needs_a_firebase_project(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    assert isinstance(signals.from_env(), signals.NoSignals)
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-altarmy")
    monkeypatch.setenv("PRICE_SIGNALS", "off")
    assert isinstance(signals.from_env(), signals.NoSignals)
    monkeypatch.delenv("PRICE_SIGNALS")
    found = signals.from_env()
    assert isinstance(found, signals.FirestoreSignals)
    assert found.project_id == "demo-altarmy"
