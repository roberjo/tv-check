# tv-check → Daybreak

[![CI](https://github.com/roberjo/tv-check/actions/workflows/ci.yml/badge.svg)](https://github.com/roberjo/tv-check/actions/workflows/ci.yml) · [Releases](https://github.com/roberjo/tv-check/releases) · [Roadmap](https://github.com/users/roberjo/projects/2) · [Changelog](CHANGELOG.md)

**What started as "what can an AI learn about my TV over Wi-Fi?" ended up as Daybreak, a standalone family dashboard and screensaver running natively on a TCL Roku TV.**

Built in one evening, pair-programming with [Claude Code](https://claude.com/claude-code). The write-up is in [`docs/blog-post.md`](docs/blog-post.md).

| | |
|---|---|
| ![Morning briefing](docs/images/briefing.jpg) | ![Game recap](docs/images/recap.jpg) |
| ![Week ahead](docs/images/week.jpg) | ![Live radar](docs/images/radar.jpg) |
| ![Ambient screensaver](docs/images/ambient.jpg) | ![Tonight's sky](docs/images/sky.jpg) |

*Screenshots use a fictional family (`config/family.example.json`) and a synthetic calendar, with real public data: weather, radar, scores and West Point Lake's level.*

## What's here

| Path | What |
|---|---|
| `scripts/` | The exploration toolkit (Python stdlib): SSDP discovery, Roku ECP probe, port scan, AirPlay info, debug-console helper, health sampler, contrast checker, radar map renderer, City of LaGrange curbside rules, iCal reader |
| `FINDINGS.md`, `DIAGNOSTICS.md` | What a Roku TV exposes on the LAN, and a full health check (RAM, storage, network, codecs, DRM) with recommendations. Identifiers redacted |
| `diag-channel/` | A tiny sideloaded diagnostic app that reports display, codec, network, memory and DRM capabilities and runs a speed test |
| `daybreak/channel/` | **Daybreak**, the standalone Roku app (BrightScript and SceneGraph). The TV fetches everything itself |
| `daybreak/tests/` | Off-device tests run with [`@rokucommunity/brs`](https://github.com/rokucommunity/brs) against synthetic feeds and a synthetic calendar, with the clock pinned |
| `daybreak/service/` | Python reference renderer that draws the same screens as images on a Mac, for design previews |
| `concierge/` | A shelved experiment: Siri → Claude → Roku voice control |
| `DAYBREAK.md` | Daybreak design notes: screens, triggers, rules, visual system, licensing, privacy |
| `CLAUDE.md` | The working rules the AI followed: what's read-only, what needs permission first |
| `docs/DEVELOPMENT.md` | Build, test, CI, install and release process |

## Daybreak at a glance
- **Data, all fetched on the TV:**
  - **Weather:** Open-Meteo.
  - **Alerts:** National Weather Service.
  - **West Point Lake level:** USGS.
  - **Radar:** NOAA MRMS.
  - **Pro and SEC schedules:** ESPN's public JSON.
  - **LaGrange College athletics:** iCal feed.
  - **Local headlines:** Google News RSS.
  - **The family calendar:** Google Calendar secret iCal.
- **Rule-based "heads up" insights:** deadlines, schedule overlaps, curbside pickup (including holiday shifts), rain and frost, birthdays, meteor showers and low lake levels. No AI at runtime.
- **Family board through the calendar:** an event called `TV: Dinner at 6:30` shows as a note; `Buy: milk, eggs` adds to a grocery list.
- **Privacy defaults:** health appointments show as "Appointment", and violent-crime headlines are filtered out.
- **Design:** tested for readability, with contrast measured against the photo behind every line of text.

## Run it yourself
You need a Roku TV with **developer mode** on (Home ×3, Up ×2, Right, Left, Right, Left, Right) and "Control by mobile apps" set to **Enabled**. Both open interfaces to anyone on your LAN, so only do this on a network you trust.

```sh
python3 -m venv .venv && .venv/bin/pip install pillow fonttools
cp .env.example .env                                  # TV IP, dev password, calendar iCal URL
cp config/family.example.json config/family.json      # your household
.venv/bin/python daybreak/build_channel.py            # generates assets + config, validates, zips
python3 scripts/deploy.py                             # installs only if nobody is watching; asks first
# Then pick Settings → Theme → Screensaver → Daybreak.
```

Tests (Node required, no network):
```sh
daybreak/tests/run.sh                 # library: curbside, dates, sky, iCal (RRULE + EXDATE)
daybreak/tests/run_data.sh            # derive() + every screen against synthetic feeds
daybreak/tests/fetch_fixtures.sh && daybreak/tests/run_live.sh   # optional: today's real feeds
```
More in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

Daybreak is tuned for LaGrange, Georgia: the curbside schedule, West Point Lake, LaGrange College and the local news filter. Swap those sources out for your town.

## Licensing
- **Code:** MIT (see `LICENSE`).
- **Fonts:** Outfit and Manrope, SIL Open Font License 1.1 (`daybreak/service/fonts/OFL-*.txt`).
- **Photos:** Callaway Gardens, CC0 (Wikimedia Commons).
- **Map and radar data:** USGS and NOAA, public domain.

Not affiliated with Roku, TCL or any of the data providers.
