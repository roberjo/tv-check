# Changelog

All notable changes to Daybreak. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Work is tracked on the [Daybreak roadmap](https://github.com/users/roberjo/projects/2) project.

## [1.1.0] - 2026-10-25

Foundations: CI, deterministic tests, quick fixes and a safe deploy script.

### Added
- **CI** (`.github/workflows/ci.yml`): every push and PR runs the library, data and screen tests, the BrighterScript check and pyflakes. It needs no secrets or private files (#1).
- **Synthetic feed fixtures** (`daybreak/tests/fixtures/feeds/`, made by `make_fixtures.py`): every feed Daybreak fetches, built around a fixed time (Sunday 2026-10-18, 10:00 AM). The tests now check results instead of printing them, and the runners exit non-zero on any failure (#2).
- **`scripts/deploy.py`**: installs the package through the dev installer only when nobody is watching. `--check` runs just the checks. It asks before installing, never prints credentials, and appends an entry to the local activity log (#6).
- **Provisional 2027 curbside holidays**, plus "confirm with the city" notes for weekend shifts and for years the city hasn't published yet (#3).
- **`build_channel.py --check`**: writes an example config and runs BrighterScript, with no `.env` or images needed. Packages now carry `build_version` = the git commit count.

### Fixed
- The Briefing calendar listed the curbside row before earlier events. Rows are now in time order (#4).
- Briefing's Heads up repeated items already shown in its calendar card (#5).
- Multi-day all-day events, including `TV:` board notes, ended after their first day.
- `test_data.brs` crashed when no meteor shower was within 14 days. It's now `test_live.brs`, an optional smoke run on live feeds.

## [1.0.0] - 2026-10-17

The first standalone release: 12 native screens, every feed fetched on the TV, rule-based heads-up insights, the family board through calendar events, and app and screensaver modes.

[1.1.0]: https://github.com/roberjo/tv-check/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/roberjo/tv-check/releases/tag/v1.0.0
