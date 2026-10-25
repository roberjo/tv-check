"""Daybreak versioning: one version, kept in step across the manifest, the
changelog and git tags.

- daybreak/channel/manifest holds major and minor. The patch is the
  release's own; on the TV, build_version is the git commit count, stamped
  by build_channel.py.
- CHANGELOG.md collects changes under "## [Unreleased]" until a release.

Usage:
  python3 scripts/bump_version.py 1.7.0     # Unreleased -> [1.7.0] - today, manifest -> 1.7
  python3 scripts/bump_version.py --check   # manifest and newest CHANGELOG version agree
  python3 scripts/bump_version.py --check v1.7.0   # ...and match this tag (release CI)
  python3 scripts/bump_version.py --notes 1.7.0    # print that version's CHANGELOG section
"""
import datetime as dt
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "daybreak" / "channel" / "manifest"
CHANGELOG = ROOT / "CHANGELOG.md"
REPO = "https://github.com/roberjo/tv-check"
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def manifest_version():
    m = dict(l.split("=", 1) for l in MANIFEST.read_text().splitlines() if "=" in l)
    return int(m["major_version"]), int(m["minor_version"])


def released_versions(text):
    return re.findall(r"^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$", text, re.M)


def section(text, version):
    m = re.search(r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else None


def bump(version):
    if not SEMVER.match(version):
        sys.exit(f"{version}: expected MAJOR.MINOR.PATCH")
    text = CHANGELOG.read_text()
    if version in released_versions(text):
        sys.exit(f"{version} is already in CHANGELOG.md")
    unreleased = section(text, "Unreleased")
    if not unreleased:
        sys.exit("CHANGELOG.md has no entries under ## [Unreleased]")
    prev = released_versions(text)[0]
    today = dt.date.today().isoformat()
    text = text.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{version}] - {today}", 1)
    text = re.sub(r"^\[Unreleased\]: .*$", f"[Unreleased]: {REPO}/compare/v{version}...HEAD", text, flags=re.M)
    link = f"[{version}]: {REPO}/compare/v{prev}...v{version}"
    text = re.sub(r"^(\[" + re.escape(prev) + r"\]: )", link + "\n" + r"\1", text, count=1, flags=re.M)
    CHANGELOG.write_text(text)
    major, minor, _ = SEMVER.match(version).groups()
    lines = MANIFEST.read_text().splitlines()
    lines = [f"major_version={major}" if l.startswith("major_version=") else
             f"minor_version={minor}" if l.startswith("minor_version=") else l for l in lines]
    MANIFEST.write_text("\n".join(lines) + "\n")
    print(f"CHANGELOG.md: Unreleased -> {version} ({today}); manifest -> {major}.{minor}")


def check(tag=None):
    text = CHANGELOG.read_text()
    latest = released_versions(text)[0]
    major, minor, _ = (int(x) for x in latest.split("."))
    problems = []
    if manifest_version() != (major, minor):
        problems.append(f"manifest is {manifest_version()[0]}.{manifest_version()[1]} but CHANGELOG's newest release is {latest}")
    if tag is not None:
        v = tag.lstrip("v")
        if v not in released_versions(text):
            problems.append(f"tag {tag} has no section in CHANGELOG.md")
        elif v != latest:
            problems.append(f"tag {tag} isn't the newest CHANGELOG release ({latest})")
    if problems:
        sys.exit("version check failed:\n  " + "\n  ".join(problems))
    print(f"version check OK: {latest} (manifest {major}.{minor})" + (f", tag {tag}" if tag else ""))


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--check"]:
        check(args[1] if len(args) > 1 else None)
    elif args[:1] == ["--notes"]:
        notes = section(CHANGELOG.read_text(), args[1].lstrip("v"))
        if notes is None:
            sys.exit(f"no CHANGELOG section for {args[1]}")
        print(notes)
    elif len(args) == 1:
        bump(args[0])
    else:
        sys.exit(__doc__)
