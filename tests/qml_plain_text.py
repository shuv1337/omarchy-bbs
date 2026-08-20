#!/usr/bin/env python3
"""Ensure QML never auto-detects server-controlled strings as rich text."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "BbsView.qml").read_text()


def components(pattern: str):
    for match in re.finditer(pattern, SOURCE):
        start = match.start()
        cursor = match.end()
        depth = 1
        while cursor < len(SOURCE) and depth:
            if SOURCE[cursor] == "{":
                depth += 1
            elif SOURCE[cursor] == "}":
                depth -= 1
            cursor += 1
        assert depth == 0, f"unterminated QML component at offset {start}"
        yield SOURCE[start:cursor]


def main() -> None:
    text_blocks = list(components(r"\bText\s*\{"))
    areas = list(components(r"\bControls\.TextArea\s*\{"))
    assert text_blocks and areas
    assert all(re.search(r"textFormat\s*:\s*Text\.PlainText", block) for block in text_blocks)
    assert all(re.search(r"textFormat\s*:\s*TextEdit\.PlainText", block) for block in areas)
    assert "component InlineReplyEditor" in SOURCE
    assert SOURCE.count("InlineReplyEditor{") == 2, "original posts and replies must each own an inline editor"
    assert "replyComposer.parent" not in SOURCE, "reply editors must not be dynamically reparented"
    assert 'enabled: !root.replyComposerOpen && ["compose", "edit", "report", "preferences"]' in SOURCE
    assert "wheel.accepted = false" in SOURCE, "mouse-wheel events must retain native Flickable handling"
    assert "function openToReply" in SOURCE and "focus_reply_id" in SOURCE
    assert "Notifications: " in SOURCE and "cycleThreadNotifications" in SOURCE
    assert all(name in SOURCE for name in ["mentionToggle", "replyToggle", "newPostToggle", "desktopToggle"])
    assert "detachRequested" in SOURCE and "reattachRequested" in SOURCE
    wrapper = (ROOT / "Panel.qml").read_text()
    widget = (ROOT / "BarWidget.qml").read_text()
    assert "BbsView" in wrapper and "KeyboardPanel" in wrapper
    assert "FloatingWindow" in widget and "function detach()" in widget and "function reattach()" in widget
    assert "omarchy plugin update io.github.thoughtlesslabs.omarchy-bbs --yes" in widget
    print("qml plain text: ok")


if __name__ == "__main__":
    main()
