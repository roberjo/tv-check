"""Discover UPnP/DIAL/Roku devices on the LAN via SSDP M-SEARCH."""
import socket
import sys

TARGETS = ["ssdp:all", "roku:ecp", "urn:dial-multiscreen-org:service:dial:1"]


def discover(timeout=4.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    sock.settimeout(timeout)
    for st in TARGETS:
        msg = (
            "M-SEARCH * HTTP/1.1\r\n"
            "HOST: 239.255.255.250:1900\r\n"
            'MAN: "ssdp:discover"\r\n'
            "MX: 2\r\n"
            f"ST: {st}\r\n\r\n"
        )
        sock.sendto(msg.encode(), ("239.255.255.250", 1900))
    seen = {}
    try:
        while True:
            data, addr = sock.recvfrom(65507)
            headers = {}
            for line in data.decode(errors="replace").split("\r\n")[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            key = (addr[0], headers.get("st"), headers.get("location"))
            if key not in seen:
                seen[key] = headers
    except socket.timeout:
        pass
    return seen


if __name__ == "__main__":
    for (ip, st, loc), h in sorted(discover(float(sys.argv[1]) if len(sys.argv) > 1 else 4.0).items()):
        print(f"{ip:15} {st}\n    location={loc}\n    server={h.get('server')}")
