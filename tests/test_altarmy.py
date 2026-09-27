import pytest

from altarmy_profit import altarmy
from altarmy_profit.altarmy import Character, Profession

# Trimmed from a real AltArmy_TBC.lua (addon 2.1.1): no indentation, one statement per global.
ALTARMY_SV = b"""
AltArmyTBC_Options = {
["showMinimap"] = true,
}
AltArmyTBC_Data = {
["RecipeReagents"] = {
[900] = {
{
1,
10,
},
},
},
["Characters"] = {
["Classic Beta PvE"] = {
["Tailor Guy"] = {
["name"] = "Tailor Guy",
["realm"] = "Classic Beta PvE",
["legacyTalents"] = {
["nodes"] = {
[105955] = 2,
},
["totalRanksSpent"] = 2,
["restRank"] = 0,
},
["faction"] = "Horde",
["classFile"] = "MAGE",
["level"] = 20,
["Containers"] = {
{
["items"] = {
{
["itemID"] = 1,
["count"] = 20,
},
nil,
{
["itemID"] = 2,
["count"] = 5,
},
},
},
},
["Professions"] = {
["Tailoring"] = {
["isPrimary"] = true,
["Recipes"] = {
[900] = {
["color"] = 1,
["primaryRecipeID"] = 900,
["name"] = "Green Robe",
["resultItemID"] = 3,
},
},
["maxRank"] = 75,
["rank"] = 50,
},
["Cooking"] = {
["isSecondary"] = true,
["Recipes"] = {
},
["maxRank"] = 75,
["rank"] = 1,
},
},
},
["Ally Alt"] = {
["name"] = "Ally Alt",
["faction"] = "Alliance",
["classFile"] = "PRIEST",
["level"] = 10,
["Professions"] = {
["Enchanting"] = {
["isPrimary"] = true,
["Recipes"] = {
[7418] = {
["color"] = 4,
},
},
["maxRank"] = 75,
["rank"] = 12,
},
},
},
},
["Dreamscythe"] = {
["Frell"] = {
["name"] = "Frell",
["faction"] = "Horde",
["classFile"] = "WARLOCK",
["level"] = 70,
["Professions"] = {
["Cooking"] = {
["Recipes"] = {
[33260] = {
["color"] = 4,
["primaryRecipeID"] = 33284,
["resultItemID"] = 27655,
},
[33284] = {
["color"] = 4,
["primaryRecipeID"] = 33284,
["resultItemID"] = 27655,
},
},
["maxRank"] = 375,
["rank"] = 370,
},
},
["legacyTalents"] = {
["spells"] = {
[1225459] = 2,
[1225457] = 3,
[1225478] = 0,
},
["nodes"] = {
[110289] = 3,
[110286] = 2,
},
["totalRanksSpent"] = 5,
["restRank"] = 0,
},
},
["Newbie"] = {
["faction"] = "Horde",
},
},
},
}
AltArmyTBC_GuildData = {
}
"""


def test_parse_characters() -> None:
    chars = altarmy.parse_characters(ALTARMY_SV)
    assert [(c.realm, c.name) for c in chars] == [
        ("Classic Beta PvE", "Ally Alt"),
        ("Classic Beta PvE", "Tailor Guy"),
        ("Dreamscythe", "Frell"),
        ("Dreamscythe", "Newbie"),
    ]
    ally, tailor, frell, newbie = chars
    assert tailor == Character(
        realm="Classic Beta PvE",
        name="Tailor Guy",
        faction="Horde",
        class_file="MAGE",
        level=20,
        professions=(
            Profession("Cooking", rank=1, max_rank=75, recipe_ids=frozenset()),
            Profession("Tailoring", rank=50, max_rank=75, recipe_ids=frozenset({900})),
        ),
    )
    # Enchanting craft rows only carry a color: the key is the recipe id.
    assert ally.professions == (Profession("Enchanting", 12, 75, frozenset({7418})),)
    # TBC alias keys collapse onto primaryRecipeID.
    assert frell.professions == (Profession("Cooking", 370, 375, frozenset({33284})),)
    # Legacy talents by spell id, sorted, without unspent ones; data version 1 (no `spells`: class talents
    # really) gives none.
    assert frell.talents == ((1225457, 3), (1225459, 2))
    assert tailor.talents == ()
    # A character that was never fully scanned still shows up, without professions.
    assert newbie == Character("Dreamscythe", "Newbie", "Horde", "", 0, ())


def test_known_recipes_unions_professions() -> None:
    (tailor,) = [c for c in altarmy.parse_characters(ALTARMY_SV) if c.name == "Tailor Guy"]
    assert tailor.known_recipes == frozenset({900})


def test_groups_by_realm_and_faction() -> None:
    got = [(g.realm, g.faction, [c.name for c in g.characters]) for g in altarmy.groups(chars())]
    assert got == [
        ("Classic Beta PvE", "Alliance", ["Ally Alt"]),
        ("Classic Beta PvE", "Horde", ["Tailor Guy"]),
        ("Dreamscythe", "Horde", ["Frell", "Newbie"]),
    ]


def test_crafters() -> None:
    assert altarmy.crafters(chars()) == {900: ["Tailor Guy"], 7418: ["Ally Alt"], 33284: ["Frell"]}


def chars() -> list[Character]:
    return altarmy.parse_characters(ALTARMY_SV)


def test_rejects_other_files() -> None:
    with pytest.raises(ValueError, match="AltArmyTBC_Data"):
        altarmy.parse_characters(b"AUCTIONATOR_PRICE_DATABASE = {}\n")


def _sv(realm_body: str) -> bytes:
    body = f'["Characters"] = {{\n["Classic Beta PvE"] = {{\n{realm_body}}},\n}},\n'
    return f"AltArmyTBC_Data = {{\n{body}}}\n".encode()


def _entry(key: str, *, level: int, updated: int, guid: str = "", class_file: str = "SHAMAN") -> str:
    guid_line = f'["guid"] = "{guid}",\n' if guid else ""
    return (
        f'["{key}"] = {{\n["name"] = "{key}",\n["faction"] = "Horde",\n["classFile"] = "{class_file}",\n'
        f'["raceFile"] = "TAUREN",\n["level"] = {level},\n["lastUpdate"] = {updated},\n{guid_line}}},\n'
    )


def names(data: bytes) -> list[tuple[str, int]]:
    return [(c.name, c.level) for c in altarmy.parse_characters(data)]


def test_a_renamed_character_imports_once() -> None:
    # WoW: Forever's UnitName("player") dropped the surname: the addon saved the same character under
    # its old key ("Frell Ofelements") and its new one ("Frell"). The newest entry wins.
    data = _sv(_entry("Frell Ofelements", level=20, updated=100) + _entry("Frell", level=21, updated=200))
    assert names(data) == [("Frell", 21)]
    short_first = _entry("Frell", level=20, updated=100)
    older_short = _sv(short_first + _entry("Frell Ofelements", level=21, updated=200))
    assert names(older_short) == [("Frell Ofelements", 21)]


def test_characters_sharing_a_first_name_are_kept() -> None:
    # Another class, or both with surnames: different characters.
    data = _sv(
        _entry("Frell", level=20, updated=200)
        + _entry("Frell Blast", level=9, updated=100, class_file="MAGE")
        + _entry("Frell Hound", level=1, updated=100, class_file="HUNTER")
    )
    assert names(data) == [("Frell", 20), ("Frell Blast", 9), ("Frell Hound", 1)]
    # Only a key without a surname can be a rename of one with it.
    both = _sv(_entry("Frell Hound", level=1, updated=100) + _entry("Frell Wrath", level=3, updated=100))
    assert names(both) == [("Frell Hound", 1), ("Frell Wrath", 3)]


def test_the_same_guid_is_one_character() -> None:
    data = _sv(
        _entry("Old Name", level=10, updated=100, guid="Player-1-A")
        + _entry("New Name", level=11, updated=200, guid="Player-1-A")
        + _entry("Frell", level=20, updated=300, guid="Player-1-B")
        + _entry("Frell Ofelements", level=20, updated=100, guid="Player-1-C")
    )
    # Different GUIDs are different characters, whatever their names.
    assert names(data) == [("Frell", 20), ("Frell Ofelements", 20), ("New Name", 11)]


def test_a_never_scanned_stub_is_skipped() -> None:
    # The addon once created an entry while UnitName("player") still said "Unknown" during loading.
    data = _sv(
        '["Unknown"] = {\n["lastUpdate"] = 5,\n["Reputations"] = {\n},\n},\n'
        + _entry("Frell", level=20, updated=1)
    )
    assert names(data) == [("Frell", 20)]
