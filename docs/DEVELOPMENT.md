# Developing Daybreak

How to build, test, install and release Daybreak. For what the app shows and why, see [`DAYBREAK.md`](../DAYBREAK.md). For the code layout, see [`daybreak/README.md`](../daybreak/README.md).

## Setup
```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt   # Pillow, fontTools, pyflakes, pip-audit (pinned)
npm ci --ignore-scripts                            # @rokucommunity/brs + brighterscript (package-lock.json)
cp .env.example .env                               # TV IP, dev password, calendar iCal URL
cp config/family.example.json config/family.json   # your household (gitignored)
```
Node 20 or newer is required. The test runners and the build use `node_modules/.bin`, and fall back to the same versions through `npx` if it's missing.

## Test
| Command | What it covers | Network |
|---|---|---|
| `daybreak/tests/run.sh` | Library: curbside rules (2026 verified, 2027 provisional), dates, moon and showers, iCal with RRULE and EXDATE | No |
| `daybreak/tests/run_data.sh` | `derive()` and every screen against the synthetic feeds in `tests/fixtures/feeds/`, with the clock pinned to Sunday 2026-10-18 10:00 AM | No |
| `daybreak/tests/run_live.sh` | Smoke run against today's real feeds. Fetch them first with `fetch_fixtures.sh` | Yes |
| `.venv/bin/python daybreak/build_channel.py --check` | BrighterScript type and scope check | No |
| `daybreak/preview/preview.sh <dir> --audit` | Renders every screen from the TV code, and flags text under 24 px or below WCAG contrast. Run `build_channel.py --assets` (or a full build) first | No (the radar base map is fetched once) |

Each runner exits non-zero on a failed check, a BrightScript runtime error, or a run that stops before its summary.

**Changing fixtures:** edit `daybreak/tests/make_fixtures.py`, run it, and commit the regenerated `fixtures/feeds/`. CI fails if the committed files don't match the generator.

**Pinning the clock:** tests set `m.testNowUtc` and `m.testNowWall` (see `tests/harness.brs`). `tNowUtc()` and `tNowWall()` return them when set. Nothing on the TV sets them.

**Off-device limits:** `@rokucommunity/brs` doesn't measure text (`boundingRect()` is 0), so `uiWidth` and `uiHeight` fall back to estimates there. It also has no registry, memory monitor or `roUrlTransfer`, so code that uses them must check for `invalid`.

## Design changes
1. Change the builders in `channel/components/screens.brs`, using the grid (`gx`, `gw`) and the type scale in `ui.brs`.
2. Run `daybreak/preview/preview.sh daybreak/out/preview --audit` and look at the PNGs. The audit must report 0 issues.
3. If a screen in the README changed, refresh the screenshots with `--docs docs/images`.

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

## CI and security scanning
| Workflow | When | What |
|---|---|---|
| `ci.yml` → `test` | Every push to `main`, every PR, and called by releases | Version check, fixtures in sync, the three test suites, BrighterScript, pyflakes, the design audit (renders uploaded as `screen-previews`) |
| `ci.yml` → `dependency audit` | Same | `npm audit --audit-level=moderate` and `pip-audit -r requirements-dev.txt` |
| `ci.yml` → `secret scan` | Same | gitleaks over the full git history |
| `codeql.yml` | PRs, `main`, Mondays | CodeQL `security-and-quality` for Python and GitHub Actions |
| `release.yml` | A `v*.*.*` tag | All of CI, then the release (below) |
| Dependabot | Weekly, plus security alerts | Grouped updates for Actions, npm and pip; automatic security PRs |

GitHub secret scanning with push protection, Dependabot alerts and private vulnerability reporting are on for the repository. Actions are pinned to commit SHAs, and Dependabot moves the pins. `main` requires `test`, `dependency audit` and `secret scan` to pass before merging. See [`SECURITY.md`](../SECURITY.md).

## Releases
Versions live in `daybreak/channel/manifest` (major and minor) and `CHANGELOG.md`. On the TV, `build_version` is the git commit count.
1. Work on a branch (`release/<x.y>-<topic>`), add entries under `## [Unreleased]`, and reference issues.
2. Run `python3 scripts/bump_version.py X.Y.Z`. Unreleased becomes `[X.Y.Z] - today`, and the manifest gets `X.Y`.
3. Open a PR that closes the milestone's issues, and merge it once the checks are green.
4. Run `git tag -a vX.Y.Z -m "Daybreak X.Y.Z" && git push origin vX.Y.Z`. `release.yml`:
   - runs all of CI again and runs `bump_version.py --check vX.Y.Z`
   - builds `daybreak-demo-X.Y.Z.zip` (`build_channel.py --demo`: the fictional family, never reads `.env`) with `SHA256SUMS.txt` and a build-provenance attestation (`gh attestation verify <zip> -R roberjo/tv-check`)
   - publishes the release, with the CHANGELOG section as notes
5. Close the milestone, and move its issues to **Done** on the [project board](https://github.com/users/roberjo/projects/2).

## Privacy checklist before pushing
The repo is public. Never commit `.env`, `config/family.json`, `ACTIVITY_LOG.md`, `captures/`, `source/config.brs` or live fixtures; `.gitignore` covers all of them. Use the fictional family in `config/family.example.json` and the synthetic calendar for anything committed, including screenshots.
