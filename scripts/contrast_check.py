"""Worst-case WCAG contrast of text over a dimmed photo, per screen region.

Usage: .venv/bin/python scripts/contrast_check.py <ambient.jpg> <main.jpg> <ambient_dim> <main_dim>
Daybreak uses this rule for every background: pick the lowest dim where all text
clears 4.5:1 (small) or 3:1 (large) against the 98th-percentile brightest pixels.
"""
import sys
from PIL import Image

def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def lum(rgb):
    r, g, b = (lin(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def cover(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    s = max(1920 / w, 1080 / h)
    im = im.resize((round(w * s), round(h * s)))
    l, t = (im.width - 1920) // 2, (im.height - 1080) // 2
    return im.crop((l, t, l + 1920, t + 1080))

def check(img, overlay_rgb, alpha, regions):
    for name, box, text_hex, need in regions:
        px = img.crop(box).resize((60, 30)).get_flattened_data()
        ls = sorted(lum(tuple(p * (1 - alpha) + o * alpha for p, o in zip(px_i, overlay_rgb))) for px_i in px)
        worst = ls[int(len(ls) * 0.98)]  # 98th percentile brightest background
        lt = lum(hexrgb(text_hex))
        ratio = (lt + 0.05) / (worst + 0.05)
        print(f"  {'OK ' if ratio >= need else 'LOW'} {ratio:5.1f}:1 (need {need}) {name}")

ambient, main, alpha_a, alpha_m = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
print(f"Ambient, overlay {alpha_a}")
check(cover(ambient), (7, 11, 20), alpha_a, [
    ("clock 300px", (160, 120, 900, 360), "#F4F1EA", 3),
    ("date 38px", (160, 380, 700, 450), "#E1E4EC", 3),
    ("temp 96px", (1450, 140, 1760, 250), "#F4F1EA", 3),
    ("conditions 30px", (1450, 260, 1760, 300), "#E1E4EC", 3),
    ("location 24px", (1550, 300, 1760, 340), "#E1E4EC", 4.5),
    ("sun stats 26px", (160, 920, 1150, 960), "#E1E4EC", 4.5),
    ("photo caption 20px", (160, 965, 800, 995), "#E1E4EC", 4.5),
])
print(f"Main, overlay {alpha_m}")
check(cover(main), (11, 17, 32), alpha_m, [
    ("eyebrow 24px", (112, 70, 1000, 100), "#F4A259", 4.5),
    ("greeting 78px", (112, 110, 1300, 200), "#F4F1EA", 3),
    ("clock 112px", (1480, 90, 1808, 200), "#F4F1EA", 3),
    ("AM 34px", (1700, 150, 1808, 200), "#A9B1C4", 3),
])
