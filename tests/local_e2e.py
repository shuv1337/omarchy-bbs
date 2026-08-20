#!/usr/bin/env python3
"""Exercise the complete BBS API against an isolated encrypted SQLite database."""

from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "client.py"


def call(command: str, payload: dict | None, state: Path, url: str, ok: bool = True) -> dict:
    env = os.environ | {"XDG_STATE_HOME": str(state), "OMARCHY_BBS_URL": url}
    result = subprocess.run(
        ["python3", str(CLIENT), command],
        input=(json.dumps(payload) + "\n") if payload is not None else None,
        text=True,
        capture_output=True,
        env=env,
        timeout=10,
    )
    data = json.loads(result.stdout)
    assert (result.returncode == 0) is ok, (command, result.stdout, result.stderr)
    return data


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="omarchy-bbs-e2e-") as temp_name:
        temp = Path(temp_name)
        database = temp / "bbs.sqlite"
        config = temp / "config.php"
        config.write_text(
            "<?php return [\n"
            "'driver'=>'sqlite',\n"
            f"'db_path'=>'{database}',\n"
            "'app_key'=>'89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567',\n"
            "'admin_handles'=>['test-admin'],\n];\n"
        )
        os.chmod(config, 0o600)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        url = f"http://127.0.0.1:{port}"
        server = subprocess.Popen(
            ["php", "-S", f"127.0.0.1:{port}", str(ROOT / "web/index.php")],
            cwd=ROOT,
            env=os.environ | {"OMARCHY_BBS_CONFIG": str(config)},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(40):
                try:
                    with urllib.request.urlopen(url + "/health", timeout=1) as response:
                        if json.load(response)["ok"]:
                            break
                except Exception:
                    time.sleep(0.05)
            else:
                raise AssertionError("local server did not start")

            admin, member, third, duplicate = temp / "admin", temp / "member", temp / "third", temp / "duplicate"
            assert call("register", {"handle": "test-admin"}, admin, url)["handle"] == "test-admin"
            assert call("register", {"handle": "test-member"}, member, url)["handle"] == "test-member"
            assert call("register", {"handle": "test-third"}, third, url)["handle"] == "test-third"
            assert call("register", {"handle": "test-admin"}, duplicate, url, ok=False)["error"] == "Username already exists"
            with sqlite3.connect(database) as connection:
                assert connection.execute("SELECT role FROM users WHERE handle='test-admin'").fetchone()[0] == "member"
            manage = ROOT / "deploy/manage-admin.php"
            subprocess.run(["php", str(manage), str(config), "promote", "test-admin"], check=True, capture_output=True, text=True)
            subprocess.run(["php", str(manage), str(config), "promote", "test-third"], check=True, capture_output=True, text=True)
            subprocess.run(["php", str(manage), str(config), "demote", "test-third"], check=True, capture_output=True, text=True)
            final_admin = subprocess.run(["php", str(manage), str(config), "demote", "test-admin"], capture_output=True, text=True)
            assert final_admin.returncode != 0 and "final administrator" in final_admin.stderr
            for index in range(7):
                assert call("register", {"handle": f"rate-user-{index}"}, temp / f"rate-{index}", url)["registered"] is True
            limited = call("register", {"handle": "rate-limited"}, temp / "rate-limited", url, ok=False)
            assert limited["error"] == "Too many registrations"

            created = call("create", {"category": "projects", "title": "Encrypted test post", "body": "Hello @test-member — secret body"}, admin, url)
            thread_id = created["thread_id"]
            for index in range(9):
                call("create", {"category": "general", "title": f"Admin page fixture {index}", "body": "Pagination fixture"}, admin, url)
            for index in range(10):
                call("create", {"category": "help", "title": f"Member page fixture {index}", "body": "Pagination fixture"}, member, url)
            for index in range(2):
                call("create", {"category": "meta", "title": f"Third page fixture {index}", "body": "Pagination fixture"}, third, url)
            first_page = call("threads", {"category": "all", "query": "", "page": 1}, third, url)
            second_page = call("threads", {"category": "all", "query": "", "page": 2}, third, url)
            assert first_page["pages"] == 2 and len(first_page["threads"]) == 20
            assert len(second_page["threads"]) == 2
            listing = call("threads", {"category": "projects", "query": "encrypted", "page": 1}, member, url)
            assert listing["threads"][0]["unread"] is True
            assert call("thread", {"thread_id": thread_id}, member, url)["thread"]["mine"] is False
            assert call("threads", {"category": "projects", "query": "", "page": 1}, member, url)["threads"][0]["unread"] is False

            reply = call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "Replying to @test-admin"}, member, url)
            reply_id = reply["reply_id"]
            call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "A reply without a tag"}, third, url)
            admin_status = call("status", None, admin, url)
            assert {event["kind"] for event in admin_status["events"]} == {"mention", "reply"}
            assert len([event for event in admin_status["events"] if event["actor"] == "test-member"]) == 1
            assert admin_status["unread"] > 0, "a reply to your post must activate unread status"
            call("reply", {"thread_id": thread_id, "parent_reply_id": reply_id, "body": "Nested reply"}, admin, url)
            call("edit", {"kind": "thread", "id": thread_id, "category": "showcase", "title": "Edited encrypted post", "body": "Edited secret body @test-member"}, admin, url)
            call("edit", {"kind": "reply", "id": reply_id, "body": "Edited member reply"}, member, url)
            assert "invalid" in call("edit", {"kind": "thread", "id": thread_id, "category": "showcase", "title": "x" * 121, "body": "body"}, admin, url, ok=False)["error"].lower()
            assert "invalid" in call("edit", {"kind": "reply", "id": reply_id, "body": "x" * 8001}, member, url, ok=False)["error"].lower()

            call("preferences", {"action": "set", "bio": "Private encrypted bio", "mention_notifications": False}, admin, url)
            assert call("profile", {"handle": "test-admin"}, member, url)["profile"]["posts"] == 10
            assert call("mentions", {"page": 1, "mark_read": False}, member, url)["mentions"]
            member_status = call("status", None, member, url)
            assert member_status["mentions"] > 0 and any(event["kind"] == "mention" for event in member_status["events"])
            call("thread", {"thread_id": thread_id}, member, url)
            cleared_status = call("status", None, member, url)
            assert cleared_status["mentions"] == 0 and not any(event["kind"] == "mention" for event in cleared_status["events"])
            call("report", {"kind": "thread", "id": thread_id, "reason": "Encrypted report reason"}, member, url)
            reports = call("moderation", {"action": "list_reports"}, admin, url)["reports"]
            assert reports[0]["reason"] == "Encrypted report reason"
            call("moderation", {"action": "resolve_report", "report_id": reports[0]["id"]}, admin, url)
            call("moderation", {"action": "pin", "thread_id": thread_id, "enabled": True}, admin, url)
            call("moderation", {"action": "lock", "thread_id": thread_id, "enabled": True}, admin, url)
            assert "locked" in call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "blocked"}, member, url, ok=False)["error"].lower()
            call("moderation", {"action": "category_moderator", "handle": "test-member", "category": "showcase", "enabled": True}, admin, url)
            call("moderation", {"action": "lock", "thread_id": thread_id, "enabled": False}, member, url)
            call("moderation", {"action": "suspend", "handle": "test-member", "hours": 1}, admin, url)
            assert "suspended" in call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "blocked"}, member, url, ok=False)["error"].lower()
            call("moderation", {"action": "suspend", "handle": "test-member", "hours": 0}, admin, url)
            call("delete", {"kind": "reply", "id": reply_id}, member, url)
            thread = call("thread", {"thread_id": thread_id}, admin, url)["thread"]
            assert any(item["deleted"] for item in thread["replies"])

            raw = database.read_bytes()
            for plaintext in [b"Encrypted test post", b"secret body", b"Private encrypted bio", b"Encrypted report reason"]:
                assert plaintext not in raw, f"plaintext leaked into SQLite: {plaintext!r}"
            assert (database.stat().st_mode & 0o077) == 0
            print("local e2e: ok")
        finally:
            server.terminate()
            server.wait(timeout=5)


if __name__ == "__main__":
    main()
