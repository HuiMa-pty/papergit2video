"""Warn about narration lines whose subtitle would wrap past two lines, and scene titles that
start with a single capital letter (read as the scene ID).

The video layout keeps diagrams above a two-line subtitle box (1500 px wide, 38 px font). A
longer beat grows the box upward into the diagram. Limits are measured on the 1920x1080
player: two lines hold about 170 Latin characters (a 170-char beat measured at 2 lines)
or about 76 full-width CJK characters (38 px each); 72 leaves a small margin.
Usage: python caption_check.py <draft.md>
"""

import re
import sys
from pathlib import Path

MAX_LATIN_CHARS = 170
MAX_CJK_CHARS = 72
CJK = re.compile(r"[぀-ヿ一-鿿＀-￯]")


def caption_width(text: str) -> float:
    """Approximate width in Latin-character units; a CJK character is about 2.4 Latin ones."""
    cjk = len(CJK.findall(text))
    return (len(text) - cjk) + cjk * MAX_LATIN_CHARS / MAX_CJK_CHARS


def main() -> None:
    lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    too_long = []
    for number, line in enumerate(lines, start=1):
        if not line.startswith("> "):
            continue
        # [Name] camera cues are not shown as brackets in the subtitle.
        text = re.sub(r"\[([^\]]+)\]", r"\1", line[2:].strip())
        if caption_width(text) > MAX_LATIN_CHARS:
            too_long.append((number, text))
    # A single capital letter plus a space at the start of a scene title is read as the
    # scene's ID letter, so "## A team ..." would display as "team ...".
    for number, line in enumerate(lines, start=1):
        if re.match(r"^## [A-Z] ", line):
            print(f"  L{number} [title] the leading '{line[3]}' is read as the scene ID and "
                  f"disappears from the title; start with another word: {line[3:60]}")
    for number, text in too_long:
        print(f"  L{number} [caption] subtitle wraps past 2 lines and covers the diagram; "
              f"split it into two '>' lines: {text[:60]}...")
    if not too_long:
        print("  captions ✓ all fit in 2 lines")


if __name__ == "__main__":
    main()
