"""Visual regression: compare preview renders with saved reference images.

The design audit checks text size and contrast, not layout; a wrong
coordinate was only noticed by eye. This compares each screen rendered by
`preview.sh <dir> --stable` (no team logos, no radar base map: only what's in
the repo) with daybreak/preview/reference/<screen>.png, a quarter-size copy
(480x270). A pixel counts as changed when a channel differs by more than
CHANNEL_TOLERANCE; a screen fails when more than PIXEL_TOLERANCE of its
pixels changed (font rasterizing differs a little between machines).

On failure, <render-dir>/diff/<screen>.png shows reference | new | changes.

Usage:
  sh daybreak/preview/preview.sh out/stable --stable
  .venv/bin/python daybreak/preview/visual_diff.py out/stable            # compare
  .venv/bin/python daybreak/preview/visual_diff.py out/stable --update   # accept intentional changes
"""
import pathlib
import sys

from PIL import Image, ImageChops

HERE = pathlib.Path(__file__).resolve().parent
REF = HERE / "reference"
SIZE = (480, 270)
CHANNEL_TOLERANCE = 32
PIXEL_TOLERANCE = 0.0002  # 0.02% of the pixels: about 26 at 480x270 (a 24 px label moved 20 px is ~0.1%)


def small(path):
    return Image.open(path).convert("RGB").resize(SIZE, Image.LANCZOS)


def changed_mask(a, b):
    diff = ImageChops.difference(a, b).split()
    worst = ImageChops.lighter(ImageChops.lighter(diff[0], diff[1]), diff[2])
    return worst.point(lambda v: 255 if v > CHANNEL_TOLERANCE else 0)


def diff_image(ref, new, mask):
    out = Image.new("RGB", (SIZE[0] * 3, SIZE[1]), "black")
    out.paste(ref, (0, 0))
    out.paste(new, (SIZE[0], 0))
    faded = Image.blend(new, Image.new("RGB", SIZE, "black"), 0.7)
    faded.paste((255, 40, 120), (0, 0), mask)
    out.paste(faded, (SIZE[0] * 2, 0))
    return out


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.exit(__doc__)
    renders = pathlib.Path(argv[0])
    update = "--update" in argv
    shots = {p.stem: p for p in sorted(renders.glob("*.png"))}
    if not shots:
        sys.exit(f"no renders in {renders}: run preview.sh {renders} --stable first")
    if update:
        REF.mkdir(exist_ok=True)
        for name, p in shots.items():
            small(p).save(REF / f"{name}.png", optimize=True)
        for old in REF.glob("*.png"):
            if old.stem not in shots:
                old.unlink()
        print(f"visual diff: {len(shots)} reference image(s) updated in {REF.relative_to(HERE.parent.parent)}")
        return 0
    failures = []
    diffs = renders / "diff"
    for name, p in shots.items():
        ref_path = REF / f"{name}.png"
        if not ref_path.exists():
            failures.append(f"{name}: new screen with no reference (run with --update if intended)")
            continue
        ref, new = Image.open(ref_path).convert("RGB"), small(p)
        mask = changed_mask(ref, new)
        frac = mask.histogram()[255] / (SIZE[0] * SIZE[1])
        status = "ok" if frac <= PIXEL_TOLERANCE else "CHANGED"
        print(f"{name}: {frac:.3%} changed, {status}")
        if frac > PIXEL_TOLERANCE:
            diffs.mkdir(exist_ok=True)
            diff_image(ref, new, mask).save(diffs / f"{name}.png")
            failures.append(f"{name}: {frac:.2%} of pixels changed (diff/{name}.png)")
    for ref_path in sorted(REF.glob("*.png")):
        if ref_path.stem not in shots:
            failures.append(f"{ref_path.stem}: reference has no render (screen removed? run with --update)")
    for f in failures:
        print("  FAIL", f)
    print(f"visual diff: {len(shots) - len([f for f in failures if 'changed' in f or 'new screen' in f])}/{len(shots)} unchanged")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
