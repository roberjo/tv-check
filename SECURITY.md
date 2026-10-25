# Security

## Reporting a vulnerability
Please report security problems privately through GitHub: **Security → Report a vulnerability** on this repository. Don't open a public issue. You'll get a reply within a week. Fixes are released as a patch version and noted in `CHANGELOG.md`.

## Supported versions
Only the latest release gets fixes. Daybreak is sideloaded, so update by building and installing the newest tag.

## Scope
| In scope | Notes |
|---|---|
| The Daybreak channel (`daybreak/channel/`) | Parsing of remote feeds (JSON, iCal, RSS, WMS), anything that could crash the app or run unexpected code |
| Scripts (`scripts/`, `daybreak/*.py`) | Especially `deploy.py`, which handles the dev-installer password |
| CI and release workflows (`.github/`) | Permissions, pinned actions, supply chain |
| Accidental exposure of private data in the repo or release packages | See below |

Out of scope:
- **Roku OS itself and its LAN interfaces.** ECP, the dev installer and the debug consoles are Roku's; `FINDINGS.md` documents what they expose. Report OS problems to Roku.
- **The third-party feeds.**
- **The shelved code in `attic/`.**

## How the project protects things
- **Private data stays out of git.** `.env` (TV password, the calendar's secret iCal URL), `config/family.json`, `ACTIVITY_LOG.md`, `captures/` and the generated `source/config.brs` are gitignored.
- **Public release packages** are built with `--demo`, which never reads `.env` or `family.json`. They carry the fictional family and no calendar URL.
- **Your own package is private.** It embeds your calendar URL, so don't share it.
- **On the TV:** Daybreak's warm-start cache (`cachefs:`) and settings (registry) stay on the device. The cache holds parsed calendar events without descriptions.
- **Scanning on every push and PR:**
  - gitleaks secret scanning of the full history, plus GitHub secret scanning with push protection
  - CodeQL for Python and GitHub Actions (also weekly)
  - `npm audit` and `pip-audit` on the locked dev tools
  - Dependabot alerts, security updates and weekly version updates (Actions, npm, pip)
- **Supply chain:** workflows pin every action to a commit SHA, run with read-only permissions by default, and release builds carry a build-provenance attestation and SHA-256 checksums.
- **Wallpapers:** the TV downloads photos from this repo's protected `main` branch, from `place.wallpapers`.
  - **Validation:** catalog ids and paths are checked (`[a-z0-9-]` ids, `img/<id>.jpg` files, at most 100), so a bad catalog can't name files outside `cachefs:/wp-*`.
  - **Downloads:** a download is kept only if it arrives whole. The photos are plain JPEGs, decoded by Roku OS.
- **Developer mode** and "Control by mobile apps" open the TV to the local network. Only use them on a network you trust (see the README).
