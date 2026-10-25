# Changelog

All notable changes to Daybreak. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Work is tracked on the [Daybreak roadmap](https://github.com/users/roberjo/projects/2) project.

## [1.4.0] - 2026-10-25

Remote navigation, settings and the diagnostics screen.

### Added
- **Page dots and a progress line** (app only): dots for the playlist with the current screen's name, and a line along the bottom edge that fills until the next screen (#21).
- **First-run remote hint** on the first three launches (#22).
- **OK menu:** pause or resume, go to a screen, settings, diagnostics. The menu and diagnostics hold the rotation while open (#23).
- **Settings saved on the TV:** gentle news, rotation speed (Normal, Slow, Fast) and per-screen on or off. The gentle-news default comes from `GENTLE_NEWS` (#24).
- **Diagnostics screen** (the * key, or from the menu) (#25):
  - per-source status, age, latency, size and errors, colored by freshness
  - app memory, % of its limit, memory level, low-memory mode, screen element count
  - device, display and network
  - the warm-start cache
  - an on-demand speed test
- `isTrue`/`isFalse` helpers for values that may be missing.

### Changed
- Violent-crime headlines are kept at ingest with a flag and hidden in `derive()` when gentle news is on, so the setting applies without refetching.
- The offline status line moved to the bottom right, clear of the page dots.

## [1.3.0] - 2026-10-25

Design system, screen refresh and previews from the TV code.

### Added
- **Previews from the TV's own code** (`daybreak/preview/`): the screen builders run off-device and dump their SceneGraph tree, and `render.py` draws it with the package's fonts and 9-patch images. `--audit` flags any label under 24 px or below WCAG contrast against what's behind it. CI runs the audit and uploads the renders (#15).
- **Design tokens** in `ui.brs`: a 12-column grid (`gx`, `gw`), a type scale with a 24 px minimum, and named colors (#16).
- **Loading skeleton:** the real date and clock with placeholder cards until data arrives. An offline note says when the saved data is from (#18).
- **Night mode:** from 11 PM to 5 AM the screensaver is a dim, drifting clock with the coming day's forecast and first event (#19).

### Changed
- **Every screen** now sits on the grid, with nothing below 24 px (it used to go down to 15 px) (#16).
- **Briefing** (#17):
  - Game Watch shows the next game of each tracked team plus at most one small-college game, with compact times ("Wed 7:30 PM").
  - Two wider headlines instead of three narrow ones.
  - The bottom row aligns with the cards above it.
  - Heads up is marked by an amber rule.
- **Radar:** the legend, timeline and map labels are 24 px, and a map label that sat under the legend card was removed.
- `docs/images` are rendered from the TV code with synthetic data (#20).

### Removed
- `daybreak/service/` (the Python re-implementation of every screen), `scripts/render_demo.py` and `scripts/contrast_check.py`. The asset sources moved to `daybreak/art/` (#15).

## [1.2.0] - 2026-10-25

Performance, memory and reliability.

### Changed
- **Screens rebuild only when they rotate in or their data changes.** Before, the current screen was rebuilt and crossfaded every minute. The data task now publishes only when the content changes, and relative times are stamped when a screen is built (#7).
- **Radar uses about 17 MB instead of about 100 MB.** It loads 8 frames at 960×540 (scaled up) instead of 12 at 1920×1080. The frames are built once per set of times and reused, so rotating back to radar doesn't download them again (#8).
- **Feeds are reduced to compact forms when they arrive.** Raw ESPN schedules (up to ~360 KB each) and calendar descriptions are no longer held in memory (#10).
- **All due feeds are fetched in parallel** with one 25-second deadline, instead of one after another with 25 seconds each (#11).

### Added
- **Warm start:** the last good data is saved to `cachefs:` and shown immediately on the next launch (#9).
- **Freshness:** each source has a maximum age. Screens show "as of" on older data, and expired alerts show as "Unavailable" instead of "None in effect" (#12).
- **Per-source health** (last success, status, latency, size, failures, last error), published for the diagnostics screen (#13).
- **Low-memory mode:** on a low or critical memory level, or past 80% of the app's limit, radar keeps 4 frames and photo screens use a plain fill (#14).
- `docs/ARCHITECTURE.md`: data flow, source limits, publishing rules and the memory budget.

### Fixed
- Empty or error-page responses no longer reach the JSON parser.
- Calendar and member-name regexes are built once per refresh instead of once per event.

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

[1.4.0]: https://github.com/roberjo/tv-check/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/roberjo/tv-check/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/roberjo/tv-check/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/roberjo/tv-check/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/roberjo/tv-check/releases/tag/v1.0.0
