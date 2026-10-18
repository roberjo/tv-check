"""TCP connect scan of ports commonly exposed by smart TVs / Roku devices."""
import socket
import sys
from concurrent.futures import ThreadPoolExecutor

PORTS = {
    80: "http (dev installer when dev mode on)", 443: "https", 1900: "ssdp",
    5555: "adb", 7000: "airplay", 7001: "airplay", 7100: "airplay mirror",
    8008: "cast", 8009: "cast tls", 8060: "roku ecp", 8061: "roku ecp?",
    8080: "http-alt", 8085: "debug: plugin", 8086: "debug", 8087: "debug",
    8089: "debug", 8443: "https-alt", 9080: "roku?", 9092: "roku?",
    49152: "upnp", 49153: "upnp", 6466: "androidtv remote", 6467: "androidtv pair",
    5000: "upnp/airplay", 7250: "miracast", 554: "rtsp", 22: "ssh", 23: "telnet",
}


def check(ip, port):
    s = socket.socket()
    s.settimeout(1.0)
    try:
        return port, s.connect_ex((ip, port)) == 0
    finally:
        s.close()


if __name__ == "__main__":
    ip = sys.argv[1]
    with ThreadPoolExecutor(32) as ex:
        for port, is_open in sorted(ex.map(lambda p: check(ip, p), PORTS)):
            if is_open:
                print(f"open  {port:>5}  {PORTS[port]}")
