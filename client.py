#!/usr/bin/env python3
"""Native client bridge for the Omarchy BBS shell panel."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy-bbs"
CONFIG_FILE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-bbs/config.json"
DEVICE_FILE = STATE_DIR / "device.json"
STATUS_FILE = STATE_DIR / "status.json"
PLUGIN_DIR = Path(__file__).resolve().parent


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(code)


def omarchy_version() -> str:
    if not Path("/usr/share/omarchy").is_dir():
        fail("Omarchy was not detected on this machine")
    try:
        result = subprocess.run(
            ["omarchy", "version"], check=True, capture_output=True, text=True, timeout=5
        )
    except (FileNotFoundError, subprocess.SubprocessError) as exc:
        fail(f"Could not verify Omarchy: {exc}")
    version = result.stdout.strip()
    if not version:
        fail("The Omarchy version command returned no version")
    return version


def server_url() -> str:
    if value := os.environ.get("OMARCHY_BBS_URL"):
        return value.rstrip("/")
    try:
        return json.loads(CONFIG_FILE.read_text())["server_url"].rstrip("/")
    except (OSError, KeyError, json.JSONDecodeError):
        return "https://bbs.thoughtlesslabs.com"


def read_input() -> dict:
    try:
        value = json.loads(sys.stdin.readline())
    except json.JSONDecodeError:
        fail("Invalid request data")
    if not isinstance(value, dict):
        fail("Request data must be an object")
    return value


def request_json(path: str, payload: dict) -> dict:
    request = urllib.request.Request(
        f"{server_url()}{path}",
        data=json.dumps(payload, separators=(",", ":")).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "Omarchy-BBS/1"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            value = json.load(response)
            return value if isinstance(value, dict) else {"data": value}
    except urllib.error.HTTPError as exc:
        try:
            message = json.load(exc).get("error", exc.reason)
        except Exception:
            message = exc.reason
        fail(str(message))
    except urllib.error.URLError as exc:
        fail(f"Could not reach the BBS: {exc.reason}")


def suggested_handle() -> str:
    value = socket.gethostname().split(".", 1)[0].lower()
    value = re.sub(r"[^a-z0-9_-]+", "-", value).strip("-_")[:31]
    if len(value) < 3:
        value = f"omarchy-{hashlib.sha256(socket.gethostname().encode()).hexdigest()[:8]}"
    return value


def load_device(required: bool = True) -> dict | None:
    omarchy_version()
    try:
        record = json.loads(DEVICE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        record = None
    if record and record.get("server_url") == server_url():
        return record
    if required:
        fail("Join the board from the first-run screen")
    return None


def save_device(record: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DEVICE_FILE.write_text(json.dumps(record, indent=2) + "\n")
    os.chmod(DEVICE_FILE, 0o600)


def register() -> None:
    if existing := load_device(required=False):
        print(json.dumps({"ok": True, "registered": True, "handle": existing["handle"]}))
        return
    request = read_input()
    handle = str(request.get("handle", "")).lower().strip()
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]", handle):
        fail("Use 3–32 lowercase letters, numbers, hyphens, or underscores")
    device_id = secrets.token_urlsafe(18)
    secret = secrets.token_hex(32)
    response = request_json("/api/register", {
        "device_id": device_id,
        "secret": secret,
        "handle": handle,
        "omarchy_version": omarchy_version(),
    })
    save_device({"device_id": device_id, "secret": secret, "handle": response["handle"], "server_url": server_url()})
    notify("Omarchy BBS", f"You are tuned in as @{response['handle']}.")
    print(json.dumps({"ok": True, "registered": True, "handle": response["handle"]}))


def signed_fields(record: dict, purpose: str) -> dict:
    timestamp = str(int(time.time()))
    nonce = secrets.token_urlsafe(12)
    message = f"{record['device_id']}.{timestamp}.{nonce}.{purpose}".encode()
    signature = hmac.new(bytes.fromhex(record["secret"]), message, hashlib.sha256).hexdigest()
    return {"device": record["device_id"], "ts": timestamp, "nonce": nonce, "sig": signature}


def signed_request(path: str, purpose: str, extra: dict | None = None) -> dict:
    payload = dict(extra or {})
    payload.update(signed_fields(load_device(), purpose))
    return request_json(path, payload)


def notify(title: str, message: str) -> None:
    try:
        subprocess.run(
            ["omarchy", "notification", "send", "--exec", "omarchy-shell omarchy.bbs toggle", "-g", "󰆍", title, message],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        pass


def identity() -> None:
    record = load_device(required=False)
    print(json.dumps({
        "ok": True,
        "registered": bool(record),
        "handle": record.get("handle") if record else "",
        "suggested_handle": suggested_handle(),
    }))


def status(should_notify: bool) -> None:
    record = load_device(required=False)
    if not record:
        print(json.dumps({"ok": True, "registered": False, "unread": 0}))
        return
    response = signed_request("/api/status", "status")
    try:
        previous = json.loads(STATUS_FILE.read_text()).get("unread", 0)
    except (OSError, json.JSONDecodeError):
        previous = 0
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATUS_FILE.write_text(json.dumps(response, indent=2) + "\n")
    os.chmod(STATUS_FILE, 0o600)
    if should_notify and response.get("unread", 0) > previous:
        notify("Omarchy BBS", f"{response['unread']} new transmission{'s' if response['unread'] != 1 else ''}.")
    print(json.dumps({"ok": True, "registered": True, **response}))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("identity")
    sub.add_parser("register")
    sub.add_parser("threads")
    sub.add_parser("thread")
    sub.add_parser("create")
    sub.add_parser("reply")
    status_parser = sub.add_parser("status")
    status_parser.add_argument("--notify", action="store_true")
    args = parser.parse_args()
    if args.command == "identity": identity()
    elif args.command == "register": register()
    elif args.command == "status": status(args.notify)
    elif args.command == "threads": print(json.dumps(signed_request("/api/threads", "threads")))
    elif args.command == "thread":
        item = read_input(); thread_id = int(item.get("thread_id", 0))
        print(json.dumps(signed_request("/api/thread", f"thread:{thread_id}", {"thread_id": thread_id})))
    elif args.command == "create":
        item = read_input(); title = str(item.get("title", "")).strip(); body = str(item.get("body", "")).strip()
        digest = hashlib.sha256(f"{title}\0{body}".encode()).hexdigest()
        print(json.dumps(signed_request("/api/create", f"create:{digest}", {"title": title, "body": body})))
    elif args.command == "reply":
        item = read_input(); thread_id = int(item.get("thread_id", 0)); body = str(item.get("body", "")).strip()
        digest = hashlib.sha256(body.encode()).hexdigest()
        print(json.dumps(signed_request("/api/reply", f"reply:{thread_id}:{digest}", {"thread_id": thread_id, "body": body})))


if __name__ == "__main__":
    main()
