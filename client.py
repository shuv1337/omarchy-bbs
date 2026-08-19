#!/usr/bin/env python3
"""Automatically register an Omarchy device and open an authenticated BBS session."""

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
import base64
import re
import tomllib

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy-bbs"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-bbs"
DEVICE_FILE = STATE_DIR / "device.json"
CONFIG_FILE = CONFIG_DIR / "config.json"
STATUS_FILE = STATE_DIR / "status.json"
PLUGIN_DIR = Path(__file__).resolve().parent
THEME_FILE = Path.home() / ".local/state/omarchy/current/theme/colors.toml"


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
    return "https://bbs.thoughtlesslabs.com"


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
    except urllib.error.URLError as exc:
        raise SystemExit(f"Could not reach the BBS: {exc.reason}") from exc


def auto_enroll() -> dict:
    version = omarchy_version()
    device_id = secrets.token_urlsafe(18)
    secret = secrets.token_hex(32)
    handle = f"omarchist-{hashlib.sha256(device_id.encode()).hexdigest()[:8]}"
    payload = request_json(
        f"{server_url()}/api/register",
        {
            "device_id": device_id,
            "secret": secret,
            "handle": handle,
            "omarchy_version": version,
        },
    )
    device = {
        "device_id": device_id,
        "secret": secret,
        "handle": payload["handle"],
        "server_url": server_url(),
    }
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DEVICE_FILE.write_text(json.dumps(device, indent=2) + "\n")
    os.chmod(DEVICE_FILE, 0o600)
    return device


def signed_fields(device: dict, purpose: str) -> dict:
    timestamp = str(int(time.time()))
    nonce = secrets.token_urlsafe(12)
    message = f"{device['device_id']}.{timestamp}.{nonce}.{purpose}".encode()
    signature = hmac.new(bytes.fromhex(device["secret"]), message, hashlib.sha256).hexdigest()
    return {"device": device["device_id"], "ts": timestamp, "nonce": nonce, "sig": signature}


def theme_token() -> str:
    defaults = {"bg": "#0c0f0d", "panel": "#151a16", "ink": "#e8f3e9", "muted": "#8fa091", "hot": "#a7f3a0", "amber": "#f6c177"}
    try:
        colors = tomllib.loads(THEME_FILE.read_text())
        mapped = {
            "bg": colors.get("background"),
            "panel": colors.get("lighter_background"),
            "ink": colors.get("foreground"),
            "muted": colors.get("dark_foreground"),
            "hot": colors.get("accent"),
            "amber": colors.get("yellow"),
        }
        if all(isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value) for value in mapped.values()):
            defaults = mapped
    except (OSError, tomllib.TOMLDecodeError):
        pass
    encoded = base64.urlsafe_b64encode(json.dumps(defaults, separators=(",", ":"), sort_keys=True).encode())
    return encoded.decode().rstrip("=")


def device() -> dict:
    omarchy_version()
    record = json.loads(DEVICE_FILE.read_text()) if DEVICE_FILE.exists() else None
    if not record or record.get("server_url") != server_url():
        record = auto_enroll()
        notify("Omarchy BBS", "This device is linked. Welcome to the board.")
    return record


def login_url(path: str = "/") -> str:
    if path not in ("/", "/new"):
        raise SystemExit("Unsupported BBS destination")
    record = device()
    theme = theme_token()
    fields = signed_fields(record, f"login:{path}:{theme}")
    fields["next"] = path
    fields["theme"] = theme
    query = urllib.parse.urlencode(fields)
    return f"{server_url()}/auth?{query}"


def notify(title: str, message: str) -> None:
    try:
        subprocess.run(
            ["omarchy", "notification", "send", "--exec", str(PLUGIN_DIR / "bin/omarchy-bbs"), title, message],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        pass


def check_status(should_notify: bool) -> None:
    record = device()
    payload = signed_fields(record, "status")
    status = request_json(f"{server_url()}/api/status", payload)
    previous = json.loads(STATUS_FILE.read_text()) if STATUS_FILE.exists() else {"unread": 0}
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATUS_FILE.write_text(json.dumps(status, indent=2) + "\n")
    os.chmod(STATUS_FILE, 0o600)
    if should_notify and status.get("unread", 0) > previous.get("unread", 0):
        notify("Omarchy BBS", f"{status['unread']} new transmission{'s' if status['unread'] != 1 else ''}.")
    print(json.dumps(status))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("open", help="open an authenticated BBS session")
    new_parser = sub.add_parser("new", help="open the new-transmission form")
    status_parser = sub.add_parser("status", help="check for new BBS activity")
    status_parser.add_argument("--notify", action="store_true")
    sub.add_parser("url", help="print an authenticated URL without opening it")
    args = parser.parse_args()
    if args.command == "url":
        print(login_url())
    elif args.command == "status":
        check_status(args.notify)
    else:
        url = login_url("/new" if args.command == "new" else "/")
        if not webbrowser.open(url):
            print(url)


if __name__ == "__main__":
    main()
