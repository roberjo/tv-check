"""Sample TV health over time (read-only): RAM via console `free`, UI fps,
active app, player state, volume, and network RTT. Writes CSV.

Usage: python3 scripts/sample_health.py <ip> <seconds> <interval> <out.csv>
"""
import csv
import re
import socket
import subprocess
import sys
import time
import urllib.request

ip, duration, interval, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]


def ecp(path):
    with urllib.request.urlopen(f"http://{ip}:8060/{path}", timeout=5) as r:
        return r.read().decode(errors="replace")


def tag(xml, pattern):
    m = re.search(pattern, xml, re.S)
    return m.group(1) if m else ""


class Console:
    def __init__(self):
        self.s = socket.create_connection((ip, 8080), timeout=3)
        self.drain()

    def drain(self, t=1.5):
        self.s.settimeout(t)
        out = b""
        try:
            while not out.rstrip().endswith(b">"):
                c = self.s.recv(65536)
                if not c:
                    break
                out += c
        except socket.timeout:
            pass
        return out.decode(errors="replace")

    def run(self, cmd):
        self.s.sendall(cmd.encode() + b"\r\n")
        return self.drain(4)


def rtt_ms():
    r = subprocess.run(["ping", "-c", "3", "-i", "0.2", "-t", "3", ip], capture_output=True, text=True)
    m = re.search(r"= ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+) ms", r.stdout)
    return (m.group(2), m.group(3)) if m else ("", "")


con = Console()
fields = ["t", "mem_used_kb", "mem_avail_kb", "buff_cache_kb", "swap_used_kb", "fps",
          "active_app", "player_state", "position", "duration", "video", "audio", "video_res", "video_fr",
          "bitrate", "buffering",
          "volume", "muted", "rtt_avg_ms", "rtt_max_ms"]
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fields)
    w.writeheader()
    end = time.time() + duration
    while time.time() < end:
        t0 = time.time()
        row = {"t": time.strftime("%H:%M:%S")}
        free = con.run("free")
        m = re.search(r"Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)", free)
        sw = re.search(r"Swap:\s+(\d+)\s+(\d+)", free)
        if m:
            row.update(mem_used_kb=m.group(2), buff_cache_kb=m.group(5), mem_avail_kb=m.group(6))
        if sw:
            row["swap_used_kb"] = sw.group(2)
        row["fps"] = tag(ecp("query/graphics-frame-rate"), r"<fps>([^<]+)")
        row["active_app"] = tag(ecp("query/active-app"), r"<app[^>]*>([^<]+)")
        mp = ecp("query/media-player")
        row.update(player_state=tag(mp, r'state="([^"]+)"'), position=tag(mp, r"<position>([^<]+)"),
                   duration=tag(mp, r"<duration>([^<]+)"), video=tag(mp, r'video="([^"]+)"'),
                   audio=tag(mp, r'audio="([^"]+)"'), video_res=tag(mp, r'video_res="([^"]+)"'),
                   video_fr=tag(mp, r'video_fr="([^"]+)"'), buffering=tag(mp, r"<buffering ([^/]+)/>"),
                   bitrate=tag(mp, r"<stream_bitrate>([^<]+)") or tag(mp, r'bitrate="([^"]+)"'))
        ad = ecp("query/audio-device")
        row.update(volume=tag(ad, r"<global>.*?<volume>(\d+)"), muted=tag(ad, r"<global>.*?<muted>(\w+)"))
        row["rtt_avg_ms"], row["rtt_max_ms"] = rtt_ms()
        w.writerow(row)
        f.flush()
        time.sleep(max(0, interval - (time.time() - t0)))
