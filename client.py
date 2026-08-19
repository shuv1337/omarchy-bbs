#!/usr/bin/env python3
"""Enroll an Omarchy device and open a short-lived authenticated BBS session."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy-bbs"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-bbs"
DEVICE_FILE = STATE_DIR / "device.json"
CONFIG_FILE = CONFIG_DIR / "config.json"


def omarchy_version() -> str:
    if not Path("/usr/share/omarchy").is_dir():
        raise SystemExit("Omarchy was not detected at /usr/share/omarchy")
    try:
        result = subprocess.run(
            ["omarchy", "version"], check=True, capture_output=True, text=True, timeout=5
        )
    except (FileNotFoundError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"Could not verify Omarchy: {exc}") from exc
    version = result.stdout.strip()
    if not version:
        raise SystemExit("The Omarchy version command returned no version")
    return version


def server_url() -> str:
    env_url = os.environ.get("OMARCHY_BBS_URL")
    if env_url:
        return env_url.rstrip("/")
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())["server_url"].rstrip("/")
    return "http://127.0.0.1:8787"


def request_json(url: str, payload: dict) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            message = json.load(exc)["error"]
        except Exception:
            message = exc.reason
        raise SystemExit(f"BBS refused the request: {message}") from exc


def enroll(args: argparse.Namespace) -> None:
    version = omarchy_version()
    payload = request_json(
        f"{server_url()}/api/enroll",
        {"invite": args.invite, "handle": args.handle, "omarchy_version": version},
    )
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DEVICE_FILE.write_text(json.dumps(payload, indent=2) + "\n")
    os.chmod(DEVICE_FILE, 0o600)
    print(f"Enrolled @{payload['handle']} on {server_url()}")


def login_url() -> str:
    omarchy_version()
    if not DEVICE_FILE.exists():
        raise SystemExit("This device is not enrolled. Run client.py enroll HANDLE INVITE_CODE")
    device = json.loads(DEVICE_FILE.read_text())
    timestamp = str(int(time.time()))
    nonce = secrets.token_urlsafe(12)
    message = f"{device['device_id']}.{timestamp}.{nonce}".encode()
    signature = hmac.new(bytes.fromhex(device["secret"]), message, hashlib.sha256).hexdigest()
    query = urllib.parse.urlencode(
        {"device": device["device_id"], "ts": timestamp, "nonce": nonce, "sig": signature}
    )
    return f"{server_url()}/auth?{query}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    enroll_parser = sub.add_parser("enroll", help="enroll this Omarchy device")
    enroll_parser.add_argument("handle")
    enroll_parser.add_argument("invite")
    sub.add_parser("open", help="open an authenticated BBS session")
    sub.add_parser("url", help="print an authenticated URL without opening it")
    args = parser.parse_args()
    if args.command == "enroll":
        enroll(args)
    elif args.command == "url":
        print(login_url())
    else:
        url = login_url()
        if not webbrowser.open(url):
            print(url)


if __name__ == "__main__":
    main()
