# I built a feature to keep the peace in my house. It picked a side on day one.

My family is a house divided: two Auburn fans, two Georgia fans.

So when I spent a Saturday evening building a custom dashboard for our living-room TV with an AI coding assistant, I added a harmless "House Divided" card to track the rivalry.

Its first night with real data happened to be game night. Auburn won 27–24. The TV put it up for the whole room:

**"[The Auburn fans] have bragging rights. [The Georgia fans], there's always next year."**

Peacekeeping feature: shipped. Peace: not kept.

---

**How it started**

I opened an empty folder and asked Claude Code: *what can you learn about my TV over Wi-Fi?*

Within minutes it had:
• found the TV on my network and read its built-in control API
• shown me that even in "limited" mode the TV shares its serial number, MAC addresses, the room it's in, and **which app is open right now**
• found 28 apps we'd never opened, clogging a TV with 36 MB of free storage. It removed them one at a time, after asking, and storage tripled
• flagged automatic content recognition (ACR), which fingerprints what's on screen for ad targeting. We turned it off

Then it wrote and installed a small diagnostic app to measure what the network API can't see: 4K and HDR capability, DRM level, codecs, and real network throughput.

**Where it went**

By midnight the TV was running "Daybreak," a standalone app that knows our town and our family:
• **City of LaGrange garbage schedule,** with alternating yard-waste weeks and holiday shifts, verified against all 53 weeks of the city's flyer
• **West Point Lake level** from the USGS gauge, plus a "best lake day" pick
• **Live NOAA radar,** National Weather Service alerts and the local forecast
• **Our family calendar:** deadlines, schedule overlaps, and notes posted just by adding a calendar event called "TV: …"
• **Scores and schedules** for every team in the house, plus LaGrange College athletics
• **Tonight's sky:** moon phase and meteor showers

**What I took away professionally**

1. **Guardrails make AI collaboration productive, not slower.** I set two rules: keep an activity log of everything you do and why, and ask before anything irreversible. It followed both, including logging its own failures.

2. **Real data finds real bugs.** The best catches came from live feeds, not the mockups: a rivalry game I hadn't planned for, a calendar change made mid-session, a news filter the family room needed.

3. **Make it visible first, then make it right.** Rendering screens on a laptop made the design loop fast. Rewriting natively for the TV came after the design was settled. Off-device tests then caught a pile of language-specific footguns before the TV ever saw the code.

4. **Measure quality instead of eyeballing it.** "Make sure the text is readable over the photo" turned into a WCAG contrast check against the brightest pixels behind every line, and the first version failed it.

5. **Knowing what *not* to build matters.** When I asked about decompiling a streaming app, the answer was no: DRM circumvention is a legal line. It suggested a legitimate alternative.

6. **Specific beats generic.** Nobody gets excited about a weather widget. Everybody notices when the TV knows it's yard-waste week.

The first install crashed because the app didn't know what city it lived in. The second ran clean. The rivalry card has not been removed, despite multiple requests from the Georgia side of the house.

Code, screenshots (with a fictional family) and the full write-up are on GitHub: **tv-check**.

#AI #SoftwareEngineering #ClaudeCode #Roku #SmartHome #BuildInPublic #DeveloperExperience
