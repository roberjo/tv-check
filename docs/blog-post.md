# My TV Picked a Side in Our House Divided

*How a lazy Saturday question ("what can an AI learn about my TV over Wi-Fi?") turned into a standalone Roku app, written in one evening with Claude Code.*

---

Our house is split down the middle: two Auburn fans and two Georgia fans. In Georgia that isn't a sports preference; it's a family structure. So when I was building a dashboard for our living-room TV, I added what seemed like a harmless feature: a "House Divided" card that tracks the rivalry and shows the latest result.

The first time the app rendered with real data was the night of the game. Auburn won, 27–24, in Athens.

The TV calmly put this up for the whole room:

> **Auburn 27 · Georgia 24**
> *[The Auburn fans] have bragging rights. [The Georgia fans], there's always next year.*

I wrote a feature to keep the peace. It started a family argument on its first night. That's how I knew it was working.

![Game recap screen](images/recap.jpg)
*(Screenshots throughout use a fictional family. The rivalry score is real, unfortunately for half my house.)*

## It started as a curiosity

I opened an empty folder and asked Claude Code something vague: *"I want this directory to be a project for exploring connecting to my TCL 65-inch TV over Wi-Fi and figuring out what Claude can learn from its interfaces."*

About thirty seconds later it had found two Roku TVs on my network with an SSDP broadcast, worked out which one was the 65-inch TCL, and started reading the TV's **External Control Protocol (ECP)**, Roku's built-in HTTP API on port 8060.

Even locked down in "Limited" mode, my TV happily told anyone on the network:
- its serial number, MAC addresses, and the name of my Wi-Fi network
- the room it's in ("Living room")
- **which app was open right then** (Spectrum TV, if you're wondering)

Once I flipped "Control by mobile apps" to Enabled and turned on developer mode, it gave up a lot more: every installed app, the media player's state, the volume, and a telnet debug console with a `plugins` command. That command listed all ~130 packages on the TV, each with a usage counter.

That counter turned out to be **embarrassing**. Netflix: 175. Spectrum: 25. Then 28 apps we had never opened once, sitting on a TV with **36 MB of free storage**, where Roku was already evicting the apps we *do* use. Claude asked which groups to remove, warned me that removal also takes apps off the Roku account, and cleared them one at a time over the network. Free storage tripled to 107 MB.

The TV also revealed something less funny: **ACR** ("automatic content recognition") packages, the feature that fingerprints what's on screen, including from HDMI devices, for ad targeting. We turned that off.

## A diagnostic app that the AI wrote and installed

Roku doesn't expose CPU, video mode, link speed or DRM level over the network. So Claude wrote a small diagnostic app in BrightScript, sideloaded it, read the results from the developer console, and pressed Home when it was done. The results:
- **Ethernet** at about 85 Mbps, consistent with a 100 Mbps port and plenty for 4K
- **Widevine L1 and PlayReady SL3000**, so streaming services will serve full 4K HDR
- HEVC Main 10 and VP9 Profile 2, but **no AV1**, which is why YouTube falls back to VP9
- about 325 MB of RAM free during 4K playback, so it's tight

It also caught its own bug. The first codec check said the TV couldn't decode *anything*. Claude noticed that couldn't be true for a 4K Dolby Vision TV, re-ran the query with the full response, found the TV expects the profile name `"main 10"` (with a space), and fixed it.

## Then it got ambitious: Daybreak

The question changed from "what can it learn?" to "what could the TV *do* for us?" That became **Daybreak**, a dashboard and screensaver that knows our town and our family.

![Morning briefing](images/briefing.jpg)

The specificity makes it feel personal:
- **Garbage day.** The City of LaGrange alternates yard-waste and bulky-trash weeks, and city holidays push pickup back a day. Claude found the city's 2026 schedule flyer, encoded the rule, **verified it against all 53 weeks**, and the TV now says *"Monday: garbage + yard waste. No grass clippings."* (Holiday handling came from a correction from me: I told it holidays shift pickup to the next day.)
- **West Point Lake.** It reads the live USGS gauge (625.2 ft that night, 2.8 ft below winter pool) and flags low water before you haul the boat out.
- **Radar.** NOAA radar frames over a dark map built from public USGS layers, with a 25-mile ring around town.
- **LaGrange College athletics.** Straight from the college's own calendar feed, including final scores.
- **Our family calendar.** Deadlines, overlaps, and anything titled `TV: Dinner at 6:30` shows up as a note on the TV.
- **Tonight's sky.** The moon drawn at its real phase, plus the Orionids, which peaked that week.

![The week ahead](images/week.jpg)

At one point I asked whether we could decompile the Spectrum app and build our own player. Claude said no and explained why: the streams are DRM-protected and tied to Spectrum's sign-in, and getting around that runs into anti-circumvention law. Then it suggested a legitimate alternative. I appreciated that.

## What the build was actually like

A few moments stuck with me.

**It measured readability instead of guessing.** When I asked for photos of Callaway Gardens behind the text and said "make sure it's readable," it wrote a script that computes WCAG contrast against the brightest pixels behind every line of text. The first attempt failed at 4.0:1 on the small captions, so it darkened the photo until every line passed.

![Ambient screensaver](images/ambient.jpg)

**It tested on real data and found real problems.** On its first pass through live feeds it learned that:
- Auburn and Georgia had played each other that day, which my mockups hadn't anticipated.
- Someone in the family had just ended a weekly practice series in our shared calendar, and the reader handled the change correctly.
- One news feed was surfacing a violent-crime story, so it added a "gentle news" filter for the living-room screen and told me it had done so.

**Going standalone was the right call, and also humbling.** The first version had the Mac draw every screen and the TV just display images. When I asked, "why do we need the Mac?", Claude agreed it could all run on the TV and rewrote it natively in BrightScript. It ran the code off-device with a BrightScript interpreter, using a synthetic calendar and saved copies of the live feeds, which caught a wonderful collection of footguns:
- I named a parameter `m`. That's BrightScript's reserved "this."
- A variable named `sub` and a function named `run`: both reserved.
- The iCal rule key `COUNT` collided with the dictionary's built-in `.Count()` method.
- The USGS lake gauge publishes elevation as parameter `00062`, not `62614`.

**Then the TV crashed anyway**, because the app didn't know what city it lived in. One field (`city`) never made it from the data task to the screen, so the big clock screen tried to print "nothing" and halted. The fix went in with a lesson: every screen build is now wrapped in try/catch, so one bad screen gets skipped instead of freezing the screensaver.

The second install cycled through all eleven screens on the real TV without an error.

![Live radar](images/radar.jpg)

## Things I'd tell a friend
- **Your smart TV is chattier than you think.** If "Control by mobile apps" is Enabled, anyone on your Wi-Fi can see what you're watching and control the TV. Leave it on Limited unless you have a reason.
- **"Build it so I can see it" beats "build it right the first time."** Rendering the screens on the Mac first made the design loop fast. Going native came after the design was settled.
- **AI pair-programming works best with guardrails.** I asked for an activity log of everything it did and why, and it kept one, including failures and the time it interrupted a live show because I told it to "do it now." It asked before anything irreversible: removing apps, installing, sending commands to the TV.
- **The details make it feel personal.** Nobody gets excited about a weather widget. Everybody notices when the TV knows it's yard-waste week.

## Try it
The code is on GitHub: **tv-check**. It includes the exploration scripts, the diagnostic app, Daybreak's source, off-device tests, and design notes. Everything personal stays in gitignored config. The screenshots use the fictional Parker family, whose fake calendar is much calmer than ours.

The House Divided card is still on the TV, and the rivalry is tied 1–1 in arguments about whether it should be.
