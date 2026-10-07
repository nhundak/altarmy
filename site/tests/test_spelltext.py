"""Spell descriptions as tooltip text (examples are the Forever client's, checked against Wowhead)."""

from altarmy_site import spelltext
from altarmy_site.itemstats import Effect
from altarmy_site.spelltext import EffectValues, SpellData

DATA = SpellData(
    descriptions={
        17534: "Restores $s1 health.",
        17538: "Increases Agility by $s1 and chance to get a critical hit by $s2%. Lasts for $d.",
        16898: "Burns the enemy for $o1 damage over $d.",
        1131: "Restores $o1 health over $d.  Must remain seated while eating.",
        1249522: "$@spelldesc1131 If you spend at least 10 seconds eating you will become well fed and gain "
        "$s2% Critical Strike chance for $1249523d. $@spelldesc1243969",
        1243969: "$?pc142418[Additionally, experience gained from kills is increased by $s1%.][]",
        11202: "Coats a weapon with poison that lasts for ${$m1/60} minutes.\nEach strike has a $h% chance",
        17528: "Increases Rage by $/10;s1 and increases Strength by $s2 for $d.",
        14134: "removing $m1 disease $leffect:effects; and $m2 poison $leffect:effects;.",
        15279: "doing $s1 damage to anyone who hits $ghim:her;.  Lasts $d1.",
        1232103: "up to a ${$m1/-1000}.1 second reduction$?s442543[. While equipped][]",
        9: "loop $@spelldesc9",
        10: "$@spellicon10 Bam! $zz1 $s1",
        11: "Radius $a1, $x1 targets, $q1 misc, every $t1 sec, $PL levels, $u stacks",
    },
    effects={
        17534: (EffectValues(1400, variance=0.5),),
        17538: (EffectValues(25), EffectValues(2)),
        16898: (EffectValues(20, period_ms=3000),),
        1131: (EffectValues(358, period_ms=0),),
        1249522: (EffectValues(0), EffectValues(1)),
        1243969: (EffectValues(5),),
        11202: (EffectValues(1800),),
        17528: (EffectValues(200), EffectValues(25)),
        14134: (EffectValues(1), EffectValues(2)),
        15279: (EffectValues(-30),),
        1232103: (EffectValues(-1500),),
        11: (EffectValues(5, misc=7, radius=20.0, chain=3, period_ms=1500),),
    },
    durations={17538: 3600000, 16898: 30000, 1131: 27000, 1249523: 900000, 15279: 90000, 11202: 1800000},
    proc_chance={11202: 20},
    max_stacks={11: 4},
)


def test_values_ranges_and_durations() -> None:
    assert spelltext.expand("Restores $s1 health.", 17534, DATA) == "Restores 1050 to 1750 health."
    assert (
        spelltext.expand(DATA.descriptions[17538], 17538, DATA)
        == "Increases Agility by 25 and chance to get a critical hit by 2%. Lasts for 1 hour."
    )
    assert (
        spelltext.expand(DATA.descriptions[16898], 16898, DATA)
        == "Burns the enemy for 200 damage over 30 sec."
    )
    # no tick period: the base is the total; a double space collapses; $d1 is the duration
    assert (
        spelltext.expand(DATA.descriptions[1131], 1131, DATA)
        == "Restores 358 health over 27 sec. Must remain seated while eating."
    )
    assert spelltext.expand(DATA.descriptions[15279], 15279, DATA) == (
        "doing 30 damage to anyone who hits him. Lasts 1.5 min."
    )


def test_nested_descriptions_other_spells_and_conditionals() -> None:
    assert spelltext.expand(DATA.descriptions[1249522], 1249522, DATA) == (
        "Restores 358 health over 27 sec. Must remain seated while eating. If you spend at least 10 seconds "
        "eating you will become well fed and gain 1% Critical Strike chance for 15 min."
    )
    assert spelltext.expand(DATA.descriptions[1232103], 1232103, DATA) == "up to a 1.5 second reduction"
    assert spelltext._conditionals("a $?s1[x]?s2[y][z] b") == "a z b"
    assert spelltext._conditionals("$?s1[only]") == ""


def test_arithmetic_division_plurals_and_the_rest() -> None:
    assert spelltext.expand(DATA.descriptions[11202], 11202, DATA) == (
        "Coats a weapon with poison that lasts for 30 minutes.\nEach strike has a 20% chance"
    )
    assert spelltext.expand(DATA.descriptions[17528], 17528, DATA) == (
        "Increases Rage by 20 and increases Strength by 25 for ."
    )
    assert (
        spelltext.expand(DATA.descriptions[14134], 14134, DATA)
        == "removing 1 disease effect and 2 poison effects."
    )
    assert spelltext.expand(DATA.descriptions[11], 11, DATA, player_level=60) == (
        "Radius 20, 3 targets, 7 misc, every 1.5 sec, 60 levels, 4 stacks"
    )


def test_unknown_tokens_stay_and_recursion_stops() -> None:
    assert spelltext.expand(DATA.descriptions[10], 10, DATA) == "Bam! $zz1 $s1"  # 10 has no effects
    assert spelltext.expand(DATA.descriptions[9], 9, DATA) == "loop loop loop loop"
    assert spelltext.expand("${$s1/0}", 17534, DATA) == "${$s1/0}"
    assert spelltext.expand("${1+x}", 17534, DATA) == "${1+x}"
    assert spelltext.referenced("$@spelldesc1131 for $1249523d and $s1") == {1131, 1249523}


def test_durations_and_cooldowns() -> None:
    assert [spelltext.format_duration(ms) for ms in (0, -1, 3000, 90000, 1800000, 3600000, 7200000)] == [
        "",
        "",
        "3 sec",
        "1.5 min",
        "30 min",
        "1 hour",
        "2 hrs",
    ]
    assert spelltext.cooldown_text(120000) == "(2 Min Cooldown)"
    assert spelltext.cooldown_text(3000) == "(3 Sec Cooldown)"
    assert spelltext.cooldown_text(3600000) == "(1 Hour Cooldown)"
    assert spelltext.cooldown_text(0) == ""


def test_render_effect() -> None:
    assert spelltext.render_effect("Use", 17534, 120000, DATA) == Effect(
        "Use", "Restores 1050 to 1750 health. (2 Min Cooldown)"
    )
    assert spelltext.render_effect("Chance on hit", 16898, 0, DATA) == Effect(
        "Chance on hit", "Burns the enemy for 200 damage over 30 sec."
    )
    assert spelltext.render_effect("Equip", 16898, 5000, DATA) == Effect(
        "Equip", "Burns the enemy for 200 damage over 30 sec."
    )  # cooldowns show on Use lines only
    assert spelltext.render_effect("Use", 12345, 0, DATA) is None  # no description
    assert spelltext.render_effect("Use", 1243969, 0, DATA) is None  # empty once expanded
