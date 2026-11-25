"""Refresh Seek's config from the container's Wyrwood binding."""

import http.client
import json
import os
from pathlib import Path
import socket
import time


class WyrwoodConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect("/run/wyrwood/vault.sock")


def fetch():
    connection = WyrwoodConnection("wyrwood", timeout=10)
    try:
        connection.request("GET", "/v1/kv/data/homelab/seek")
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError(f"OpenBao returned HTTP {response.status}")
        secret = json.load(response)["data"]["data"]
        if not secret.get("SEEK_SERVER_TOKEN", "").strip():
            raise ValueError("missing client token")
        return json.dumps(secret) + "\n"
    finally:
        connection.close()


def main():
    os.umask(0o077)
    config = Path("/config/seek/config.json")
    config.parent.mkdir(exist_ok=True)
    while True:
        try:
            secret = fetch()
            pending = config.with_suffix(".tmp")
            pending.write_text(secret)
            pending.replace(config)
        except RuntimeError as error:
            print(f"seek-secrets: {error}", flush=True)
        except (OSError, http.client.HTTPException, AttributeError, KeyError, TypeError, ValueError):
            print("seek-secrets: could not load Seek configuration", flush=True)
        time.sleep(30)


if __name__ == "__main__":
    main()
