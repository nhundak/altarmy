"""Regenerate the Gear tab sub-view icons (2x2 Grid / scales Upgrade Check) as 64x64 32-bit TGAs.

Usage: python scripts/generate-gear-view-icons.py [--preview <png>]
Requires Pillow. Paints at 512px and downsamples, in the style of retail WoW icons: gold
bevelled metal on a dark painted background with a vignette. See docs/UI_DESIGN.md.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "AltArmy_TBC", "Textures", "Icons")
S = 512  # working size
OUT = 64

GOLD_LIGHT = (255, 232, 150)
GOLD_MID = (224, 170, 60)
GOLD_DARK = (120, 70, 18)
OUTLINE = (28, 14, 4, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def radial_background(inner, outer, center=(0.5, 0.42), seed=1):
    """Painted radial gradient + mottled noise + dark vignette (retail icon backdrop)."""
    img = Image.new("RGB", (S, S))
    px = img.load()
    cx, cy = center[0] * S, center[1] * S
    maxd = math.hypot(S, S) * 0.62
    for y in range(S):
        for x in range(S):
            t = min(1.0, math.hypot(x - cx, y - cy) / maxd)
            px[x, y] = lerp(inner, outer, t ** 0.9)
    rnd = random.Random(seed)
    noise = Image.new("L", (32, 32))
    noise.putdata([rnd.randint(0, 255) for _ in range(32 * 32)])
    noise = noise.resize((S, S), Image.BICUBIC).filter(ImageFilter.GaussianBlur(10))
    dark = Image.new("RGB", (S, S), (0, 0, 0))
    img = Image.composite(img, dark, noise.point(lambda v: 200 + v * 55 // 255))
    vig = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(vig)
    d.rectangle((S * 0.04, S * 0.04, S * 0.96, S * 0.96), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(S * 0.08)).point(lambda v: 90 + v * 165 // 255)
    return Image.composite(img, dark, vig).convert("RGBA")


def metal_fill(mask, light=GOLD_LIGHT, mid=GOLD_MID, dark=GOLD_DARK, top=0, bottom=S):
    """Vertical metal gradient clipped to mask, with an inner bevel (lit top-left)."""
    grad = Image.new("RGB", (S, S))
    gd = ImageDraw.Draw(grad)
    span = max(1, bottom - top)
    for y in range(S):
        t = min(1.0, max(0.0, (y - top) / span))
        c = lerp(light, mid, t / 0.45) if t < 0.45 else lerp(mid, dark, (t - 0.45) / 0.55)
        gd.line([(0, y), (S, y)], fill=c)
    # Bevel: highlight where the mask shifted down-right still covers, shadow the other way.
    blur = mask.filter(ImageFilter.GaussianBlur(4))
    hi = ImageChops.subtract(blur, blur.transform(blur.size, Image.AFFINE, (1, 0, -5, 0, 1, -5)))
    lo = ImageChops.subtract(blur, blur.transform(blur.size, Image.AFFINE, (1, 0, 5, 0, 1, 5)))
    grad = Image.composite(Image.new("RGB", (S, S), (255, 248, 210)), grad, hi.point(lambda v: min(255, v * 3)))
    grad = Image.composite(Image.new("RGB", (S, S), (60, 30, 5)), grad, lo.point(lambda v: min(200, v * 2)))
    out = grad.convert("RGBA")
    out.putalpha(mask)
    return out


def with_outline(layer, width=10):
    """Dark outline + soft drop shadow behind a layer (keeps shapes readable at 32px)."""
    alpha = layer.getchannel("A")
    grown = alpha.filter(ImageFilter.MaxFilter(width * 2 + 1))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    shadow.putalpha(grown.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 170 // 255))
    base.alpha_composite(shadow, (8, 12))
    ring = Image.new("RGBA", (S, S), OUTLINE)
    ring.putalpha(grown)
    base.alpha_composite(ring)
    base.alpha_composite(layer)
    return base


def glow(color, mask, radius=30, strength=0.8):
    g = Image.new("RGBA", (S, S), color + (255,))
    g.putalpha(mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: int(v * strength)))
    return g


def finish(img):
    small = img.resize((OUT, OUT), Image.LANCZOS)
    return small.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))


# ---------------------------------------------------------------- Grid
def grid_icon():
    img = radial_background((52, 92, 120), (8, 14, 24), seed=3)
    n, pad, gap = 2, 64, 30
    cell = (S - 2 * pad - (n - 1) * gap) / n
    frame_mask = Image.new("L", (S, S), 0)
    well_mask = Image.new("L", (S, S), 0)
    fd, wd = ImageDraw.Draw(frame_mask), ImageDraw.Draw(well_mask)
    inset = 38
    for r in range(n):
        for c in range(n):
            x0 = pad + c * (cell + gap)
            y0 = pad + r * (cell + gap)
            box = (x0, y0, x0 + cell, y0 + cell)
            fd.rounded_rectangle(box, radius=20, fill=255)
            wd.rounded_rectangle((x0 + inset, y0 + inset, x0 + cell - inset, y0 + cell - inset),
                                 radius=9, fill=255)
    frames = metal_fill(ImageChops.subtract(frame_mask, well_mask), top=pad, bottom=S - pad)
    img.alpha_composite(glow((120, 200, 255), frame_mask, radius=40, strength=0.45))
    img.alpha_composite(with_outline(frames, width=7))
    # Cell wells: deep blue glass with a lit top edge; top-left cell glows (the "selected" slot).
    wells = Image.new("RGBA", (S, S))
    wdraw = ImageDraw.Draw(wells)
    for r in range(n):
        for c in range(n):
            x0 = pad + c * (cell + gap) + inset
            y0 = pad + r * (cell + gap) + inset
            w = cell - 2 * inset
            lit = (r, c) == (0, 0)
            for i in range(int(w)):
                t = i / w
                col = lerp((130, 220, 255), (30, 90, 150), t) if lit else lerp((50, 80, 110), (10, 20, 34), t)
                wdraw.line([(x0, y0 + i), (x0 + w, y0 + i)], fill=col + (255,))
    wells.putalpha(ImageChops.multiply(wells.getchannel("A"), well_mask))
    img.alpha_composite(wells)
    return finish(img)


# ---------------------------------------------------------------- Scales
def scales_icon():
    img = radial_background((120, 60, 150), (16, 6, 26), seed=7)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx = S / 2
    tilt = math.radians(-12)  # left pan lower, so it reads as weighing rather than a static logo
    beam_y = 150
    half = 150

    def rot(dx, dy):
        return (cx + dx * math.cos(tilt) - dy * math.sin(tilt), beam_y + dx * math.sin(tilt) + dy * math.cos(tilt))

    # Pillar, base and finial
    d.rectangle((cx - 20, beam_y, cx + 20, 420), fill=255)
    d.polygon([(cx - 90, 440), (cx + 90, 440), (cx + 50, 400), (cx - 50, 400)], fill=255)
    d.rounded_rectangle((cx - 110, 432, cx + 110, 462), radius=10, fill=255)
    d.ellipse((cx - 30, beam_y - 62, cx + 30, beam_y - 2), fill=255)
    # Beam
    d.polygon([rot(-half, -12), rot(half, -12), rot(half, 12), rot(-half, 12)], fill=255)
    for sgn in (-1, 1):
        ex, ey = rot(sgn * half, 0)
        d.ellipse((ex - 22, ey - 22, ex + 22, ey + 22), fill=255)
    metal = metal_fill(m, top=80, bottom=470)

    # Chains + pans (drawn separately so the pans can sit in front of the chains)
    chains = Image.new("L", (S, S), 0)
    pans = Image.new("L", (S, S), 0)
    cd, pd = ImageDraw.Draw(chains), ImageDraw.Draw(pans)
    for sgn in (-1, 1):
        ex, ey = rot(sgn * half, 0)
        py = ey + 150
        for off in (-58, 58):
            cd.line([(ex, ey), (ex + off, py)], fill=255, width=12)
        pd.pieslice((ex - 84, py - 60, ex + 84, py + 60), 0, 180, fill=255)
        pd.rounded_rectangle((ex - 88, py - 9, ex + 88, py + 9), radius=8, fill=255)
    chain_layer = metal_fill(chains, light=(250, 220, 150), mid=(190, 140, 60), dark=(110, 70, 20))
    pan_layer = metal_fill(pans, top=260, bottom=400)

    whole = Image.new("RGBA", (S, S))
    whole.alpha_composite(chain_layer)
    whole.alpha_composite(metal)
    whole.alpha_composite(pan_layer)
    all_mask = ImageChops.lighter(ImageChops.lighter(m, chains), pans)
    img.alpha_composite(glow((255, 200, 110), all_mask, radius=36, strength=0.5))
    img.alpha_composite(with_outline(whole, width=7))
    return finish(img)


def save_tga(img, name):
    path = os.path.join(OUT_DIR, name)
    img.save(path, format="TGA")
    print("wrote", os.path.normpath(path))


def main():
    icons = {"GearViewGrid.tga": grid_icon(), "GearViewUpgradeCheck.tga": scales_icon()}
    for name, img in icons.items():
        save_tga(img, name)
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        # 64px, 36px (tab size) and 24px on a dark strip for eyeballing readability.
        sizes = (128, 64, 36, 24)
        sheet = Image.new("RGBA", (sum(sizes) * 2 + 60, 2 * 140), (24, 24, 24, 255))
        for row, img in enumerate(icons.values()):
            x = 10
            for sz in sizes:
                sheet.alpha_composite(img.resize((sz, sz), Image.LANCZOS), (x, row * 140 + 6))
                x += sz + 12
        sheet.save(sys.argv[2])
        print("preview", sys.argv[2])


if __name__ == "__main__":
    main()
