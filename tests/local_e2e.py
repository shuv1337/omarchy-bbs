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
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "client.py"


def call(command: str, payload: dict | None, state: Path, url: str, ok: bool = True, environment_payload: bool = False) -> dict:
    env = os.environ | {"XDG_STATE_HOME": str(state), "OMARCHY_BBS_URL": url}
    if payload is not None and environment_payload:
        env["OMARCHY_BBS_PAYLOAD"] = json.dumps(payload)
    result = subprocess.run(
        ["python3", str(CLIENT), command],
        input=(json.dumps(payload) + "\n") if payload is not None and not environment_payload else None,
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

            wrong_type = urllib.request.Request(url + "/api/register", data=b"{}", headers={"Content-Type": "text/plain"}, method="POST")
            try:
                urllib.request.urlopen(wrong_type, timeout=2)
                raise AssertionError("non-JSON request was accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 415
            oversized = urllib.request.Request(url + "/api/register", data=b"{" + b" " * 65536 + b"}", headers={"Content-Type": "application/json"}, method="POST")
            try:
                urllib.request.urlopen(oversized, timeout=2)
                raise AssertionError("oversized request was accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 413

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
            feedback = call("create", {"category": "feedback", "title": "BBS feedback", "body": "A focused place for suggestions"}, third, url)
            assert call("threads", {"category": "feedback", "query": "", "page": 1}, admin, url)["threads"][0]["id"] == feedback["thread_id"]
            for index in range(9):
                call("create", {"category": "general", "title": f"Admin page fixture {index}", "body": "Pagination fixture"}, admin, url)
            for index in range(10):
                call("create", {"category": "help", "title": f"Member page fixture {index}", "body": "Pagination fixture"}, member, url)
            for index in range(1):
                call("create", {"category": "meta", "title": f"Third page fixture {index}", "body": "Pagination fixture"}, third, url)
            first_page = call("threads", {"category": "all", "query": "", "page": 1}, third, url)
            second_page = call("threads", {"category": "all", "query": "", "page": 2}, third, url)
            assert first_page["pages"] == 2 and len(first_page["threads"]) == 20
            assert len(second_page["threads"]) == 2
            listing = call("threads", {"category": "projects", "query": "encrypted", "page": 1}, member, url)
            assert listing["threads"][0]["unread"] is True
            assert call("threads", {"category": "projects", "query": "encrypted", "page": 1}, member, url, environment_payload=True)["threads"][0]["id"] == thread_id
            injected_search = call("threads", {"category": "all", "query": "%' OR 1=1 --", "page": 1}, member, url)
            assert injected_search["total"] == 0
            assert "not found" in call("profile", {"handle": "test-admin' OR 1=1 --"}, member, url, ok=False)["error"].lower()
            assert call("thread", {"thread_id": thread_id}, member, url)["thread"]["mine"] is False
            assert call("threads", {"category": "projects", "query": "", "page": 1}, member, url)["threads"][0]["unread"] is False

            reply = call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "Replying to @test-admin"}, member, url)
            reply_id = reply["reply_id"]
            exact_reply = call("thread", {"thread_id": thread_id, "reply_page": 0, "reply_id": reply_id}, third, url)["thread"]
            assert exact_reply["focus_reply_id"] == reply_id and exact_reply["reply_page"] == 1
            assert exact_reply["notification_mode"] == "default"
            watched = call("thread-notifications", {"thread_id": thread_id, "mode": "watch"}, third, url)
            assert watched["mode"] == "watch"
            assert call("threads", {"category": "projects", "query": "", "page": 1}, third, url)["threads"][0]["notification_mode"] == "watch"
            third_prefs = call("preferences", {"action": "set", "handle": "test-third", "bio": "", "mention_notifications": False, "reply_notifications": False, "new_post_notifications": False, "desktop_notifications": True}, third, url)["preferences"]
            assert third_prefs["reply_notifications"] is False and third_prefs["desktop_notifications"] is True
            watched_status = call("status", None, third, url)
            assert any(event["event_id"] == f"reply:{reply_id}" and event["deliver"] is True for event in watched_status["events"])
            call("preferences", {"action": "set", "handle": "test-third", "bio": "", "mention_notifications": False, "reply_notifications": False, "new_post_notifications": False, "desktop_notifications": False}, third, url)
            desktop_off = call("status", None, third, url)
            assert not any(event["deliver"] for event in desktop_off["events"]), "the desktop master switch must suppress delivery"
            call("preferences", {"action": "set", "handle": "test-third", "bio": "", "mention_notifications": False, "reply_notifications": False, "new_post_notifications": False, "desktop_notifications": True}, third, url)
            call("thread-notifications", {"thread_id": thread_id, "mode": "mute"}, third, url)
            muted_status = call("status", None, third, url)
            assert any(event["event_id"] == f"reply:{reply_id}" and event["deliver"] is False for event in muted_status["events"])
            call("thread-notifications", {"thread_id": thread_id, "mode": "default"}, third, url)
            assert call("thread", {"thread_id": thread_id}, third, url)["thread"]["notification_mode"] == "default"
            assert "invalid" in call("thread-notifications", {"thread_id": thread_id, "mode": "loud"}, third, url, ok=False)["error"].lower()
            assert call("like", {"kind": "thread", "id": thread_id, "enabled": True}, admin, url) == {"ok": True, "likes": 1, "liked": True}
            assert call("like", {"kind": "thread", "id": thread_id, "enabled": True}, member, url)["likes"] == 2
            assert call("like", {"kind": "thread", "id": thread_id, "enabled": True}, member, url)["likes"] == 2, "a user may heart only once"
            assert call("like", {"kind": "thread", "id": thread_id, "enabled": False}, member, url) == {"ok": True, "likes": 1, "liked": False}
            assert call("like", {"kind": "reply", "id": reply_id, "enabled": True}, admin, url) == {"ok": True, "likes": 1, "liked": True}
            assert "not found" in call("like", {"kind": "reply", "id": 999999, "enabled": True}, admin, url, ok=False)["error"].lower()
            assert call("threads", {"category": "projects", "query": "", "page": 1}, admin, url)["threads"][0]["likes"] == 1
            call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": "A reply without a tag"}, third, url)
            admin_status = call("status", None, admin, url)
            assert {"mention", "reply", "new_post"} <= {event["kind"] for event in admin_status["events"]}
            assert len([event for event in admin_status["events"] if event["actor"] == "test-member" and event["kind"] in {"mention", "reply"}]) == 1
            assert admin_status["unread"] > 0, "a reply to your post must activate unread status"
            assert next(event for event in admin_status["events"] if event["event_id"] == f"reply:{reply_id}")["deliver"] is True
            assert any(event["kind"] == "new_post" and event["deliver"] is False for event in admin_status["events"]), "new-post alerts default off"
            call("thread-notifications", {"thread_id": thread_id, "mode": "mute"}, admin, url)
            muted_admin = call("status", None, admin, url)
            assert next(event for event in muted_admin["events"] if event["event_id"] == f"reply:{reply_id}")["deliver"] is False
            assert muted_admin["unread"] > 0 and muted_admin["mentions"] > 0 and muted_admin["alert_mentions"] == 0, "muting must not change unread or mention history"
            call("thread-notifications", {"thread_id": thread_id, "mode": "default"}, admin, url)
            heart_view = call("thread", {"thread_id": thread_id}, admin, url)["thread"]
            assert heart_view["likes"] == 1 and heart_view["liked"] is True
            assert next(item for item in heart_view["replies"] if item["id"] == reply_id)["liked"] is True
            nested = call("reply", {"thread_id": thread_id, "parent_reply_id": reply_id, "body": "Nested reply"}, admin, url)
            assert nested["reply_page"] == 1
            direct_comment_status = call("status", None, member, url)
            assert any(event["event_id"] == f"reply:{nested['reply_id']}" and event["kind"] == "reply" and event["deliver"] is True for event in direct_comment_status["events"]), "a direct reply to your comment must notify you"
            grandchild = call("reply", {"thread_id": thread_id, "parent_reply_id": nested["reply_id"], "body": "Third-level reply"}, member, url)
            assert grandchild["reply_page"] == 1
            for index in range(20):
                call("reply", {"thread_id": thread_id, "parent_reply_id": 0, "body": f"Reply page fixture {index}"}, admin, url)
            reply_page_one = call("thread", {"thread_id": thread_id, "reply_page": 1}, admin, url)["thread"]
            reply_page_two = call("thread", {"thread_id": thread_id, "reply_page": 2}, admin, url)["thread"]
            reply_latest = call("thread", {"thread_id": thread_id}, admin, url)["thread"]
            assert reply_page_one["reply_pages"] == 2 and len(reply_page_one["replies"]) == 22
            assert reply_page_two["reply_page"] == 2 and len(reply_page_two["replies"]) == 2
            assert reply_latest["reply_page"] == 2, "opening a thread should show its newest replies"
            ordered_ids = [item["id"] for item in reply_page_one["replies"]]
            assert ordered_ids.index(reply_id) < ordered_ids.index(nested["reply_id"]) < ordered_ids.index(grandchild["reply_id"])
            assert next(item for item in reply_page_one["replies"] if item["id"] == reply_id)["depth"] == 0
            assert next(item for item in reply_page_one["replies"] if item["id"] == nested["reply_id"])["depth"] == 1
            assert next(item for item in reply_page_one["replies"] if item["id"] == grandchild["reply_id"])["depth"] == 2
            call("edit", {"kind": "thread", "id": thread_id, "category": "showcase", "title": "Edited encrypted post", "body": "Edited secret body @test-member"}, admin, url)
            call("edit", {"kind": "reply", "id": reply_id, "body": "Edited member reply"}, member, url)
            assert "invalid" in call("edit", {"kind": "thread", "id": thread_id, "category": "showcase", "title": "x" * 121, "body": "body"}, admin, url, ok=False)["error"].lower()
            assert "invalid" in call("edit", {"kind": "reply", "id": reply_id, "body": "x" * 8001}, member, url, ok=False)["error"].lower()

            preferences = call("preferences", {"action": "get"}, admin, url)["preferences"]
            assert preferences["handle"] == "test-admin"
            assert preferences["mention_notifications"] is True and preferences["reply_notifications"] is True
            assert preferences["new_post_notifications"] is False and preferences["desktop_notifications"] is True
            assert "lowercase" in call("preferences", {"action": "set", "handle": "not valid!", "bio": "", "mention_notifications": True}, admin, url, ok=False)["error"]
            collision = call("preferences", {"action": "set", "handle": "test-member", "bio": "Private encrypted bio", "mention_notifications": False}, admin, url, ok=False)
            assert collision["error"] == "Username already exists"
            renamed = call("preferences", {"action": "set", "handle": "renamed-admin", "bio": "Private encrypted bio", "mention_notifications": False, "reply_notifications": True, "new_post_notifications": False, "desktop_notifications": True}, admin, url)
            assert renamed["preferences"]["handle"] == "renamed-admin"
            assert json.loads((admin / "omarchy-bbs/device.json").read_text())["handle"] == "renamed-admin"
            assert "not found" in call("profile", {"handle": "test-admin"}, member, url, ok=False)["error"].lower()
            assert call("profile", {"handle": "renamed-admin"}, member, url)["profile"]["posts"] == 10
            renamed_thread = call("thread", {"thread_id": thread_id, "reply_page": 1}, member, url)["thread"]
            assert renamed_thread["handle"] == "renamed-admin"
            assert any(item["handle"] == "renamed-admin" for item in renamed_thread["replies"])
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
            thread = call("thread", {"thread_id": thread_id, "reply_page": 1}, admin, url)["thread"]
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
