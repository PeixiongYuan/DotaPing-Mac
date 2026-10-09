#!/usr/bin/env python3
"""Restore Resources/Sounds from the sources in Resources/asset-sources.json.

Only needed if the sound files are missing; normal builds use the copies in
the repository. Each download must match its recorded SHA-256.
"""
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Resources"

def main():
    manifest = json.loads((ROOT / "asset-sources.json").read_text())
    for item in manifest["files"]:
        destination = ROOT / item["path"]
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == item["sha256"]:
            continue
        for url in item["urls"]:
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "DotaPing-asset-fetch/1.0"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    payload = response.read()
            except OSError as error:
                print(f"{url}: {error}")
                continue
            if hashlib.sha256(payload).hexdigest() == item["sha256"]:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(payload)
                break
            print(f"{url}: checksum mismatch")
        else:
            raise SystemExit(f"Could not fetch {item['path']}")
    print(f"Ready: {len(manifest['files'])} sound files at revision {manifest['soundRevision'][:12]}")

if __name__ == "__main__":
    main()
