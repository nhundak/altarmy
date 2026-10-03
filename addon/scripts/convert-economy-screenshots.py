"""Convert the alt-army.com screenshots shown on the Economy tab's Supply Chain page into TGA textures.

Usage: python scripts/convert-economy-screenshots.py [--src <folder>]
Requires Pillow. Reads "search results.png", "flow chart.png" and "detailed steps.png" from --src
(default: ~/Downloads) and writes 24-bit uncompressed TGAs at their native size under
AltArmy_TBC/Textures/Economy/. The client loads non-power-of-two TGAs (see QuestRewardPreview_*.tga).
If a size changes, update IMAGES in Tabs/TabEconomySupplyChain.lua.
"""
import argparse
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "AltArmy_TBC", "Textures", "Economy")
SHOTS = [
    ("search results.png", "SupplyChainSearchResults.tga"),
    ("flow chart.png", "SupplyChainFlowChart.tga"),
    ("detailed steps.png", "SupplyChainDetailedSteps.tga"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(os.path.expanduser("~"), "Downloads"))
    args = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)
    for src, dst in SHOTS:
        img = Image.open(os.path.join(args.src, src)).convert("RGB")
        img.save(os.path.join(OUT_DIR, dst), format="TGA", compression=None)
        print(f"{dst}: {img.width}x{img.height}")


if __name__ == "__main__":
    main()
