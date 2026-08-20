#!/usr/bin/env python3
"""Verify notification baselining, delivery, and deduplication."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import client


def response(*event_ids: str, title: str = "Hello") -> dict:
    return {
        "ok": True,
        "unread": len(event_ids),
        "mentions": len(event_ids),
        "unread_threads": 0,
        "events": [
            {
                "event_id": event_id,
                "kind": "mention",
                "actor": "alice",
                "title": title,
                "thread_id": 1,
            }
            for event_id in event_ids
        ],
    }


def poll(value: dict, notifications: list[tuple[str, str, int, int]]) -> None:
    with (
        mock.patch.object(client, "load_device", return_value={"device_id": "test"}),
        mock.patch.object(client, "signed_request", return_value=value),
        mock.patch.object(client, "update_status", return_value={"update_available": False, "current_version": "0.9.0", "latest_version": "0.9.0"}),
        mock.patch.object(client, "notify", side_effect=lambda title, body, thread_id=0, reply_id=0: notifications.append((title, body, thread_id, reply_id))),
        contextlib.redirect_stdout(io.StringIO()),
    ):
        client.status(True)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="omarchy-bbs-update-") as name:
        update_file = Path(name) / "update.json"
        update_file.write_text(json.dumps({"current_version": "0.9.2", "latest_version": "0.9.2", "checked_at": int(client.time.time())}))
        response_data = mock.MagicMock()
        response_data.__enter__.return_value = io.StringIO('{"tag_name":"v0.10.0"}')
        response_data.__exit__.return_value = False
        with (
            mock.patch.object(client, "UPDATE_FILE", update_file),
            mock.patch.object(client, "STATE_DIR", Path(name)),
            mock.patch.object(client, "installed_plugin_version", return_value="0.10.0"),
            mock.patch.object(client.urllib.request, "urlopen", return_value=response_data),
        ):
            update = client.update_status()
            assert update["current_version"] == "0.10.0" and update["update_available"] is False

    with mock.patch.object(client.subprocess, "run") as run:
        client.notify("Omarchy BBS", "Test")
        command = run.call_args.args[0]
        assert command[:4] == ["omarchy", "notification", "send", "--exec"]
        assert command[4] == "omarchy shell omarchy.bbs open"
        client.notify("Omarchy BBS", "Thread", 42)
        assert run.call_args.args[0][4] == "omarchy shell omarchy.bbs openThread 42"
        client.notify("Omarchy BBS", "Reply", 42, 9)
        assert run.call_args.args[0][4] == "omarchy shell omarchy.bbs openReply 42 9"

    with tempfile.TemporaryDirectory(prefix="omarchy-bbs-notifications-") as name:
        state = Path(name)
        notifications: list[tuple[str, str, int, int]] = []
        with (
            mock.patch.object(client, "STATE_DIR", state),
            mock.patch.object(client, "STATUS_FILE", state / "status.json"),
        ):
            poll(response("mention:1"), notifications)
            assert notifications == [], "the initial baseline must not alert for old events"
            persisted = (state / "status.json").read_text()
            assert "Hello" not in persisted and "alice" not in persisted, "notification metadata must not persist"

            poll(response("mention:2", "mention:1"), notifications)
            assert len(notifications) == 1 and "@alice mentioned you" in notifications[0][1]
            assert notifications[0][2] == 1

            poll(response("mention:2", "mention:1"), notifications)
            assert len(notifications) == 1, "an already-seen event must not alert twice"

            poll(response("mention:3", "mention:2", "mention:1", title='<img src="https://example.invalid/pixel">'), notifications)
            assert "<img" not in notifications[-1][1]
            assert "&lt;img" in notifications[-1][1], "notification markup must be escaped"

            muted = response("mention:4", "mention:3")
            muted["events"][0]["deliver"] = False
            poll(muted, notifications)
            assert len(notifications) == 2, "suppressed events must be baselined without delivery"
            muted["events"][0]["deliver"] = True
            poll(muted, notifications)
            assert len(notifications) == 2, "re-enabling notifications must not replay suppressed events"

    print("notification state: ok")


if __name__ == "__main__":
    main()
