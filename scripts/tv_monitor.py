"""Live CPU and memory graphs for the TV, in the terminal.

Roku gives apps no CPU reading, so Daybreak's own diagnostics can only show a
stand-in. The debug console (port 8080) has the real numbers: this polls its
read-only `chanperf` (the dev app's memory and CPU) and `free` (the TV's
memory) and draws rolling graphs. Nothing on the TV changes.

Usage:
  python3 scripts/tv_monitor.py                  # every 5 s until Ctrl-C
  python3 scripts/tv_monitor.py --every 2 --csv tv.csv
  python3 scripts/tv_monitor.py --count 3        # three samples, then stop
"""
import argparse
import csv
import datetime as dt
import pathlib
import re
import socket
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
BARS = " ▁▂▃▄▅▆▇█"
WIDTH = 60  # samples shown per graph


def tv_ip():
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("ROKU_IP="):
                return line.split("=", 1)[1].strip()
    sys.exit("No ROKU_IP in .env")


class Console:
    """One connection to the debug console; commands answered up to the '>' prompt."""

    def __init__(self, ip):
        self.s = socket.create_connection((ip, 8080), timeout=5)
        self.read(3.0)  # banner

    def read(self, wait):
        self.s.settimeout(wait)
        out = b""
        try:
            while chunk := self.s.recv(65536):
                out += chunk
                if out.rstrip().endswith(b">"):
                    break
        except socket.timeout:
            pass
        return out.decode(errors="replace")

    def run(self, cmd):
        self.s.sendall(cmd.encode() + b"\r\n")
        return self.read(8.0)

    def close(self):
        try:
            self.s.sendall(b"exit\r\n")
        finally:
            self.s.close()


def parse_chanperf(text):
    """'channel: mem=29144KiB{...},%cpu=4{user=4,sys=1}' -> (mem MiB, cpu %), or (None, None)."""
    mem = re.search(r"mem=(\d+)KiB", text)
    cpu = re.search(r"%cpu=(\d+)", text)
    if not mem or not cpu:
        return None, None
    return int(mem.group(1)) / 1024, int(cpu.group(1))


def parse_free(text):
    """`free` -> available MB (the last column of the Mem: row), or None."""
    m = re.search(r"^Mem:\s+(.*)$", text, re.M)
    if not m:
        return None
    return int(m.group(1).split()[-1]) / 1024


def spark(values, top=None):
    vals = [v for v in values if v is not None]
    if not vals:
        return ""
    hi = top or max(vals) or 1
    def bar(v):
        if v is None:
            return " "
        i = min(8, round(v / hi * 8))
        return BARS[max(i, 1 if v > 0 else 0)]  # anything above zero shows
    return "".join(bar(v) for v in values[-WIDTH:])


def draw(rows, note):
    cpu = [r["cpu"] for r in rows]
    mem = [r["mem"] for r in rows]
    avail = [r["avail"] for r in rows]
    last = rows[-1]
    fmt = lambda v, unit: "—" if v is None else f"{v:.0f}{unit}"
    lines = [
        f"TV monitor · {last['time']} · every {note}",
        "",
        f"Daybreak CPU      {fmt(last['cpu'], ' %'):>9}  {spark(cpu, 100)}",
        f"Daybreak memory   {fmt(last['mem'], ' MiB'):>9}  {spark(mem)}",
        f"TV memory free    {fmt(last['avail'], ' MB'):>9}  {spark(avail)}",
        "",
    ]
    if last["cpu"] is None:
        lines.append("chanperf has no numbers: Daybreak (the dev app) isn't running.")
    lines.append("Read-only: chanperf and free on the debug console. Ctrl-C to stop.")
    sys.stdout.write("\x1b[H\x1b[2J" + "\n".join(lines) + "\n")
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--every", type=float, default=5.0, help="seconds between samples (default 5)")
    ap.add_argument("--count", type=int, default=0, help="stop after this many samples")
    ap.add_argument("--csv", type=pathlib.Path, help="also append samples to this CSV file")
    args = ap.parse_args()
    con = Console(tv_ip())
    rows = []
    taken = 0
    writer = None
    if args.csv:
        new = not args.csv.exists()
        f = args.csv.open("a", newline="")
        writer = csv.DictWriter(f, fieldnames=["time", "cpu", "mem", "avail"])
        if new:
            writer.writeheader()
    try:
        while True:
            mem, cpu = parse_chanperf(con.run("chanperf"))
            avail = parse_free(con.run("free"))
            row = {"time": dt.datetime.now().strftime("%H:%M:%S"), "cpu": cpu,
                   "mem": None if mem is None else round(mem, 1), "avail": None if avail is None else round(avail, 1)}
            rows = (rows + [row])[-WIDTH:]
            taken += 1
            if writer:
                writer.writerow(row)
                f.flush()
            draw(rows, f"{args.every:g} s")
            if args.count and taken >= args.count:
                break
            time.sleep(args.every)
    except KeyboardInterrupt:
        pass
    finally:
        con.close()


if __name__ == "__main__":
    main()
