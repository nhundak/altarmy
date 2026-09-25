"""Decode the Alt Army addon's paste export: characters, professions and learned recipes as one string,
pasted on the Upload tab instead of uploading AltArmy_TBC.lua (no /reload needed).

The addon (`AltArmy_TBC/Data/ProfitExport.lua`) writes "AAX1:" plus LibDeflate's printable encoding of raw
DEFLATE of these lines:

    V|1|<interface>|<build>                       the client, so the export says which game it is from
    C|<realm>|<name>|<faction>|<CLASS_FILE>|<level>
    P|<profession>|<rank>|<maxRank>|<recipe ids>  belongs to the C line before it; ids comma-separated

Recipe ids are craft spell ids with aliases already resolved, as `altarmy.parse_characters` reads them.
The string is untrusted: anything wrong raises ValueError (the API's 400).
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass

from . import versions
from .altarmy import Character, Profession

PREFIX = "AAX1:"
FORMAT_VERSION = "1"
MAX_BYTES = 32 * 2**20  # decompressed, as for uploaded files

# LibDeflate's EncodeForPrint alphabet: 6 bits per character, little-endian.
_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
_VALUE = {c: i for i, c in enumerate(_ALPHABET)}


@dataclass(frozen=True)
class Export:
    interface: int  # the client's interface number, e.g. 20506
    build: str  # e.g. 2.5.6.69795
    characters: list[Character]  # sorted by realm then name

    @property
    def game_version(self) -> str | None:
        """The game version whose client made the export; None for a client this app doesn't serve."""
        return next((v.key for v in versions.VERSIONS.values() if v.interface == self.interface), None)


def encode_for_print(data: bytes) -> str:
    """LibDeflate:EncodeForPrint (for tests and tools; the addon does the encoding)."""
    out = []
    i = 0
    while i + 3 <= len(data):
        n = data[i] | data[i + 1] << 8 | data[i + 2] << 16
        out.append("".join(_ALPHABET[n >> s & 63] for s in (0, 6, 12, 18)))
        i += 3
    n, bits = 0, 0
    for b in data[i:]:
        n |= b << bits
        bits += 8
    while bits > 0:
        out.append(_ALPHABET[n & 63])
        n >>= 6
        bits -= 6
    return "".join(out)


def decode_for_print(text: str) -> bytes:
    """LibDeflate:DecodeForPrint; ValueError on a character it can't have produced."""
    try:
        values = [_VALUE[c] for c in text]
    except KeyError as e:
        raise ValueError(f"unexpected character {e.args[0]!r} in the export") from None
    out = bytearray()
    whole = len(values) - len(values) % 4
    for i in range(0, whole, 4):
        n = values[i] | values[i + 1] << 6 | values[i + 2] << 12 | values[i + 3] << 18
        out += bytes((n & 255, n >> 8 & 255, n >> 16 & 255))
    n, bits = 0, 0
    for v in values[whole:]:
        n |= v << bits
        bits += 6
    while bits >= 8:
        out.append(n & 255)
        n >>= 8
        bits -= 8
    return bytes(out)


def decode(text: str, max_bytes: int = MAX_BYTES) -> Export:
    """The export in `text` (surrounding and embedded whitespace ignored)."""
    text = "".join(text.split())
    if not text.startswith(PREFIX):
        raise ValueError(
            "not an Alt Army export: copy the whole string the addon shows (it starts with AAX1:)"
        )
    raw = decode_for_print(text[len(PREFIX) :])
    inflate = zlib.decompressobj(-15)
    try:
        body = inflate.decompress(raw, max_bytes + 1)
    except zlib.error as e:
        raise ValueError(f"the export is damaged ({e}): copy it again") from None
    if len(body) > max_bytes:
        raise ValueError("the export is too large")
    if not inflate.eof:
        raise ValueError("the export is cut short: copy the whole string again")
    try:
        lines = body.decode("utf-8").split("\n")
    except UnicodeDecodeError:
        raise ValueError("the export is damaged: copy it again") from None
    return _parse(lines)


def _parse(lines: list[str]) -> Export:
    head = lines[0].split("|")
    if len(head) != 4 or head[0] != "V":
        raise ValueError("the export has no version line")
    if head[1] != FORMAT_VERSION:
        raise ValueError(f"export format {head[1]!r} is not supported: update the site or the addon")
    interface = _int(head[2], "interface")
    chars: list[Character] = []
    current: tuple[list[str], list[Profession]] | None = None
    for line in lines[1:]:
        fields = line.split("|")
        if fields[0] == "C" and len(fields) == 6:
            if current is not None:
                chars.append(_character(*current))
            current = (fields[1:], [])
        elif fields[0] == "P" and len(fields) == 5:
            if current is None:
                raise ValueError("the export lists a profession before any character")
            name, rank, max_rank, ids = fields[1:]
            recipe_ids = frozenset(_int(i, "recipe id") for i in ids.split(",") if i)
            current[1].append(Profession(name, _int(rank, "rank"), _int(max_rank, "max rank"), recipe_ids))
        elif line.strip():
            raise ValueError(f"unexpected line in the export: {line[:40]!r}")
    if current is not None:
        chars.append(_character(*current))
    return Export(interface, head[3], sorted(chars, key=lambda c: (c.realm, c.name)))


def _character(fields: list[str], professions: list[Profession]) -> Character:
    realm, name, faction, class_file, level = fields
    return Character(
        realm,
        name,
        faction,
        class_file,
        _int(level, "level"),
        tuple(sorted(professions, key=lambda p: p.name)),
    )


def _int(text: str, what: str) -> int:
    if not text.isascii() or not text.isdigit() or len(text) > 12:
        raise ValueError(f"bad {what} {text[:20]!r} in the export")
    return int(text)
