#!/usr/bin/env bash
# Render a narrated explainer video from an `am video` draft.
# Usage:
#   bash render.sh check <draft.md>             # syntax + STE check, no voice, no MP4 (seconds)
#   bash render.sh full  <draft.md> <out_dir>   # Kokoro narration + MP4 + loudness + contact sheet
#   bash render.sh page  <draft.md> <out_dir>   # interactive one-page explainer (HTML) + screenshot
# CUDA is detected automatically (scripts/hw.sh); PAPER_VIDEO_GPU=off forces the CPU path.
set -euo pipefail
mode=$1 draft=$2 out=${3:-}
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PAPER_VIDEO_HOME="${PAPER_VIDEO_HOME:-$HOME/.papergit2video}"
# Narration stays local: never let the bundled tool pick up a cloud TTS credential from the
# environment (it would otherwise send narration text to ElevenLabs).
unset ELEVENLABS_API_KEY ELEVENLABS_VOICE_ID
export AM_HOME="$PAPER_VIDEO_HOME/am"
AM="$SKILL_DIR/vendor/am/am.mjs"  # vendored, patched copy (see vendor/am/SOURCE.txt)
[[ -f "$AM" ]] || { echo "missing $AM; reinstall the skill" >&2; exit 1; }
export AM_CHROME="${AM_CHROME:-$(ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | sort -V | tail -1)}"

# A page draft declares `template: sheet` or `template: doc`; anything else is a video draft.
is_page_draft() { grep -q -E '^template: *(sheet|doc)' "$1"; }

if [[ "$mode" == "check" ]]; then
    tmp_html="$PAPER_VIDEO_HOME/tmp/check-$$.html"
    mkdir -p "$PAPER_VIDEO_HOME/tmp"
    # `|| true`: under set -e a failing $(...) would exit before the error is printed.
    if is_page_draft "$draft"; then
        result=$(node "$AM" render "$draft" --no-open -o "$tmp_html" 2>&1 || true)
    else
        result=$(node "$AM" video "$draft" --voice off --no-open -o "$tmp_html" 2>&1 || true)
        result+=$'\n'$(python3 "$SKILL_DIR/scripts/caption_check.py" "$draft")
    fi
    echo "$result"
    rm -f "$tmp_html"  # the check output is throwaway
    exit 0
fi

if [[ "$mode" == "page" ]]; then
    [[ -n "$out" ]] || { echo "page mode needs <out_dir>" >&2; exit 1; }
    is_page_draft "$draft" || { echo "not a page draft: add 'template: sheet' or 'template: doc'" >&2; exit 1; }
    mkdir -p "$out"
    name=$(basename "$draft" .md)
    node "$AM" render "$draft" --no-open -o "$out/$name.html"
    # A tall screenshot for visual verification (the page itself is the deliverable).
    "$AM_CHROME" --headless=new --hide-scrollbars --window-size=1600,2600 \
        --screenshot="$out/$name.png" "file://$(realpath "$out/$name.html")" >/dev/null 2>&1 || true
    echo "PAGE_HTML=$out/$name.html"
    echo "SCREENSHOT=$out/$name.png"
    exit 0
fi

[[ -n "$out" ]] || { echo "full mode needs <out_dir>" >&2; exit 1; }
mkdir -p "$out"
# Some installers (ZIP uploads, plugin packagers) drop exec bits; the renderer runs this shim by name.
chmod +x "$SKILL_DIR/bin/espeak-ng" 2>/dev/null || true
export PATH="$SKILL_DIR/bin:$PATH"
# Keep export segments on the data disk (AM_HOME is set above).
export TMPDIR="$PAPER_VIDEO_HOME/tmp"
mkdir -p "$TMPDIR"

source "$SKILL_DIR/scripts/hw.sh"
detect_hardware
echo "hardware: $HW_SUMMARY"

# am caches narration by line text only, so a voice or TTS change would replay stale audio.
# Wipe the cache whenever the TTS script or voice settings change.
tts_cache="$AM_HOME/cache/tts"
voice_sig=$( (cat "$SKILL_DIR/scripts/kokoro_tts.py"; env | grep '^PAPER_VIDEO_\(VOICE\|SPEED\)' | sort || true) | sha1sum | cut -d' ' -f1)
if [[ "$(cat "$tts_cache/.voice-sig" 2>/dev/null)" != "$voice_sig" ]]; then
    rm -rf "$tts_cache"
    mkdir -p "$tts_cache"
    echo "$voice_sig" > "$tts_cache/.voice-sig"
fi

# Warm TTS server: loads Kokoro once (on CUDA when available) for the whole render.
lang=$(sed -n '/^---$/,/^---$/s/^lang: *\([a-z]*\).*/\1/p' "$draft" | head -1)
case "$lang" in zh) preload="cmn en-us" ;; ja) preload="ja en-us" ;; *) preload="en-us" ;; esac
export PAPER_VIDEO_TTS_SOCKET="$PAPER_VIDEO_HOME/tts/tts-$$.sock"
server_log="$out/$(basename "$draft" .md).tts.log"
HF_HOME="$PAPER_VIDEO_HOME/tts/hf" PYTHONDONTWRITEBYTECODE=1 "$PAPER_VIDEO_HOME/tts/.venv/bin/python" \
    "$SKILL_DIR/scripts/tts_server.py" "$PAPER_VIDEO_TTS_SOCKET" $preload >"$server_log" 2>&1 &
server_pid=$!
trap 'kill $server_pid 2>/dev/null; rm -f "$PAPER_VIDEO_TTS_SOCKET"' EXIT
for _ in $(seq 300); do
    grep -q "tts server ready" "$server_log" && break
    kill -0 $server_pid 2>/dev/null || { echo "TTS server failed; see $server_log" >&2; exit 1; }
    sleep 1
done
grep -q "tts server ready" "$server_log" || { echo "TTS server did not start; see $server_log" >&2; exit 1; }
grep "tts server ready" "$server_log"

log="$out/$(basename "$draft" .md).render.log"
# Stream to a log (progress stays visible) and fail loudly; a captured $(...) would hide errors.
start=$(date +%s)
if ! node "$AM" video "$draft" --voice system --mp4 --no-open 2>&1 | tee "$log"; then
    echo "am video failed; see $log" >&2
    exit 1
fi
echo "render time: $(( $(date +%s) - start )) s"
result=$(grep -v '导出 MP4：' "$log")
# `am` prints "✓ <path>" for the HTML player and "✓ <path>（Ns 导出）" for the MP4.
mapfile -t made < <(echo "$result" | sed -n 's/^✓ //p' | sed 's/（.*//')
html=""; mp4=""
for f in "${made[@]}"; do
    [[ "$f" == *.html ]] && html=$f
    [[ "$f" == *.mp4 ]] && mp4=$f
done
[[ -n "$mp4" && -f "$mp4" ]] || { echo "MP4 export failed; see output above" >&2; exit 1; }

name=$(basename "$draft" .md)
cp "$html" "$out/$name.html"
final="$out/$name.mp4"
# Kokoro output is quiet (~-27 LUFS); normalise to the -14 LUFS streaming target.
ffmpeg -hide_banner -loglevel error -y -i "$mp4" -af loudnorm=I=-14:TP=-1.5:LRA=11 -ar 48000 \
    -c:v copy -c:a aac -b:a 192k -movflags +faststart "$final"
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$final")
ffmpeg -hide_banner -loglevel error -y -i "$final" \
    -vf "fps=16/$duration,scale=480:-1,tile=4x4" -frames:v 1 "$out/$name.sheet.png"
echo "FINAL_MP4=$final"
echo "PLAYER_HTML=$out/$name.html"
echo "CONTACT_SHEET=$out/$name.sheet.png"
echo "DURATION_S=$duration"
