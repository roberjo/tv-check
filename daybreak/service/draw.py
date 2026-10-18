"""Drawing toolkit for Daybreak screens: 1920x1080 canvases, Outfit/Manrope at
any weight, wrapped text, rounded cards, weather icons and photo backgrounds.
Mirrors the design canvas tokens."""
import functools
import math
import pathlib

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
W, H = 1920, 1080

INK = (11, 17, 32)
INK_DEEP = (7, 11, 20)
CARD = (19, 27, 46)
CARD_LINE = (31, 42, 68)
CHIP = (26, 36, 64)
TEXT = (244, 241, 234)
TEXT_2 = (169, 177, 196)
TEXT_2_ON_PHOTO = (225, 228, 236)
AMBER = (244, 162, 89)
VIOLET = (179, 166, 242)
BLUE = (127, 183, 232)
GREEN = (158, 199, 155)
RED = (186, 12, 47)
MARGIN_X, MARGIN_Y = 112, 64


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


@functools.lru_cache(maxsize=256)
def font(size, weight=400, family="Manrope"):
    f = ImageFont.truetype(str(HERE / "fonts" / f"{family}.ttf"), size)
    f.set_variation_by_axes([weight])
    return f


def display(size, weight=400):
    return font(size, weight, "Outfit")


class Screen:
    def __init__(self, bg=INK):
        self.img = Image.new("RGB", (W, H), bg)
        self.d = ImageDraw.Draw(self.img, "RGBA")

    # --- backgrounds ---------------------------------------------------------
    def photo(self, name, dim, tint=INK):
        im = Image.open(HERE / "assets" / name).convert("RGB")
        s = max(W / im.width, H / im.height)
        im = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.LANCZOS)
        l, t = (im.width - W) // 2, (im.height - H) // 2
        im = im.crop((l, t, l + W, t + H))
        self.img.paste(Image.blend(im, Image.new("RGB", (W, H), tint), dim))

    # --- shapes ----------------------------------------------------------------
    def card(self, x, y, w, h, fill=CARD, outline=CARD_LINE, r=28, width=1):
        self.d.rounded_rectangle((x, y, x + w, y + h), r, fill=fill, outline=outline, width=width)

    def bar(self, x, y, w, h, fill, r=None):
        self.d.rounded_rectangle((x, y, x + w, y + h), r if r is not None else h // 2, fill=fill)

    def dot(self, x, y, r, fill):
        self.d.ellipse((x - r, y - r, x + r, y + r), fill=fill)

    # --- text ------------------------------------------------------------------
    def text(self, x, y, s, size, weight=400, fill=TEXT, fam="Manrope", anchor="la", spacing=0.0):
        f = font(size, weight, fam)
        if spacing:
            for ch in s:
                self.d.text((x, y), ch, font=f, fill=fill, anchor=anchor)
                x += f.getlength(ch) + size * spacing
            return x
        self.d.text((x, y), s, font=f, fill=fill, anchor=anchor)
        return x + f.getlength(s)

    def label(self, x, y, s, size=22, fill=TEXT_2):
        """Small caps-style section label with letter spacing."""
        return self.text(x, y, s.upper(), size, 700, fill, spacing=0.14)

    def measure(self, s, size, weight=400, fam="Manrope"):
        return font(size, weight, fam).getlength(s)

    def wrap(self, s, size, width, weight=400, fam="Manrope", max_lines=2):
        f = font(size, weight, fam)
        words, lines, cur = s.split(), [], ""
        for w_ in words:
            trial = (cur + " " + w_).strip()
            if f.getlength(trial) <= width:
                cur = trial
            else:
                if cur:
                    lines.append(cur)
                cur = w_
        if cur:
            lines.append(cur)
        if len(lines) > max_lines:
            lines = lines[:max_lines]
            while f.getlength(lines[-1] + "…") > width and " " in lines[-1]:
                lines[-1] = lines[-1].rsplit(" ", 1)[0]
            lines[-1] += "…"
        return lines

    def para(self, x, y, s, size, width, weight=400, fill=TEXT, fam="Manrope", max_lines=2, leading=1.3):
        lines = self.wrap(s, size, width, weight, fam, max_lines)
        for i, line in enumerate(lines):
            self.text(x, y + i * size * leading, line, size, weight, fill, fam)
        return y + len(lines) * size * leading

    def fit(self, s, size, width, weight=400, fam="Manrope", min_size=18):
        """Largest size <= size that fits on one line."""
        while size > min_size and self.measure(s, size, weight, fam) > width:
            size -= 1
        return size

    # --- icons -----------------------------------------------------------------
    def icon(self, kind, cx, cy, s, color=TEXT, stroke=None):
        st = stroke or max(2, int(s * 0.07))
        d = self.d
        if kind in ("sun", "partly"):
            sx, sy, r = (cx, cy, s * 0.22) if kind == "sun" else (cx - s * 0.12, cy - s * 0.12, s * 0.18)
            d.ellipse((sx - r, sy - r, sx + r, sy + r), outline=color, width=st)
            for i in range(8):
                a = i * math.pi / 4
                d.line((sx + math.cos(a) * r * 1.45, sy + math.sin(a) * r * 1.45,
                        sx + math.cos(a) * r * 1.95, sy + math.sin(a) * r * 1.95), fill=color, width=st)
        if kind in ("cloud", "partly", "rain", "storm", "snow"):
            ox = cx + (s * 0.08 if kind == "partly" else 0)
            oy = cy + (s * 0.1 if kind == "partly" else -s * 0.05)
            box = (ox - s * 0.38, oy - s * 0.02, ox + s * 0.38, oy + s * 0.22)
            if kind == "partly":
                d.rounded_rectangle(box, int(s * 0.12), fill=INK)
            d.rounded_rectangle(box, int(s * 0.12), outline=color, width=st)
            d.ellipse((ox - s * 0.2, oy - s * 0.24, ox + s * 0.14, oy + s * 0.1), fill=INK if kind == "partly" else None, outline=color, width=st)
            d.rounded_rectangle((box[0] + st, oy, box[2] - st, box[3] - st), int(s * 0.1), fill=INK)
            d.arc((ox - s * 0.2, oy - s * 0.24, ox + s * 0.14, oy + s * 0.1), 160, 360, fill=color, width=st)
            d.line((box[0] + s * 0.1, box[3], box[2] - s * 0.1, box[3]), fill=color, width=st)
            if kind == "rain":
                for i in (-1, 0, 1):
                    x0 = ox + i * s * 0.18
                    d.line((x0, oy + s * 0.32, x0 - s * 0.06, oy + s * 0.46), fill=color, width=st)
            if kind == "snow":
                for i in (-1, 0, 1):
                    self.dot(ox + i * s * 0.18, oy + s * 0.38, st, color)
            if kind == "storm":
                d.line((ox, oy + s * 0.26, ox - s * 0.08, oy + s * 0.4, ox + s * 0.04, oy + s * 0.4, ox - s * 0.04, oy + s * 0.52), fill=color, width=st)
        if kind == "moon":
            r = s * 0.3
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
            d.ellipse((cx - r * 0.45, cy - r * 1.15, cx + r * 1.55, cy + r * 0.85), fill=INK)

    def save(self, path, quality=90):
        self.img.save(path, "JPEG", quality=quality, optimize=True, progressive=True)


def moon_image(size, illum, waxing, lit=(233, 228, 214), dark=(26, 31, 51)):
    """Moon disc with the terminator drawn as an ellipse (northern hemisphere view)."""
    k = 4
    S = size * k
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, S - 1, S - 1), fill=dark)
    half = Image.new("L", (S, S), 0)
    hd = ImageDraw.Draw(half)
    if waxing:
        hd.pieslice((0, 0, S - 1, S - 1), -90, 90, fill=255)
    else:
        hd.pieslice((0, 0, S - 1, S - 1), 90, 270, fill=255)
    rx = abs(1 - 2 * illum) * S / 2
    ell = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ell).ellipse((S / 2 - rx, 0, S / 2 + rx, S - 1), fill=255)
    from PIL import ImageChops
    mask = ImageChops.add(half, ell) if illum >= 0.5 else ImageChops.subtract(half, ell)
    im.paste(Image.new("RGBA", (S, S), lit), (0, 0), mask)
    disc = Image.new("L", (S, S), 0)
    ImageDraw.Draw(disc).ellipse((0, 0, S - 1, S - 1), fill=255)
    im.putalpha(ImageChops.multiply(im.getchannel("A"), disc))
    return im.resize((size, size), Image.LANCZOS)
