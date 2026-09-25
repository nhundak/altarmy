"""Alt Army's paste export: the string the addon shows, decoded to characters.

tests/fixtures/altarmy_export_v1.txt is a copy of the addon repo's spec/fixtures/profit_export_v1.txt (made by
AltArmy_TBC/Data/ProfitExport.lua), so the two sides can't drift apart unnoticed.
"""

import zlib
from pathlib import Path

import pytest

from altarmy_profit import paste
from altarmy_profit.altarmy import Character, Profession

GOLDEN = (Path(__file__).parent / "fixtures" / "altarmy_export_v1.txt").read_text(encoding="utf-8")


def encoded(lines: str) -> str:
    """What the addon would show for `lines` (raw DEFLATE, LibDeflate's printable encoding)."""
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return paste.PREFIX + paste.encode_for_print(c.compress(lines.encode()) + c.flush())


def test_decodes_the_addons_golden_export() -> None:
    got = paste.decode(GOLDEN)
    assert (got.interface, got.build) == (20506, "2.5.6.69795")
    assert got.characters == [
        Character("Classic Beta PvE", "Tailor Guy", "", "PRIEST", 20, ()),
        Character(
            "Dreamscythe",
            "Frell",
            "Horde",
            "MAGE",
            70,
            (
                Profession("Cooking", 1, 75, frozenset()),
                Profession("Enchanting", 300, 375, frozenset({7418, 7420})),
                Profession("Tailoring", 375, 375, frozenset({26745, 26746})),
            ),
        ),
    ]


def test_print_encoding_round_trips() -> None:
    for data in (b"", b"a", b"ab", b"abc", bytes(range(256))):
        assert paste.decode_for_print(paste.encode_for_print(data)) == data


def test_surrounding_whitespace_is_ignored() -> None:
    assert paste.decode(f"  \n{GOLDEN}\r\n ").interface == 20506


def test_version_of_the_client() -> None:
    assert paste.decode(GOLDEN).game_version == "tbc"
    assert paste.decode(encoded("V|1|16001|1.60.1")).game_version == "forever"
    assert paste.decode(encoded("V|1|30400|3.4.0")).game_version is None


@pytest.mark.parametrize(
    "text",
    [
        "",
        "hello",
        "AAX2:abc",  # a newer format
        "AAX1:***",  # not the print alphabet
        GOLDEN[:-12],  # truncated
        "AAX1:" + "a" * 40,  # not DEFLATE
    ],
)
def test_bad_strings_raise_value_error(text: str) -> None:
    with pytest.raises(ValueError):
        paste.decode(text)


@pytest.mark.parametrize(
    "lines",
    [
        "C|R|N|Horde|MAGE|1",  # no version line
        "V|2|20506|x",  # unknown export version
        "V|1|20506|x\nP|Tailoring|1|75|1",  # a profession before any character
        "V|1|20506|x\nC|R|N|Horde|MAGE|lots",
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nP|Tailoring|1|75|1,x",
        "V|1|20506|x\nZ|what",
    ],
)
def test_malformed_lines_raise_value_error(lines: str) -> None:
    with pytest.raises(ValueError):
        paste.decode(encoded(lines))


def test_size_is_capped() -> None:
    huge = "V|1|20506|x\n" + "C|R|N|Horde|MAGE|1\n" * 20_000
    with pytest.raises(ValueError, match="too large"):
        paste.decode(encoded(huge), max_bytes=100_000)
