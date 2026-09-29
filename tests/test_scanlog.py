"""The Alt Army addon's log of Auctionator's price updates, and the faction it names for an upload."""

from altarmy_profit import scanlog
from altarmy_profit.scanlog import Scan


def scan_log(*scans: tuple[int, str]) -> bytes:
    """An `AltArmy_TBC.lua` holding the log (as the client writes it) after a big `AltArmyTBC_Data`."""
    entries = "".join(
        f'\t\t{{\n\t\t\t["t"] = {t},\n\t\t\t["faction"] = "{faction}",\n\t\t\t["key"] = "ClassicBetaPvE",\n'
        f'\t\t\t["realm"] = "Classic Beta PvE",\n\t\t}}, -- [{i}]\n'
        for i, (t, faction) in enumerate(scans, 1)
    )
    log = f'AltArmyTBC_AuctionScans = {{\n\t["version"] = 1,\n\t["scans"] = {{\n{entries}\t}},\n}}\n'
    return b'AltArmyTBC_Data = {\n\t["Characters"] = {},\n}\n' + log.encode()


def test_reads_the_log_oldest_first() -> None:
    assert scanlog.read(scan_log((200, "Alliance"), (100, "Horde"))) == [
        Scan(100, "Horde", "ClassicBetaPvE"),
        Scan(200, "Alliance", "ClassicBetaPvE"),
    ]


def test_a_missing_or_mangled_log_reads_empty() -> None:
    assert scanlog.read(b"AltArmyTBC_Data = {\n}\n") == []
    assert scanlog.read(b"AltArmyTBC_AuctionScans = {{{\n") == []
    assert scanlog.read(b'AltArmyTBC_AuctionScans = {\n\t["scans"] = "no",\n}\n') == []
    odd = (
        b'AltArmyTBC_AuctionScans = {\n\t["scans"] = { 1, { ["t"] = "x" },\n'
        b'\t\t{ ["t"] = 5, ["faction"] = "Neutral" }, { ["t"] = 7, ["faction"] = "Horde" } },\n}\n'
    )
    assert scanlog.read(odd) == [Scan(7, "Horde", "")]


def test_the_faction_of_the_updates_since_the_last_upload() -> None:
    scans = [Scan(100, "Alliance", "k"), Scan(200, "Horde", "k"), Scan(300, "Horde", "k")]
    assert scanlog.scan_faction(scans, since=150, until=400) == "Horde"
    assert scanlog.scan_faction(scans, since=50, until=400) is None  # mixed
    assert scanlog.scan_faction(scans, since=300, until=400) is None  # nothing new
    assert scanlog.scan_faction(scans, since=50, until=130) == "Alliance"  # later ones are not in the file
    assert scanlog.scan_faction(scans, since=250, until=300 - scanlog.SLACK) == "Horde"


def test_without_an_earlier_upload_the_newest_update_decides() -> None:
    scans = [Scan(100, "Alliance", "k"), Scan(200, "Horde", "k")]
    assert scanlog.scan_faction(scans, since=None, until=400) == "Horde"
    assert scanlog.scan_faction(scans, since=None, until=130) == "Alliance"
    assert scanlog.scan_faction([], since=None, until=400) is None
