#!/usr/bin/env bash
# Build dist/papergit2video.zip for "Upload skill" in the Claude desktop and web apps
# (Settings → Capabilities → Skills). The ZIP's top-level folder is the skill folder and holds
# exactly one SKILL.md, as the upload validator requires.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/papergit2video.zip"
cd "$ROOT/skills"
zip -q -r -X "$ROOT/dist/papergit2video.zip" papergit2video -x '*/__pycache__/*' '*.pyc' '*/.DS_Store'
echo "built $ROOT/dist/papergit2video.zip ($(du -h "$ROOT/dist/papergit2video.zip" | cut -f1))"
