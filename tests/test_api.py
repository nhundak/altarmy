import gzip
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Connection, select

from altarmy_profit import (
    ahledger,
    altarmy,
    auth,
    db,
    ingest,
    jobs,
    merge,
    prices,
    ratelimit,
    schema,
    service,
    store,
    uploads,
)
from altarmy_profit.altarmy import Character, Profession
from altarmy_profit.api import create_app
from altarmy_profit.auctionator import DayStats, ItemPrice
from altarmy_profit.versions import GameVersion

from .conftest import FOREVER, ME, set_prices
from .test_altarmy import ALTARMY_SV
from .test_auctionator import _entry, _saved_variables
from .test_auth import FakeVerifier
from .test_signals import FakeSignals

FIREBASE = auth.FirebaseConfig("demo-altarmy", "key", "demo-altarmy.firebaseapp.com", None)
EMULATOR = auth.FirebaseConfig(  # as `npm run dev` runs it
    "demo-altarmy", "key", "demo-altarmy.firebaseapp.com", "127.0.0.1:9099", "127.0.0.1:8080"
)
FREE = {"Authorization": "Bearer anonymous:guest"}  # tokens as `FakeVerifier` reads them: an anonymous user
LINKED = {"Authorization": "Bearer google.com:g1"}  # a user with an account
SIGNED_IN = {"Authorization": f"Bearer password:{ME}"}  # the `client` fixture's default: `ME`, linked
ADMIN = {"Authorization": "Bearer password:a1:admin"}  # a linked user with the admin claim


def make_client(
    database: db.Database,
    game_versions: dict[str, GameVersion],
    static_dir: Path,
    *,
    verifier: FakeVerifier | None = None,
    limits: ratelimit.Limits | None = None,
    firebase: auth.FirebaseConfig = FIREBASE,
) -> TestClient:
    """The app with fake tokens (see `FakeVerifier`), asking about Forever unless a request passes another
    game_version, signed in as `ME` unless a request sends other headers."""
    app = create_app(
        game_versions,
        database=database,
        static_dir=static_dir,
        verifier=verifier or FakeVerifier(),
        firebase=firebase,
        limits=limits,
        signals=FakeSignals(),
    )
    c = TestClient(app)
    c.params = c.params.set("game_version", "forever")
    c.headers.update(SIGNED_IN)
    return c


@pytest.fixture
def client(
    tmp_path: Path, vendor_csv: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> TestClient:
    """Signed in as `ME`; shares the `conn` fixture's database. FREE and LINKED sign in as others."""
    return make_client(database, game_versions, tmp_path / "nodist")


def with_tailor(conn: Connection) -> None:
    """Store the Alt Army test characters and select the realm/faction of the one who knows the robe."""
    store.save_characters(conn, ME, FOREVER, altarmy.parse_characters(ALTARMY_SV))
    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")


@pytest.fixture
def priced(db2_paths: dict[str, Path], conn: Connection) -> Connection:
    """The client's database with game data, prices linen=20, thread=100 on Classic Beta PvE's auction
    house and a selected tailor there who knows the Green Robe."""
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    with_tailor(conn)
    return conn


def test_empty_db(client: TestClient, database: db.Database) -> None:
    status = client.get("/api/status").json()
    assert status["recipes"] == 0
    assert status["build"] is None
    assert (status["characters"], status["selection"], status["data_version"]) == (0, None, 0)
    assert client.get("/api/characters").json() == {
        "groups": [],
        "selection": None,
        "imported_at": None,
        "imported_via": None,
        "auto_import_at": None,
    }
    assert client.get("/api/rank").json()["results"] == []


def one_craft(client: TestClient) -> None:
    """Rank and evaluate single crafts (a batch of 1), for tests about prices rather than sessions."""
    assert client.put("/api/time", json={"config": {"batch": 1}}).is_success


def test_rank_known_recipes(client: TestClient, priced: Connection) -> None:
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["recipe"] == "Green Robe"
    assert r["profession"] == "Tailoring"
    assert (r["crafters"], r["crafter"]) == (["Tailor Guy"], "Tailor Guy")
    assert body["classes"] == {"Tailor Guy": "MAGE"}
    assert (r["output_name"], r["output_count"]) == ("Green Robe", 1)
    # a session of the time settings' batch (10 crafts by default), as the expanded row plans it
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (10, 3000, 5000, 2000)
    assert r["roi"] == pytest.approx(2 / 3)
    assert r["best_exit"] == "vendor"
    assert [(s["action"], s["name"], s["quantity"], s["value"], s["via"]) for s in r["steps"]] == [
        ("buy", "Linen Cloth", 100, -2000, "ah"),
        ("buy", "Coarse Thread", 10, -1000, "ah"),
        ("craft", "Green Robe", 10, 0, "Green Robe"),
        ("sell", "Green Robe", 10, 5000, "vendor"),
    ]
    assert {"kind": "vendor", "value": 500, "materials": [], "postage": 0, "mail_to": ""} in r["exits"]
    assert (r["postage"], r["mail_to"]) == (0, "")
    tree = r["tree"]
    assert (tree["item_id"], tree["quantity"], tree["cost"], tree["via"], tree["crafts"]) == (
        3,
        10,
        3000,
        "Green Robe",
        10,
    )
    assert [(n["item_id"], n["quantity"], n["cost"], n["source"], n["inputs"]) for n in tree["inputs"]] == [
        (1, 100, 2000, "ah", []),
        (2, 10, 1000, "ah", []),
    ]
    one_craft(client)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (1, 300, 500, 200)


def test_rank_buys_reagents_from_vendors(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    set_prices(conn, {1: 20})  # thread has no AH price, but vendors sell it for 11c
    one_craft(client)
    with_tailor(conn)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["cost"] == 200 + 11
    assert (r["steps"][1]["name"], r["steps"][1]["via"]) == ("Coarse Thread", "vendor")
    assert r["tree"]["inputs"][1]["source"] == "vendor"
    assert (body["items"]["2"]["vendor_price"], body["items"]["1"]["vendor_price"]) == (11, None)


def with_enchanter(conn: Connection) -> None:
    """Add an enchanter (who can't tailor) to the tailor's realm/faction."""
    enchanter = Character(
        "Classic Beta PvE", "Enchy", "Horde", "PRIEST", 20, (Profession("Enchanting", 60, 75, frozenset()),)
    )
    store.save_characters(conn, ME, FOREVER, [*altarmy.parse_characters(ALTARMY_SV), enchanter])


def add_disenchant(conn: Connection, chance: float, min_count: int, max_count: int) -> None:
    """Green armor disenchants into linen."""
    conn.execute(
        schema.disenchant.insert().values(
            game_version=FOREVER,
            item_class=4,
            quality=2,
            min_ilvl=0,
            max_ilvl=1000,
            result_item_id=1,
            chance=chance,
            min_count=min_count,
            max_count=max_count,
        )
    )


def test_rank_sends_disenchant_materials(client: TestClient, priced: Connection) -> None:
    add_disenchant(priced, 0.5, 1, 3)  # robe -> 1-3 linen
    with_enchanter(priced)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    (de,) = [e for e in r["exits"] if e["kind"] == "disenchant"]
    assert de["materials"] == [
        {"item_id": 1, "name": "Linen Cloth", "chance": 0.5, "min_count": 1, "max_count": 3, "value": 19}
    ]
    assert all(e["materials"] == [] for e in r["exits"] if e["kind"] != "disenchant")


def test_rank_mails_disenchants_to_an_enchanter(client: TestClient, priced: Connection) -> None:
    one_craft(client)
    add_disenchant(priced, 1.0, 100, 100)  # robe -> 100 linen
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "vendor"  # nobody on the realm can disenchant

    with_enchanter(priced)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["best_exit"], r["postage"], r["mail_to"], r["cost"]) == ("disenchant", 30, "Enchy", 330)
    assert ("mail", "Green Robe", 1, -30, "Enchy", "Tailor Guy") in [
        (s["action"], s["name"], s["quantity"], s["value"], s["via"], s["who"]) for s in r["steps"]
    ]
    assert [(n["crafter"], n["mail_to"], n["postage"]) for n in r["tree"]["inputs"]] == [
        ("Tailor Guy", "", 0),
        ("Tailor Guy", "", 0),
    ]


def test_rank_sends_reagents_and_item_details(client: TestClient, priced: Connection) -> None:
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["reagents"] == [{"item_id": 1, "count": 10}, {"item_id": 2, "count": 1}]
    items = body["items"]
    assert set(items) == {"1", "2", "3"}  # output and reagents; JSON object keys are strings
    assert items["1"]["ah_price"] == 20
    assert items["3"] == {
        "id": 3,
        "name": "Green Robe",
        "quality": 2,
        "class_id": 4,
        "subclass_name": "Cloth",
        "inventory_type": 20,
        "bonding": 2,
        "item_delay": 0,
        "container_slots": 0,
        "required_level": 12,
        "required_skill": "Tailoring",
        "required_skill_rank": 50,
        "description": "Soft and green.",
        "sell_price": 500,
        "icon": "inv_chest_cloth_39",
        "armor": 46,
        "dmg_min": 0,
        "dmg_max": 0,
        "dps": 0.0,
        "stats": ["+9 Intellect"],
        "effects": [
            {
                "trigger": "Equip",
                "text": "Increases damage and healing done by magical spells and effects by up to 6.",
            },
            {"trigger": "Use", "text": "Restores 1050 to 1750 health. (2 Min Cooldown)"},
        ],
        "ah_price": None,
        "ah_sell_price": None,
        "vendor_price": None,
    }


def test_rank_lists_options_and_evaluate_applies_choices(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    set_prices(conn, {1: 20, 2: 100})  # vendors sell thread for 11c
    one_craft(client)
    with_tailor(conn)
    (r,) = client.get("/api/rank").json()["results"]
    assert r["tree"]["options"] == []
    assert [{k: v for k, v in o.items() if k != "seconds"} for o in r["tree"]["inputs"][1]["options"]] == [
        {"key": "vendor", "cost": 11, "source": "vendor", "via": "", "crafter": ""},
        {"key": "ah", "cost": 100, "source": "ah", "via": "", "crafter": ""},
    ]
    assert r["sell_options"] == [{"kind": "vendor", "profit": 500 - 211}]
    assert [(st["action"], st["paths"]) for st in r["steps"]] == [
        ("buy", ["r.0"]),
        ("buy", ["r.1"]),
        ("craft", ["r"]),
        ("sell", ["sell"]),
    ]

    body = {"recipe_id": r["recipe_id"], "choices": {"r.1": "ah"}}
    got = client.post("/api/evaluate", json=body).json()
    assert (got["result"]["cost"], got["result"]["tree"]["inputs"][1]["source"]) == (300, "ah")
    assert set(got["items"]) == {"1", "2", "3"}
    assert client.post("/api/evaluate", json={"recipe_id": 999, "choices": {}}).status_code == 404
    only_ah = {**body, "exits": ["ah"]}  # the robe has no AH price
    assert client.post("/api/evaluate", json=only_ah).status_code == 404


def test_favorites_are_listed_and_ranked_first(client: TestClient, priced: Connection) -> None:
    assert client.get("/api/favorites").json() == {"recipes": []}
    (r,) = client.get("/api/rank").json()["results"]
    added = client.put(f"/api/favorites/{r['recipe_id']}").json()
    assert [f["recipe_id"] for f in added["recipes"]] == [r["recipe_id"]]
    assert added["recipes"][0]["added_at"]
    assert client.get("/api/favorites").json() == added
    assert client.get("/api/favorites", params={"game_version": "tbc"}).json() == {"recipes": []}
    assert [x["recipe_id"] for x in client.get("/api/rank").json()["results"]] == [r["recipe_id"]]
    assert client.delete(f"/api/favorites/{r['recipe_id']}").json() == {"recipes": []}


def test_ah_blocked_items_are_never_sold_on_the_ah(client: TestClient, priced: Connection) -> None:
    set_prices(priced, {3: 1000})  # the robe sells for 950 on the AH, 500 at a vendor
    assert client.get("/api/ah-blocked").json() == {"items": [], "details": {}}
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "ah"

    blocked = client.put("/api/ah-blocked/3").json()
    assert [i["item_id"] for i in blocked["items"]] == [3]
    assert blocked["items"][0]["added_at"]
    robe = blocked["details"]["3"]
    assert (robe["name"], robe["ah_price"]) == ("Green Robe", 1000)
    assert client.get("/api/ah-blocked").json() == blocked
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["best_exit"], [e["kind"] for e in r["exits"]]) == ("vendor", ["vendor"])
    got = client.post("/api/evaluate", json={"recipe_id": r["recipe_id"], "choices": {"sell": "ah"}}).json()
    assert got["result"]["best_exit"] == "vendor"

    assert client.delete("/api/ah-blocked/3").json() == {"items": [], "details": {}}
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "ah"


def test_rank_filters_and_validation(client: TestClient, priced: Connection) -> None:
    def total(**params: str | int | float | list[str]) -> int:
        body = client.get("/api/rank", params=params).json()
        assert len(body["results"]) == body["total"]
        return int(body["total"])

    one_craft(client)
    assert total() == 1  # cost 300, profit 200, roi 2/3, sold to a vendor
    assert total(min_profit=201) == 0
    assert total(min_profit=200, max_profit=200, min_cost=300, max_cost=300) == 1
    assert total(max_profit=199) == 0
    assert total(min_cost=301) == 0
    assert total(max_cost=299) == 0
    assert total(min_roi=0.6, max_roi=0.7) == 1
    assert total(min_roi=0.7) == 0
    assert total(max_roi=0.6) == 0
    assert total(exits=["ah", "disenchant"]) == 0
    assert total(exits=["vendor"]) == 1
    assert client.get("/api/rank", params={"exits": "trade"}).status_code == 422
    assert client.get("/api/rank", params={"top": 0}).status_code == 422
    service.select(priced, ME, FOREVER, "Dreamscythe", "Horde")  # cooks only
    assert total() == 0


def test_rank_unlearned_recipes(client: TestClient, priced: Connection) -> None:
    def novice(skill: int) -> Character:  # knows only a recipe this build lacks
        tailoring = Profession("Tailoring", skill, 75, frozenset({1}))
        return Character("Realm", "Novice", "Horde", "MAGE", 5, (tailoring,))

    def ranked(unlearned: str) -> list[tuple[str, list[str]]]:
        results = client.get("/api/rank", params={"unlearned": unlearned}).json()["results"]
        return [(r["recipe"], r["crafters"]) for r in results]

    service.replace_characters(priced, ME, FOREVER, [novice(29)])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    assert client.get("/api/rank").json()["results"] == ranked("none") == []
    assert ranked("all") == [("Green Robe", [])]
    assert ranked("soon") == []  # its pattern requires 50: 21 short
    service.replace_characters(priced, ME, FOREVER, [novice(30)])
    assert ranked("soon") == [("Green Robe", [])]  # 20 short
    assert client.get("/api/rank", params={"unlearned": "maybe"}).status_code == 422


def test_rank_and_evaluate_without_trivial_recipes(client: TestClient, priced: Connection) -> None:
    veteran = Character(
        "Realm", "Veteran", "Horde", "MAGE", 60, (Profession("Tailoring", 60, 150, frozenset({900})),)
    )
    service.replace_characters(priced, ME, FOREVER, [veteran])  # the robe is grey from 60
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    (r,) = client.get("/api/rank").json()["results"]
    grey = client.get("/api/rank", params={"include_trivial": False}).json()
    assert (grey["results"], grey["total"]) == ([], 0)
    body = {"recipe_id": r["recipe_id"], "choices": {}}
    assert client.post("/api/evaluate", json=body).status_code == 200
    assert client.post("/api/evaluate", json={**body, "include_trivial": False}).status_code == 404


def test_characters_and_selection(client: TestClient, db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    store.save_characters(conn, ME, FOREVER, altarmy.parse_characters(ALTARMY_SV))
    one_craft(client)
    status = client.get("/api/status").json()
    assert status["characters"] == 4
    assert status["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}  # the biggest group

    body = client.get("/api/characters").json()
    assert [(g["realm"], g["faction"], len(g["characters"])) for g in body["groups"]] == [
        ("Classic Beta PvE", "Alliance", 1),
        ("Classic Beta PvE", "Horde", 1),
        ("Dreamscythe", "Horde", 2),
    ]
    assert body["groups"][1]["characters"] == [
        {
            "name": "Tailor Guy",
            "class_file": "MAGE",
            "level": 20,
            "professions": [
                {"name": "Cooking", "rank": 1, "max_rank": 75, "recipes": 0},
                {"name": "Tailoring", "rank": 50, "max_rank": 75, "recipes": 1},
            ],
            "talents": [],
        }
    ]
    (frell,) = [c for c in body["groups"][2]["characters"] if c["name"] == "Frell"]
    assert frell["talents"] == [
        {"spell_id": 1225457, "name": "Master Chef", "rank": 3, "max_rank": 5},
        {"spell_id": 1225459, "name": "Bartering", "rank": 2, "max_rank": 2},
    ]
    assert body["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}
    assert client.get("/api/rank").json()["results"] == []  # Dreamscythe only cooks

    res = client.put("/api/selection", json={"realm": "Classic Beta PvE", "faction": "Horde"})
    assert res.status_code == 200
    assert res.json()["selection"] == {"realm": "Classic Beta PvE", "faction": "Horde"}
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["crafters"], r["profit"]) == (["Tailor Guy"], 200)  # priced by that realm's auction house

    res = client.put("/api/selection", json={"realm": "Nowhere", "faction": "Horde"})
    assert res.status_code == 400


def test_serves_built_frontend(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "index.html").write_text("<html>altarmy-profit</html>")
    client = make_client(database, game_versions, dist)
    assert "altarmy-profit" in client.get("/").text
    assert client.get("/api/status", params={"game_version": "tbc"}).json()["recipes"] == 0


def test_missing_frontend_build_gives_hint(client: TestClient) -> None:
    res = client.get("/")
    assert res.status_code == 200
    assert "npm run build" in res.json()["detail"]


def test_routes_need_a_known_game_version(client: TestClient) -> None:
    client.params = client.params.remove("game_version")
    assert client.get("/api/status").status_code == 422
    assert client.get("/api/status", params={"game_version": "retail"}).status_code == 422


def test_each_game_version_has_its_own_data(client: TestClient, priced: Connection) -> None:
    assert len(client.get("/api/rank").json()["results"]) == 1  # Forever: the tailor's robe
    client.put("/api/ah-blocked/3")
    tbc = {"game_version": "tbc"}
    status = client.get("/api/status", params=tbc).json()
    assert (status["recipes"], status["prices"], status["characters"]) == (0, 0, 0)
    assert client.get("/api/ah-blocked", params=tbc).json()["items"] == []
    assert client.get("/api/rank", params=tbc).json()["results"] == []
    assert client.get("/api/versions").json() == [
        {"key": "forever", "label": "WoW: Forever", "build": None, "recipes": 1},
        {"key": "tbc", "label": "TBC Anniversary", "build": None, "recipes": 0},
    ]


# --- users, tiers and prices ------------------------------------------------------------------------
def test_the_config_names_the_emulators_in_development(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dev = make_client(database, game_versions, tmp_path, firebase=EMULATOR)
    assert dev.get("/api/config").json() == {
        "firebase": {
            "api_key": "key",
            "auth_domain": "demo-altarmy.firebaseapp.com",
            "project_id": "demo-altarmy",
            "emulator_url": "http://127.0.0.1:9099",
            "firestore_emulator_host": "127.0.0.1:8080",
        },
    }


def test_users_sign_in_with_a_token(client: TestClient, conn: Connection) -> None:
    assert client.get("/api/config").json()["firebase"]["emulator_url"] is None
    del client.headers["Authorization"]
    assert client.get("/api/versions").status_code == 200  # public
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert client.get("/api/me", headers=FREE).json() == {
        "uid": "guest",
        "tier": "free",
        "admin": False,
    }
    assert client.get("/api/me", headers=LINKED).json()["tier"] == "linked"
    assert not client.get("/api/me", headers=LINKED).json()["admin"]
    u = schema.users
    rows = conn.execute(select(u.c.uid, u.c.tier).order_by(u.c.uid)).all()
    assert [tuple(r) for r in rows] == [
        ("g1", "linked"),
        ("guest", "free"),
        ("me", "linked"),
    ]


def test_guests_rank_evaluate_and_block_like_everyone(client: TestClient, priced: Connection) -> None:
    # a new user without characters browses every recipe of the freshest realm, crafted by nobody
    (browsed,) = client.get("/api/rank", headers=FREE).json()["results"]
    assert (browsed["crafter"], browsed["crafters"]) == ("", [])
    store.save_characters(priced, "guest", FOREVER, altarmy.parse_characters(ALTARMY_SV))
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert client.put("/api/selection", headers=FREE, json=selection).json()["selection"] == selection
    assert [g["realm"] for g in client.get("/api/characters", headers=FREE).json()["groups"]][0] == (
        "Classic Beta PvE"
    )
    (r,) = client.get("/api/rank", headers=FREE).json()["results"]
    assert (r["recipe"], r["tree"]["via"]) == ("Green Robe", "Green Robe")  # with its flow chart
    body = {"recipe_id": r["recipe_id"], "choices": {}}
    assert client.post("/api/evaluate", headers=FREE, json=body).json()["result"]["profit"] == r["profit"]
    assert client.put("/api/ah-blocked/3", headers=FREE).json()["items"][0]["item_id"] == 3
    assert client.delete("/api/ah-blocked/3", headers=FREE).json()["items"] == []


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("POST", "/api/sync"),
        ("PUT", "/api/sources"),
        ("GET", "/api/auctionator/files"),
        ("GET", "/api/altarmy/files"),
        ("POST", "/api/game-data/update"),
        ("POST", "/api/reload"),
    ],
)
def test_the_old_local_file_and_admin_routes_are_gone(client: TestClient, method: str, path: str) -> None:
    res = client.request(method, path, json={} if method == "PUT" else None)
    assert res.status_code in (404, 405)


def test_linked_users_rank_their_own_characters(client: TestClient, priced: Connection) -> None:
    # the tailor is ME's: this user only browses
    assert client.get("/api/rank", headers=LINKED).json()["results"][0]["crafter"] == ""
    store.save_characters(priced, "g1", FOREVER, altarmy.parse_characters(ALTARMY_SV))
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert client.put("/api/selection", headers=LINKED, json=selection).json()["selection"] == selection
    assert client.get("/api/rank", headers=LINKED).json()["total"] == 1
    client.put("/api/ah-blocked/3", headers=LINKED)
    assert store.load_ah_blocked(priced, ME, FOREVER) == []


def scanned_robe(conn: Connection, price: int, median_7d: int) -> int:
    """An Auctionator scan pricing the robe at `price` on the tailor's auction house, whose 7-day median
    (as the merge would fill it) is `median_7d`. Returns the auction house."""
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    now = db.utcnow()
    prices.record_snapshot(conn, ah, "auctionator", now, [prices.Observation(3, price, now)])
    pc = schema.price_current
    conn.execute(pc.update().where(pc.c.item_id == 3).values(median_7d=median_7d, avail_7d=2, scans_7d=4))
    return ah


def test_rank_sells_at_the_lower_of_now_and_the_seven_day_median(
    client: TestClient, priced: Connection
) -> None:
    one_craft(client)
    scanned_robe(priced, 3_330_000, 1000)  # a lone overpriced listing
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert (r["best_exit"], r["revenue"]) == ("ah", 950)
    robe = body["items"]["3"]
    assert (robe["ah_price"], robe["ah_sell_price"]) == (3_330_000, 1000)


def test_rank_pages_through_one_search(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []
    search = service.search

    def counted(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", counted)
    assert client.get("/api/rank", params={"top": 1}).json()["total"] == 1
    assert client.get("/api/rank", params={"top": 2}).json()["total"] == 1
    assert len(calls) == 1  # "Show more" reuses the ranking
    assert client.get("/api/rank", params={"top": 1, "min_profit": 10**9}).json()["total"] == 0
    assert client.get("/api/rank", params={"top": 1, "max_cost": 0, "min_roi": 9}).json()["total"] == 0
    assert len(calls) == 1  # the bounds are applied to the cached ranking
    client.get("/api/rank", params={"top": 2, "exits": ["vendor"]})
    assert len(calls) == 2  # the exits change what is ranked
    client.get("/api/rank", params={"top": 2, "unlearned": "all"})
    assert len(calls) == 3  # other parameters rank again
    client.get("/api/rank", params={"top": 1, "sort": "rate"})
    assert len(calls) == 3  # sorting by rate reuses the ranking
    client.put("/api/time", json={"config": {"batch": 3}})
    client.get("/api/rank", params={"top": 1})
    assert len(calls) == 4  # plans depend on the time settings


def test_status_reports_the_price_version(client: TestClient, priced: Connection) -> None:
    assert client.get("/api/status").json()["price_version"] == 2  # the fixture's two prices
    ah = scanned_robe(priced, 1200, 1000)
    scanned = client.get("/api/status").json()["price_version"]
    assert scanned > 2
    prices.record_daily(priced, ah, {3: _item_price(1200)})
    merge.merge(priced, FOREVER)
    assert client.get("/api/status").json()["price_version"] == scanned + 1


def _item_price(price: int) -> ItemPrice:
    return ItemPrice(price, {db.utcnow().date(): DayStats(price, price, 1)})


def test_coverage_lists_each_realms_scans(client: TestClient, conn: Connection) -> None:
    assert upload(
        client, "auctionator", _saved_variables({"Dreamscythe Horde": {"1": _entry(20)}}), FREE
    ).is_success
    prices.unnamed_auction_house(conn, FOREVER)  # never listed
    tbc = prices.auction_house(conn, "tbc", "Dreamscythe", "Horde")
    (row,) = client.get("/api/coverage", headers=FREE).json()
    assert (row["realm"], row["faction"], row["prices"], row["last_scan_items"]) == (
        "Dreamscythe",
        "Horde",
        1,
        1,
    )
    assert (row["scans_7d"], row["uploaders_7d"], row["sources"]) == (1, 1, ["auctionator"])
    assert row["last_scan"] is not None
    (dream,) = client.get("/api/coverage", params={"game_version": "tbc"}, headers=FREE).json()
    assert (dream["auction_house_id"], dream["last_scan"], dream["scans_7d"]) == (tbc, None, 0)


# --- uploads ------------------------------------------------------------------------------------------
def upload(
    c: TestClient,
    kind: str,
    data: bytes,
    headers: dict[str, str] | None = None,
    *,
    modified_at: int | None = None,
    via: str = "browser",
    filename: str = "x.lua",
    faction: str | None = None,
) -> Any:
    form: dict[str, str] = {"kind": kind, "via": via}
    if faction is not None:
        form["faction"] = faction
    if modified_at is not None:
        form["modified_at"] = str(modified_at)
    return c.post("/api/uploads", headers=headers or {}, data=form, files={"file": (filename, data)})


def test_any_user_names_the_faction_of_a_scan(client: TestClient) -> None:
    assert upload(client, "altarmy", ALTARMY_SV, FREE).is_success  # both factions on Classic Beta PvE
    data = _saved_variables({"ClassicBetaPvE": {"1": _entry(20)}})
    (realm,) = upload(client, "auctionator", data, FREE).json()["realms"]
    assert (realm["auction_house_id"], realm["both_factions"]) == (None, True)
    (realm,) = upload(client, "auctionator", data, FREE, faction="Horde").json()["realms"]
    assert (realm["realm"], realm["faction"], realm["skipped"]) == ("Classic Beta PvE", "Horde", None)


def test_guests_upload_characters_and_prices(client: TestClient, conn: Connection) -> None:
    res = upload(client, "altarmy", ALTARMY_SV, FREE)
    assert res.status_code == 200, res.text
    body = res.json()
    assert (body["kind"], body["characters"]) == ("altarmy", 4)
    assert body["groups"][0] == {"realm": "Classic Beta PvE", "faction": "Alliance", "characters": 1}
    assert store.count_characters(conn, "guest", FOREVER) == 4
    assert len(client.get("/api/characters", headers=FREE).json()["groups"]) == 3

    assert client.delete(
        "/api/characters", params={"realm": "Classic Beta PvE", "name": "Ally Alt"}, headers=FREE
    ).is_success  # left with one faction on Classic Beta PvE: scans there are the Horde's
    data = _saved_variables({"ClassicBetaPvE": {"1": _entry(20), "2": _entry(100)}})
    res = upload(client, "auctionator", gzip.compress(data), FREE, modified_at=1_790_000_000_000)
    realm = res.json()["realms"][0]
    assert (realm["key"], realm["realm"], realm["faction"], realm["items"], realm["skipped"]) == (
        "ClassicBetaPvE",
        "Classic Beta PvE",
        "Horde",
        2,
        None,
    )
    (covered,) = client.get("/api/coverage", headers=FREE).json()
    assert (covered["realm"], covered["faction"], covered["prices"]) == ("Classic Beta PvE", "Horde", 2)
    history = client.get("/api/uploads", headers=FREE).json()
    assert [(u["kind"], u["outcome"], u["via"]) for u in history] == [
        ("auctionator", "accepted", "browser"),
        ("altarmy", "accepted", "browser"),
    ]
    assert client.get("/api/status", headers=FREE).json()["data_version"] == 3


def test_upload_refreshes_the_cached_market(client: TestClient, priced: Connection) -> None:
    one_craft(client)
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 20 + 100
    service.delete_character(priced, ME, FOREVER, "Classic Beta PvE", "Ally Alt")  # scans are the Horde's
    upload(client, "auctionator", _saved_variables({"ClassicBetaPvE": {"1": {"m": 33}}}))
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 33 + 100  # linen repriced


def published(client: TestClient) -> list[tuple[int, str, int]]:
    fake: FakeSignals = client.app.state.wow[FOREVER].signals  # type: ignore[attr-defined]
    return fake.published


def test_an_upload_that_moves_prices_signals_the_auction_house(
    client: TestClient, priced: Connection
) -> None:
    ah = service.selected_auction_house(priced, ME, FOREVER)
    assert ah is not None
    before = prices.price_version(priced, ah)
    assert before is not None
    service.delete_character(priced, ME, FOREVER, "Classic Beta PvE", "Ally Alt")  # scans are the Horde's
    data = _saved_variables({"ClassicBetaPvE": {"1": {"m": 33}}})
    upload(client, "auctionator", data)
    assert published(client) == [(ah, FOREVER, before + 1)]
    upload(client, "auctionator", data)  # the same prices again: nothing moved
    assert published(client) == [(ah, FOREVER, before + 1)]
    upload(client, "altarmy", ALTARMY_SV)  # characters only
    assert len(published(client)) == 1


def test_a_known_price_version_skips_the_markets_ttl(client: TestClient, priced: Connection) -> None:
    """After a price signal the front end asks with the new version: another instance's prices show at
    once, not STAMP_TTL later."""
    one_craft(client)
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 20 + 100
    ah = service.selected_auction_house(priced, ME, FOREVER)
    prices.set_price(priced, ah or 0, 1, 33)  # as another instance's upload would
    version = prices.price_version(priced, ah)
    got = client.get("/api/rank", params={"price_version": version}).json()
    assert got["results"][0]["cost"] == 10 * 33 + 100
    body = {"recipe_id": got["results"][0]["recipe_id"], "choices": {}, "price_version": version}
    assert client.post("/api/evaluate", json=body).json()["result"]["cost"] == 10 * 33 + 100


def test_bad_uploads(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    res = upload(client, "auctionator", b"garbage", LINKED)
    assert res.status_code == 400
    assert "AUCTIONATOR_PRICE_DATABASE" in res.json()["detail"]
    (row,) = client.get("/api/uploads", headers=LINKED).json()
    assert (row["outcome"], row["size"]) == ("rejected", 7)
    assert upload(client, "cheese", b"x", LINKED).status_code == 422
    assert upload(client, "altarmy", b"x", {"Authorization": "Bearer nonsense"}).status_code == 401

    monkeypatch.setattr(uploads, "MAX_BYTES", 1000)
    assert upload(client, "altarmy", b"x" * 1001, LINKED).status_code == 413
    assert upload(client, "altarmy", gzip.compress(b"x" * 5000), LINKED).status_code == 413

    monkeypatch.setattr(uploads, "RATE_LIMIT", 3)
    res = upload(client, "altarmy", ALTARMY_SV, LINKED)
    assert res.status_code == 429  # the rejected ones count too


PASTE = (Path(__file__).parent / "fixtures" / "altarmy_export_v2.txt").read_text(encoding="utf-8")


def test_guests_paste_the_addons_export(client: TestClient) -> None:
    tbc = {"game_version": "tbc"}
    res = client.post("/api/uploads/paste", params=tbc, headers=FREE, json={"text": PASTE})
    assert res.status_code == 200, res.text
    body = res.json()
    assert (body["kind"], body["characters"], body["realms"]) == ("altarmy", 3, [])
    assert body["groups"] == [{"realm": "Dreamscythe", "faction": "Horde", "characters": 2}]
    (row,) = client.get("/api/uploads", headers=FREE).json()
    assert (row["kind"], row["via"], row["outcome"], row["game_version"]) == (
        "altarmy",
        "paste",
        "accepted",
        "tbc",
    )
    chars = client.get("/api/characters", params=tbc, headers=FREE).json()
    assert (chars["imported_at"], chars["imported_via"], chars["auto_import_at"]) == (
        row["received_at"],
        "paste",
        None,
    )


def test_bad_pastes(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    res = client.post(
        "/api/uploads/paste", headers=LINKED, json={"text": PASTE}
    )  # a TBC export, Forever chosen
    assert res.status_code == 400
    assert res.json()["detail"] == "This is a TBC Anniversary export; this site serves WoW: Forever."
    res = client.post("/api/uploads/paste", headers=LINKED, json={"text": "hello"})
    assert res.status_code == 400
    rows = client.get("/api/uploads", headers=LINKED).json()
    assert [(r["via"], r["outcome"]) for r in rows] == [("paste", "rejected")] * 2
    signed_out = {"Authorization": "Bearer nonsense"}
    assert client.post("/api/uploads/paste", headers=signed_out, json={"text": PASTE}).status_code == 401

    monkeypatch.setattr(uploads, "MAX_BYTES", 100)
    assert client.post("/api/uploads/paste", headers=LINKED, json={"text": "x" * 101}).status_code == 413
    monkeypatch.setattr(uploads, "RATE_LIMIT", 3)
    assert client.post("/api/uploads/paste", headers=LINKED, json={"text": PASTE}).status_code == 429


def test_the_watcher_uploads_with_an_email_sign_in(client: TestClient, conn: Connection) -> None:
    signed_in = {"Authorization": "Bearer password:g1"}  # the ID token Alt Army Sync gets from Firebase
    assert upload(client, "altarmy", ALTARMY_SV, signed_in, via="watcher").status_code == 200
    assert store.count_characters(conn, "g1", FOREVER) == 4
    assert (
        upload(client, "altarmy", ALTARMY_SV, {"Authorization": "Bearer ak_old"}).status_code == 401
    )  # no keys
    assert client.get("/api/keys", headers=LINKED).status_code == 404


def test_users_delete_their_account(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database, conn: Connection
) -> None:
    verifier = FakeVerifier()
    client = make_client(database, game_versions, tmp_path / "nodist", verifier=verifier)
    upload(client, "altarmy", ALTARMY_SV, LINKED)
    upload(client, "auctionator", _saved_variables({"Dreamscythe Horde": {"1": _entry(20)}}), LINKED)

    verifier.fail = True
    assert client.delete("/api/me", headers=LINKED).status_code == 502
    assert store.count_characters(conn, "g1", FOREVER) == 4  # rolled back with the Firebase failure

    verifier.fail = False
    assert client.delete("/api/me", headers=LINKED).status_code == 204
    assert verifier.deleted == ["g1"]
    assert store.count_characters(conn, "g1", FOREVER) == 0
    assert conn.execute(select(schema.users.c.uid).where(schema.users.c.uid == "g1")).first() is None
    for table in (schema.uploads, schema.user_settings):
        assert conn.execute(select(table)).first() is None
    snap = schema.price_snapshots
    assert conn.execute(select(snap.c.uploader_uid)).scalars().all() == [None]  # pooled prices stay
    assert conn.execute(select(schema.price_current)).first() is not None


def test_rate_limits_per_user_and_ip(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    limits = ratelimit.Limits(per_ip=5, per_uid=2, window=60)
    client = make_client(database, game_versions, tmp_path / "nodist", limits=limits)
    del client.headers["Authorization"]
    ip1 = {"X-Forwarded-For": "203.0.113.1"}
    assert [client.get("/api/me", headers={**LINKED, **ip1}).status_code for _ in range(3)] == [200, 200, 429]
    res = client.get("/api/me", headers={**FREE, **ip1})  # another user from the same address
    assert res.status_code == 200
    assert [client.get("/api/versions", headers=ip1).status_code for _ in range(2)] == [200, 429]
    assert int(client.get("/api/versions", headers=ip1).headers["Retry-After"]) >= 1
    assert client.get("/api/versions", headers={"X-Forwarded-For": "203.0.113.2"}).status_code == 200


def test_api_responses_are_never_cached(client: TestClient) -> None:
    assert client.get("/api/versions").headers["Cache-Control"] == "no-store"


def test_the_default_database_is_never_migrated(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, game_versions: dict[str, GameVersion]
) -> None:
    """Each deploy migrates, once; `altarmy-profit serve` passes a database that migrates."""
    monkeypatch.setenv("DATABASE_URL", db.sqlite_url(tmp_path / "site.sqlite"))
    app = create_app(game_versions, verifier=FakeVerifier(), firebase=FIREBASE)
    assert not app.state.auth.database.migrates


def test_needs_a_firebase_project(
    monkeypatch: pytest.MonkeyPatch, game_versions: dict[str, GameVersion]
) -> None:
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    with pytest.raises(ValueError, match="FIREBASE_PROJECT_ID"):
        create_app(game_versions, verifier=FakeVerifier())


def test_professions(client: TestClient, db2_paths: dict[str, Path], conn: Connection) -> None:
    assert client.get("/api/professions").json() == []
    ingest.build_db(db2_paths, conn, FOREVER)
    assert client.get("/api/professions").json() == ["Tailoring"]


def test_browsing_without_characters(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    status = client.get("/api/status").json()
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert (status["characters"], status["selection"]) == (0, selection)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert (r["crafter"], r["crafters"], r["mail_to"], body["classes"]) == ("", [], "", {})
    assert {s["who"] for s in r["steps"]} == {""}
    assert client.get("/api/rank", params={"professions": ["tailoring"]}).json()["total"] == 1
    assert client.get("/api/rank", params={"professions": ["Cooking"]}).json()["total"] == 0

    set_prices(conn, {1: 30}, realm="Dreamscythe", faction="Horde")
    res = client.put("/api/selection", json={"realm": "Dreamscythe", "faction": "Horde"})
    assert res.json()["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}
    assert client.put("/api/selection", json={"realm": "Nowhere", "faction": ""}).status_code == 400


def test_serves_the_front_end_for_its_own_pages(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dist = tmp_path / "dist"
    (dist / "assets").mkdir(parents=True)
    (dist / "index.html").write_text("<html>app</html>")
    (dist / "assets" / "app.js").write_text("js")
    client = make_client(database, game_versions, dist)
    for page in ("/addon", "/profit", "/upload", "/manage", "/admin"):
        assert client.get(page).text == "<html>app</html>"
    assert client.get("/assets/app.js").text == "js"
    assert client.get("/assets/missing.js").status_code == 404
    assert client.get("/api/nope").status_code == 404
    assert "app" not in client.get("/api/nope").text


# --- admin -----------------------------------------------------------------------------------------------
def test_the_admin_page_is_for_admins_only(client: TestClient) -> None:
    assert client.get("/api/me", headers=ADMIN).json() == {"uid": "a1", "tier": "linked", "admin": True}
    for headers in (FREE, LINKED, SIGNED_IN):
        assert client.get("/api/admin/ingestion", headers=headers).status_code == 403
    assert client.get("/api/admin/ingestion", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert client.get("/api/admin/ingestion", headers=ADMIN).status_code == 200


def test_everyone_is_an_admin_against_the_auth_emulator(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dev = make_client(database, game_versions, tmp_path, firebase=EMULATOR)
    for headers in (FREE, LINKED, SIGNED_IN):
        assert dev.get("/api/me", headers=headers).json()["admin"]
        assert dev.get("/api/admin/ingestion", headers=headers).status_code == 200
    assert dev.get("/api/admin/ingestion", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_the_admin_page_shows_jobs_uploads_snapshots_and_feeds(client: TestClient, conn: Connection) -> None:
    now = db.utcnow()
    run_id = jobs.start(conn, "merge", now=now)
    jobs.finish(conn, run_id, True, "Merged 1 auction houses", now=now)
    jobs.start(conn, "ingest", "tbc", now=now)  # another version's: not shown
    uploads.record_upload(conn, ME, FOREVER, "auctionator", "watcher", 10, "accepted", "2 prices", now=now)
    uploads.record_upload(conn, ME, "tbc", "auctionator", "watcher", 10, "accepted", "", now=now)
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    prices.record_snapshot(conn, ah, "auctionator", now, [prices.Observation(1, 10, now)], received_at=now)
    conn.execute(
        schema.feed_tables.insert().values(
            source="ahledger",
            market="forever.normal.horde.us",
            auction_house_id=ah,
            scanned_at=now,
            stamped_at=now,
            fetched_at=now,
            body=f"AHL1|forever/normal/horde/us|{int(now.timestamp())}|1\n1:10:10:3",
        )
    )
    got = client.get("/api/admin/ingestion", headers=ADMIN).json()
    assert got["now"] >= db.timestamp_text(now)
    status = {j["job"]: j for j in got["jobs"]}
    assert list(status) == list(schema.JOBS)
    assert status["merge"]["ok"] and not status["merge"]["late"]
    assert status["merge"]["summary"] == "Merged 1 auction houses"
    assert status["ingest"] == {
        "job": "ingest",
        "game_version": None,
        "last_started": None,
        "last_finished": None,
        "ok": None,
        "late": True,
        "summary": "",
    }
    assert [r["job"] for r in got["runs"]] == ["merge"]
    assert got["uploads"]["accepted_24h"] == 1 and got["uploads"]["uploaders_7d"] == 1
    assert [(u["user_uid"], u["detail"]) for u in got["uploads"]["recent"]] == [(ME, "2 prices")]
    ((source, stats),) = [(s["source"], s) for s in got["snapshots"]]
    assert (source, stats["snapshots_24h"], stats["items_7d"]) == ("auctionator", 1, 1)
    assert [(f["market"], f["faction"], f["rows"]) for f in got["feeds"]] == [
        ("forever.normal.horde.us", "Horde", 1)
    ]
    assert ahledger.feeds(conn, FOREVER)[0].auction_house_id == ah


# --- profit per hour ----------------------------------------------------------------------------------
def test_time_settings_round_trip(client: TestClient, priced: Connection, cities: Path) -> None:
    got = client.get("/api/time").json()
    assert [c["name"] for c in got["cities"]] == ["Orgrimmar", "Thunder Bluff"]  # Horde's; no neutral town
    assert (got["city"], got["active"]) == (None, None)  # whatever is fastest
    assert got["config"] == got["defaults"]
    assert got["defaults"]["batch"] == 10
    put = client.put("/api/time", json={"city": "Thunder Bluff", "config": {"batch": 5, "time_value": 10**6}})
    assert put.status_code == 200
    assert (put.json()["city"], put.json()["active"]) == ("Thunder Bluff", "Thunder Bluff")
    assert (put.json()["config"]["batch"], put.json()["config"]["time_value"]) == (5, 10**6)
    assert client.get("/api/time").json() == put.json()
    for bad in [
        {"city": "Atlantis"},
        {"city": "Booty Bay"},
        {"config": {"batch": 0}},
        {"config": {"nope": 1}},
    ]:
        assert client.put("/api/time", json=bad).status_code == 400
    reset = client.put("/api/time", json={}).json()
    assert (reset["city"], reset["config"]) == (None, reset["defaults"])


def test_rank_reports_profit_per_hour(client: TestClient, priced: Connection, cities: Path) -> None:
    (r,) = client.get("/api/rank").json()["results"]
    t = r["timing"]
    # by default each plan is timed in the fastest Horde city: Thunder Bluff has the anvil and the vendor
    assert (t["city"], r["crafts"]) == ("Thunder Bluff", 10)
    assert t["total_seconds"] == pytest.approx(t["fixed_seconds"] + t["per_craft_seconds"])
    assert t["per_hour"] == round(10 * 200 * 3600 / t["total_seconds"])
    assert set(t["breakdown"]) >= {"travel", "craft", "ah", "vendor"}
    # collect the AH purchases, craft at the anvil, sell the robe to the vendor, and stop there
    assert [leg["to_name"] for leg in t["legs"]] == ["Mailbox", "Anvil", "Thread Seller"]
    assert [c["city"] for c in r["cities"]] == ["Orgrimmar", "Thunder Bluff"]
    assert r["best_city"] == "Thunder Bluff"
    # the robe is crafted at an anvil, which Orgrimmar lacks here: noted, not timed, never the pick
    assert (t["missing"], r["cities"][0]["missing"], r["cities"][1]["missing"]) == ([], ["anvil"], [])
    client.put("/api/time", json={"city": "Orgrimmar"})  # a chosen city is used as it is
    (there,) = client.get("/api/rank").json()["results"]
    assert (there["timing"]["city"], there["timing"]["missing"]) == ("Orgrimmar", ["anvil"])
    assert [leg["to_name"] for leg in there["timing"]["legs"]] == ["Mailbox", "Thread Seller"]
    client.put("/api/time", json={})
    craft = next(s for s in r["steps"] if s["action"] == "craft")
    assert craft["seconds"] == pytest.approx(35) and craft["station"] == "anvil"  # 10 3 s casts at an anvil
    assert r["tree"]["seconds"] > 0 and r["tree"]["inputs"][0]["options"][0]["seconds"] > 0
    by_rate = client.get("/api/rank", params={"sort": "rate"}).json()["results"]
    assert [x["recipe_id"] for x in by_rate] == [r["recipe_id"]]


def test_rank_times_anywhere_without_presets(client: TestClient, priced: Connection) -> None:
    (r,) = client.get("/api/rank").json()["results"]
    assert r["timing"]["city"] == "Anywhere"
    assert r["timing"]["breakdown"]["travel"] == 0
    assert (r["cities"], r["best_city"]) == ([], None)
    assert client.get("/api/time").json()["cities"] == []


def test_evaluate_uses_the_time_settings(client: TestClient, priced: Connection, cities: Path) -> None:
    client.put("/api/time", json={"city": "Thunder Bluff", "config": {"batch": 4}})
    body = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}}).json()
    assert (body["result"]["timing"]["city"], body["result"]["crafts"]) == ("Thunder Bluff", 4)


def test_guests_keep_their_own_time_settings(client: TestClient, conn: Connection) -> None:
    assert client.put("/api/time", json={"config": {"batch": 2}}, headers=FREE).status_code == 200
    assert client.get("/api/time", headers=FREE).json()["config"]["batch"] == 2


def test_evaluate_plans_a_session_spelled_out(client: TestClient, priced: Connection, cities: Path) -> None:
    body = {"recipe_id": 100, "choices": {}, "copies": 20, "city": "Thunder Bluff"}
    r = client.post("/api/evaluate", json=body).json()["result"]
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (20, 20 * 300, 20 * 500, 20 * 200)
    assert r["timing"]["city"] == "Thunder Bluff"
    assert r["timing"]["per_hour"] == round(20 * 200 * 3600 / r["timing"]["total_seconds"])
    said = []
    for d in r["details"]:
        if d["kind"] == "step":
            s = r["steps"][d["step"]]
            said.append((s["action"], s["name"], s["quantity"]))
        else:
            loc = d["location"]
            said.append((d["kind"], loc["name"], [(i["item_id"], i["count"]) for i in d["retrieve"]]))
    assert said == [
        ("start", "Auctioneer", []),
        ("buy", "Linen Cloth", 200),
        ("buy", "Coarse Thread", 20),
        ("go", "Mailbox", [(1, 200), (2, 20)]),
        ("go", "Anvil", []),
        ("craft", "Green Robe", 20),
        ("go", "Thread Seller", []),
        ("sell", "Green Robe", 20),
    ]
    assert r["details"][0]["seconds"] == 0
    anvil = r["details"][4]["location"]
    assert (anvil["kind"], anvil["map_x"], anvil["map_y"], anvil["map_area"]) == ("anvil", 49.0, 50.0, 1638)
    # without copies or a city: the time settings' batch, exactly as the ranking has it
    (ranked,) = client.get("/api/rank").json()["results"]
    default = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}}).json()["result"]
    assert (default["crafts"], default["details"] != []) == (10, True)
    assert default == ranked


def test_evaluate_refuses_a_city_the_characters_dont_craft_in(
    client: TestClient, priced: Connection, cities: Path
) -> None:
    for city in ("Stormwind", "Booty Bay", "Atlantis"):
        got = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}, "copies": 5, "city": city})
        assert got.status_code == 400
    assert (
        client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}, "copies": 0}).status_code == 422
    )
