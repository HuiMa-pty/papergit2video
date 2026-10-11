"""Write ffmpeg chapter metadata (one chapter per scene) from a rendered video player page.

Usage: python3 chapters.py <player.html> <out_ffmetadata.txt>

The player page embeds its timeline as JSON in <script id="amv-data">. Each segment's start
time becomes a chapter; the first segment is the title card. Also prints a YouTube-style
chapter list (m:ss Title) so the user can paste it into a description.
"""

import json
import re
import sys
from pathlib import Path


def escape(text: str) -> str:
    """Escape the characters that ffmetadata treats as special."""
    return re.sub(r"([=;#\\\n])", r"\\\1", text)


def main() -> None:
    page, out = Path(sys.argv[1]), Path(sys.argv[2])
    match = re.search(r'id="amv-data">(.*?)</script>', page.read_text(encoding="utf-8"), re.S)
    if not match:
        sys.exit(f"no timeline data in {page}")
    data = json.loads(match.group(1))
    segments = data["segments"]
    lines = [";FFMETADATA1"]
    for i, seg in enumerate(segments):
        end = segments[i + 1]["start"] if i + 1 < len(segments) else data["duration"]
        title = "Intro" if i == 0 else seg["title"]
        lines += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={round(seg['start'] * 1000)}",
                  f"END={round(end * 1000)}", f"title={escape(title)}"]
        start = round(seg["start"])
        print(f"CHAPTER {start // 60}:{start % 60:02d} {title}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
