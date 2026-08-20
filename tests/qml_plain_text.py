#!/usr/bin/env python3
"""Ensure QML never auto-detects server-controlled strings as rich text."""

from pathlib import Path
import re


SOURCE = (Path(__file__).resolve().parents[1] / "Panel.qml").read_text()


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
    print("qml plain text: ok")


if __name__ == "__main__":
    main()
