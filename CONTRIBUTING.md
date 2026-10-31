# Contributing

Thanks for your interest! Daybreak is a small family project, but fixes and ports to other towns are welcome.

## Setup
```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
npm ci --ignore-scripts                       # BrightScript emulator + BrighterScript, locked versions
cp .env.example .env
cp config/family.example.json config/family.json
```

## Before opening a PR
```sh
daybreak/tests/run.sh && daybreak/tests/run_data.sh        # off-device tests (no network)
.venv/bin/python daybreak/build_channel.py --check          # BrighterScript
.venv/bin/python daybreak/build_channel.py --assets && daybreak/preview/preview.sh daybreak/out/preview --audit
.venv/bin/pyflakes scripts daybreak/build_channel.py daybreak/tests daybreak/art daybreak/preview daybreak/wallpapers
```
CI runs all of these, plus the dependency audit, the secret scan and CodeQL. `main` is protected, so changes land through PRs with green checks.

## Guidelines
- **One branch per change**, with commits that say why. Reference issues (`Closes #12`).
- **Add a line under `## [Unreleased]` in `CHANGELOG.md`** for anything user-visible.
- **Tests:** add checks for new behavior in `daybreak/tests/`. Feeds come from `make_fixtures.py`: change the generator, rerun it, and commit the output.
- **Screens:** use the grid and type scale in `ui.brs`, keep text at 24 px or larger, and pass the design audit.
- **Code style:** match the surrounding code (BrightScript style, comment density). Scripts in `scripts/` use the Python standard library only.
- **Privacy:** never commit real household data. Use the fictional family and the synthetic calendar for tests, screenshots and docs. Install the pre-commit privacy scan once with `sh scripts/install_hooks.sh`. It reads your values from the gitignored `config/family.json`, `.env` and `captures/`, and blocks a commit that adds a family name, birthday, school, calendar URL, token or TV identifier. It prints only the kind of finding, never the value. CI runs the same scan with the public patterns only (`--all`). Known public coincidences go in `.pii-allow`, listed by file and kind.
- **Your TV:** tests and previews run off-device. If you install on a TV, do it when nobody is watching (`scripts/deploy.py` checks).

## Releases (maintainers)
1. Run `python3 scripts/bump_version.py X.Y.Z` on the release branch: Unreleased becomes the version, and the manifest is updated.
2. Merge the PR once CI is green.
3. Run `git tag -a vX.Y.Z -m "Daybreak X.Y.Z" && git push origin vX.Y.Z`. The Release workflow:
   - checks everything again and verifies the tag
   - builds the demo package with checksums and provenance
   - publishes the GitHub release with the changelog section as notes

More detail is in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
