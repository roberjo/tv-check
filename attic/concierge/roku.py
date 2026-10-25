"""Roku ECP client used by the concierge. Every TV action goes through here so
the safety limits (key allowlist, volume caps) are enforced in one place."""
import re
import time
import urllib.error
import urllib.parse
import urllib.request

# Keys the concierge may press. Anything else (e.g. purchase-flow shortcuts) is refused.
ALLOWED_KEYS = {
    "Home", "Back", "Select", "Up", "Down", "Left", "Right", "Play", "Rev", "Fwd",
    "InstantReplay", "Info", "Search", "Enter", "Backspace",
    "VolumeUp", "VolumeDown", "VolumeMute", "PowerOn", "PowerOff",
    "ChannelUp", "ChannelDown", "InputTuner", "InputHDMI1", "InputHDMI2",
    "InputHDMI3", "InputHDMI4", "InputAV1",
}
MAX_KEYS_PER_CALL = 25


def _tag(xml, pattern):
    m = re.search(pattern, xml, re.S)
    return m.group(1) if m else None


class Roku:
    def __init__(self, ip, max_volume=40, night_max_volume=15, night_hours=(22, 7)):
        self.base = f"http://{ip}:8060"
        self.max_volume = max_volume
        self.night_max_volume = night_max_volume
        self.night_hours = night_hours

    # --- transport -------------------------------------------------------
    def _get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as r:
            return r.read().decode(errors="replace")

    def _post(self, path):
        req = urllib.request.Request(self.base + path, data=b"", method="POST")
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status

    # --- reads -----------------------------------------------------------
    def apps(self):
        xml = self._get("/query/apps")
        return [{"id": i, "type": t, "name": n.replace("&amp;", "&")}
                for i, t, n in re.findall(r'<app id="([^"]+)" type="([^"]+)"[^>]*>([^<]+)</app>', xml)]

    def volume(self):
        xml = self._get("/query/audio-device")
        vol = _tag(xml, r"<global>.*?<volume>(\d+)</volume>")
        muted = _tag(xml, r"<global>.*?<muted>(\w+)</muted>")
        return (int(vol) if vol else None), muted == "true"

    def state(self):
        info = self._get("/query/device-info")
        app_xml = self._get("/query/active-app")
        mp = self._get("/query/media-player")
        vol, muted = self.volume()
        app = re.search(r'<app id="([^"]+)"[^>]*>([^<]+)</app>', app_xml)
        return {
            "power_mode": _tag(info, r"<power-mode>([^<]+)"),
            "active_app": {"id": app.group(1), "name": app.group(2)} if app else None,
            "player_state": _tag(mp, r'<player state="([^"]+)"'),
            "player_app": _tag(mp, r'<plugin id="[^"]*" name="([^"]+)"'),
            "position_ms": _tag(mp, r"<position>(\d+)"),
            "duration_ms": _tag(mp, r"<duration>(\d+)"),
            "video_format": _tag(mp, r'video="([^"]+)"'),
            "volume": vol,
            "muted": muted,
            "volume_cap_now": self.volume_cap(),
        }

    # --- safety ----------------------------------------------------------
    def volume_cap(self):
        hour = time.localtime().tm_hour
        start, end = self.night_hours
        night = hour >= start or hour < end
        return self.night_max_volume if night else self.max_volume

    # --- actions ---------------------------------------------------------
    def launch(self, app_id, content_id=None, media_type=None):
        params = {}
        if content_id:
            params["contentId"] = content_id
        if media_type:
            params["mediaType"] = media_type
        qs = ("?" + urllib.parse.urlencode(params)) if params else ""
        self._post(f"/launch/{urllib.parse.quote(str(app_id))}{qs}")
        return f"launched app {app_id}" + (f" with content {content_id}" if content_id else "")

    def search(self, keyword, type_=None, provider_id=None, launch=False, season=None):
        params = {"keyword": keyword}
        if type_:
            params["type"] = type_
        if provider_id:
            params["provider-id"] = provider_id
        if season:
            params["season"] = str(season)
        if launch:
            params["launch"] = "true"
        self._post("/search/browse?" + urllib.parse.urlencode(params))
        return f"opened Roku search for {keyword!r}" + (" and asked it to launch the best match" if launch else "")

    def press(self, keys):
        if len(keys) > MAX_KEYS_PER_CALL:
            raise ValueError(f"at most {MAX_KEYS_PER_CALL} keys per call")
        bad = [k for k in keys if k not in ALLOWED_KEYS]
        if bad:
            raise ValueError(f"keys not allowed: {bad}")
        pressed = []
        for k in keys:
            if k == "VolumeUp":
                vol, _ = self.volume()
                if vol is not None and vol >= self.volume_cap():
                    return f"pressed {pressed}; stopped at VolumeUp because volume {vol} is at the cap {self.volume_cap()}"
            self._post(f"/keypress/{k}")
            pressed.append(k)
            time.sleep(0.15)
        return f"pressed {pressed}"

    def type_text(self, text):
        for ch in text[:100]:
            self._post("/keypress/Lit_" + urllib.parse.quote(ch, safe=""))
            time.sleep(0.05)
        return f"typed {text[:100]!r}"

    def set_volume(self, level):
        cap = self.volume_cap()
        target = max(0, min(int(level), cap))
        for _ in range(60):
            vol, _ = self.volume()
            if vol is None or vol == target:
                break
            self._post("/keypress/" + ("VolumeUp" if vol < target else "VolumeDown"))
            time.sleep(0.12)
        vol, muted = self.volume()
        note = f" (requested {level}, capped at {cap})" if int(level) > cap else ""
        return f"volume is now {vol}{' (muted)' if muted else ''}{note}"
