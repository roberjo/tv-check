# Developing Daybreak

How to build, test, install and release Daybreak. For what the app shows and why, see [`DAYBREAK.md`](../DAYBREAK.md). For the code layout, see [`daybreak/README.md`](../daybreak/README.md).

## Setup
```sh
python3 -m venv .venv && .venv/bin/pip install pillow fonttools pyflakes
cp .env.example .env                               # TV IP, dev password, calendar iCal URL
cp config/family.example.json config/family.json   # your household (gitignored)
```
The tests need Node 20 or newer. They fetch `@rokucommunity/brs` and `brighterscript` with `npx` on first run.

## Test
| Command | What it covers | Network |
|---|---|---|
| `daybreak/tests/run.sh` | Library: curbside rules (2026 verified, 2027 provisional), dates, moon and showers, iCal with RRULE and EXDATE | No |
| `daybreak/tests/run_data.sh` | `derive()` and every screen against the synthetic feeds in `tests/fixtures/feeds/`, with the clock pinned to Sunday 2026-10-18 10:00 AM | No |
| `daybreak/tests/run_live.sh` | Smoke run against today's real feeds. Fetch them first with `fetch_fixtures.sh` | Yes |
| `.venv/bin/python daybreak/build_channel.py --check` | BrighterScript type and scope check | No |

Each runner exits non-zero on a failed check, a BrightScript runtime error, or a run that stops before its summary.

**Changing fixtures:** edit `daybreak/tests/make_fixtures.py`, run it, and commit the regenerated `fixtures/feeds/`. CI fails if the committed files don't match the generator.

**Pinning the clock:** tests set `m.testNowUtc` and `m.testNowWall` (see `tests/harness.brs`). `tNowUtc()` and `tNowWall()` return them when set. Nothing on the TV sets them.

**Off-device limits:** `@rokucommunity/brs` doesn't measure text (`boundingRect()` is 0), so `uiWidth` and `uiHeight` fall back to estimates there. It also has no registry, memory monitor or `roUrlTransfer`, so code that uses them must check for `invalid`.

## Build
```sh
.venv/bin/python daybreak/build_channel.py
```
This generates fonts, images and `source/config.brs` (gitignored, because it holds the private calendar URL), runs BrighterScript, and writes `daybreak/dist/daybreak.zip`. The package's manifest gets `build_version` = the git commit count. The tracked manifest holds only the major and minor version.

## Install on the TV
**Only install when nobody is watching.**
```sh
python3 scripts/deploy.py --check   # read-only: is the TV idle?
python3 scripts/deploy.py           # asks, re-checks, uploads, logs
```
The script refuses while the media player is active or another app is open. It reads the dev installer credentials from `.env`.

## CI
`.github/workflows/ci.yml` runs on pushes to `main` and on every PR. It checks that the fixtures match the generator, runs the three no-network suites, the BrighterScript check and pyflakes. It uses only committed, synthetic data.

## Releases
1. Work happens on a branch per release (`release/<x.y>-<topic>`), with commits that reference issues.
2. Open a PR against `main` that closes the release's issues. CI must pass before merging.
3. Bump `minor_version` (or `major_version`) in `daybreak/channel/manifest`, and add a section to `CHANGELOG.md`.
4. After merging, tag `v<x.y.z>` on `main` and publish a GitHub release using the changelog section as notes. No binary is attached, because a real package embeds private household settings.
5. Move the issues to **Done** on the [project board](https://github.com/users/roberjo/projects/2).

## Privacy checklist before pushing
The repo is public. Never commit `.env`, `config/family.json`, `ACTIVITY_LOG.md`, `captures/`, `source/config.brs` or live fixtures; `.gitignore` covers all of them. Use the fictional family in `config/family.example.json` and the synthetic calendar for anything committed, including screenshots.
