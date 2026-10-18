"""Render public-safe demo screenshots of Daybreak for docs: the fictional
family in config/family.example.json + the synthetic calendar in
daybreak/tests/fixtures/sample.ics, with real public data (weather, radar,
sports, lake). Writes docs/images/*.jpg.

Usage: .venv/bin/python scripts/render_demo.py
"""
import datetime as dt
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "daybreak" / "service"))
sys.path.insert(0, str(ROOT / "scripts"))
import family_calendar  # noqa: E402
import screens  # noqa: E402
import sources  # noqa: E402

example = json.loads((ROOT / "config" / "family.example.json").read_text())
sources.FAMILY = screens.FAMILY = example


def sample_calendar():
    text = (ROOT / "daybreak" / "tests" / "fixtures" / "sample.ics").read_text()
    today = sources.now().date()
    out = []
    for e in family_calendar.events(text):
        if e["cancelled"] or e["summary"].upper().startswith(("TV:", "BUY:")):
            continue
        for when in family_calendar.occurrences(e, today, today + dt.timedelta(days=21)):
            title = e["summary"]
            health = bool(sources.HEALTH.search(title))
            who = [m["name"] for m in example["members"] if m["name"] in title]
            out.append({"when": when, "all_day": not isinstance(when, dt.datetime),
                        "title": "Appointment" if health else title.replace(" — both kids", ""),
                        "who": who, "health": health, "school": bool(sources.SCHOOL.search(title)) and not health,
                        "deadline": "deadline" in title.lower()})
    return sorted(out, key=lambda e: screens.as_dt(e["when"]))


sources.calendar = sample_calendar
out = ROOT / "docs" / "images"
out.mkdir(parents=True, exist_ok=True)
data = screens.gather()
for name in ("briefing", "week", "recap", "ambient", "sky", "lake", "tonight"):
    sc, _ = screens.RENDERERS[name](data)
    if sc is not None:
        sc.img.resize((1280, 720)).save(out / f"{name}.jpg", "JPEG", quality=85, optimize=True)
        print("wrote", out / f"{name}.jpg")
if (screens.RADAR_DIR / "meta.json").exists():
    frames, _ = screens.render_radar(data)
    frames[-1][0].img.resize((1280, 720)).save(out / "radar.jpg", "JPEG", quality=85, optimize=True)
    print("wrote", out / "radar.jpg")
