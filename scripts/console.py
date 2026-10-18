"""Run commands on the Roku debug console (port 8080) and print the output.

Usage: python3 scripts/console.py <ip> "<cmd>" ["<cmd>" ...]
"""
import socket
import sys

ip, cmds = sys.argv[1], sys.argv[2:]
s = socket.create_connection((ip, 8080), timeout=3)


def drain(t=3.0):
    s.settimeout(t)
    out = b""
    try:
        while c := s.recv(1 << 20):
            out += c
            if out.rstrip().endswith(b">"):
                s.settimeout(0.5)
    except socket.timeout:
        pass
    return out.decode(errors="replace")


drain()
for cmd in cmds:
    s.sendall(cmd.encode() + b"\r\n")
    print(f"##### {cmd}\n{drain(8)}", flush=True)
s.sendall(b"exit\r\n")
s.close()
