# Configuring Daybreak

Daybreak reads two private files at build time. Both are gitignored, and `build_channel.py` bakes them into the package.

| File | Holds |
|---|---|
| `.env` | TV address and dev-installer password, the family calendar's secret iCal URL, `GENTLE_NEWS` |
| `config/family.json` | Household name, members, curbside day, evening apps and, optionally, `place` |

Start from `.env.example` and `config/family.example.json`.

## Members
Each member has a `name` (matched as a whole word in calendar titles), a `color` and a `birthday` (`MM-DD`). Optional fields:
- `allegiance`: a tracked team name, used for "house divided"
- `school` and `grade`: show the member on the School screen
- `activities`: `["Marching band"]` adds the Friday-game note

## Curbside
`"curbside": {"weekday": "Monday"}` is the household's pickup day. The rules themselves (alternating yard and bulky weeks, city holidays) are the City of LaGrange's, in `rules.brs`. Another town needs its own rules there, or `"place": {"curbside": null}` to turn curbside off.

## Place
Without a `place` block, Daybreak uses its LaGrange, Georgia defaults (`placeDefaults()` in `channel/source/lib/rules.brs`). Any top-level key you set replaces the default. `null` turns off `lake`, `college` or `curbside`.

```json
"place": {
  "town": "Athens",
  "region": "GA",
  "area": "Clarke County",
  "seasonRegion": "North Georgia",
  "timezone": "America/New_York",
  "rivalry": ["Georgia", "Falcons"],
  "teams": [
    {"key": "georgia", "name": "Georgia", "short": "UGA", "color": "#BA0C2F", "id": "61", "path": "football/college-football/teams/61"},
    {"key": "falcons", "name": "Falcons", "short": "ATL", "color": "#A71930", "id": "1", "path": "football/nfl/teams/1"}
  ],
  "lake": null,
  "college": null,
  "curbside": null,
  "news": {
    "queries": ["\"Athens\" GA when:2d", "\"Clarke County\" when:3d"],
    "local": "athens|clarke|oconee",
    "ownSource": "Athens Banner-Herald"
  }
}
```

| Key | Used for |
|---|---|
| `town`, `region` | Headers ("Sunday, October 18 · Athens, GA"), "Athens today", the sky title, radar text |
| `area` | NWS alert wording ("Tornado Warning for Clarke County") |
| `seasonRegion` | The Season screen's title |
| `timezone` | Open-Meteo forecast and air-quality times. Should match the TV's own time zone setting |
| `teams` | ESPN team schedules. `path` and `id` come from ESPN's site API URLs, e.g. `site.api.espn.com/apis/site/v2/sports/football/nfl/teams/1/schedule` |
| `rivalry` | Two names from `teams`. A final between them becomes the "house divided" recap, and game day splits the screen |
| `lake` | `{name, site, summerPool, winterPool, lowAlert}`: a USGS gauge site with parameter 00062 (lake elevation, ft) |
| `college` | `{name, short, team, color, ics}`: a college athletics iCal feed whose titles start with `[W]`/`[L]` for results (Sidearm Sports sites) |
| `news` | Google News queries (plain text, which the build URL-encodes), a regex that a headline or source must match to count as local, and the town paper's name (very short headlines from it are section labels) |
| `curbside` | `"lagrange"` (the built-in rules) or `null` |

The build rejects unknown keys, so a typo fails loudly instead of being ignored.

## Still LaGrange-specific
These are content rather than settings, and need code or art changes for another town:
- **Radar map:** the base map, its bounding box and the town labels on it. `scripts/radar_map.py` builds the base map from `CENTER`, and the labels are in `buildRadar()`.
- **Season notes:** the monthly nature and garden notes in `seasonItems()`.
- **Photos:** the Callaway Gardens backgrounds in `daybreak/art/assets/`.

## Settings on the TV
Gentle news, rotation speed and which screens to show can be changed on the TV (OK → Settings) and are saved there. `GENTLE_NEWS=0` in `.env` changes the default.
