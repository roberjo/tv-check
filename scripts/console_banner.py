"""Connect to Roku debug console ports and print whatever they send unprompted.

Usage: python3 scripts/console_banner.py <ip> [port ...] [--help]
With --help, also sends "help" (read-only) to port 8080 only.
"""
import socket
import sys

args = [a for a in sys.argv[1:] if a != "--help"]
ip, ports = args[0], [int(p) for p in args[1:]] or [8080, 8085, 8086, 8087, 8089, 9080]


def read_all(s, wait=2.0):
    s.settimeout(wait)
    out = b""
    try:
        while chunk := s.recv(65536):
            out += chunk
    except socket.timeout:
        pass
    return out.decode(errors="replace")


for port in ports:
    print(f"===== {port}")
    try:
        with socket.create_connection((ip, port), timeout=3) as s:
            print(read_all(s) or "(no banner)")
            if port == 8080 and "--help" in sys.argv:
                s.sendall(b"help\r\n")
                print(read_all(s, 3))
    except OSError as e:
        print(f"error: {e}")
