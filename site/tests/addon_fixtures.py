"""The addon's golden files (the monorepo's addon/spec/fixtures), which the addon's own specs and the site's
parsers are both tested against, so the two sides can't drift apart unnoticed."""

from pathlib import Path

ADDON_FIXTURES = Path(__file__).resolve().parents[2] / "addon" / "spec" / "fixtures"
AUCTION_BOOK = ADDON_FIXTURES / "auction_book_v1.lua"  # AltArmyTBC_AuctionBook, written by AuctionScan.lua
PROFIT_EXPORT = ADDON_FIXTURES / "profit_export_v2.txt"  # the AAX1 export (format v2), by ProfitExport.lua
ADDON_TOC = ADDON_FIXTURES.parents[1] / "AltArmy_TBC" / "AltArmy_TBC.toc"  # its ## Interface: line
