#!/usr/bin/env python3
"""Verify notification baselining, delivery, and deduplication."""

from __future__ import annotations

import contextlib
import io
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


def poll(value: dict, notifications: list[tuple[str, str]]) -> None:
    with (
        mock.patch.object(client, "load_device", return_value={"device_id": "test"}),
        mock.patch.object(client, "signed_request", return_value=value),
        mock.patch.object(client, "notify", side_effect=lambda title, body: notifications.append((title, body))),
        contextlib.redirect_stdout(io.StringIO()),
    ):
        client.status(True)


def main() -> None:
    with mock.patch.object(client.subprocess, "run") as run:
        client.notify("Omarchy BBS", "Test")
        command = run.call_args.args[0]
        assert command[:4] == ["omarchy", "notification", "send", "--exec"]
        assert command[4] == "omarchy shell omarchy.bbs open"

    with tempfile.TemporaryDirectory(prefix="omarchy-bbs-notifications-") as name:
        state = Path(name)
        notifications: list[tuple[str, str]] = []
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

            poll(response("mention:2", "mention:1"), notifications)
            assert len(notifications) == 1, "an already-seen event must not alert twice"

            poll(response("mention:3", "mention:2", "mention:1", title='<img src="https://example.invalid/pixel">'), notifications)
            assert "<img" not in notifications[-1][1]
            assert "&lt;img" in notifications[-1][1], "notification markup must be escaped"

    print("notification state: ok")


if __name__ == "__main__":
    main()
