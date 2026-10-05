#!/usr/bin/env bash
# Idempotent setup: Kokoro TTS venv (en + zh), ffmpeg and Chrome checks, CUDA when available.
# Usage: bash setup.sh [--ja]   (--ja also installs Japanese support)
# On an NVIDIA machine it installs CUDA torch and, if needed, an NVENC-capable static ffmpeg.
set -euo pipefail
HOME_DIR="${PAPER_VIDEO_HOME:-$HOME/.papergit2video}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$HOME_DIR/tts/.venv"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME_DIR/uv-cache}" PAPER_VIDEO_HOME="$HOME_DIR"
mkdir -p "$HOME_DIR/tts"
source "$SKILL_DIR/scripts/hw.sh"   # portable helpers (find_chrome, cpu_count) + detect_hardware
has_gpu=0
nvidia-smi -L >/dev/null 2>&1 && has_gpu=1

if ! "$VENV/bin/python" -c "import kokoro, jieba" 2>/dev/null; then
    echo "Installing Kokoro TTS into $VENV ..."
    uv venv -q --python 3.12 "$VENV"
    # Pin a modern transformers: the resolver otherwise picks an ancient one. On Linux the
    # "+cpu" torch build keeps a GPU-less venv small; macOS has no "+cpu" build and uses the
    # standard PyPI wheel instead.
    torch_args=("torch==2.5.1")
    if [[ "$(uname -s)" == "Linux" ]]; then
        torch_args=(--index-strategy unsafe-best-match
            --extra-index-url https://download.pytorch.org/whl/cpu "torch==2.5.1+cpu")
    fi
    uv pip install -q --python "$VENV/bin/python" "${torch_args[@]}" \
        "transformers>=4.44" "kokoro>=0.9.4" "misaki[zh]" soundfile \
        "en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
fi
if (( has_gpu )) && ! "$VENV/bin/python" -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    echo "NVIDIA GPU found: installing CUDA torch so Kokoro runs on the GPU ..."
    uv pip install -q --python "$VENV/bin/python" --index-strategy unsafe-best-match \
        --extra-index-url https://download.pytorch.org/whl/cu124 "torch==2.5.1+cu124"
fi
if [[ "${1:-}" == "--ja" ]]; then
    uv pip install -q --python "$VENV/bin/python" "misaki[ja]"
fi
echo "ok  kokoro venv: $VENV"

encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
if (( has_gpu )) && [[ "$encoders" != *h264_nvenc* ]]; then
    # Many static builds (e.g. johnvansickle's) omit NVENC; BtbN's GPL builds include it.
    ff_dir="$HOME_DIR/ffmpeg"
    echo "NVIDIA GPU found: installing an NVENC-capable ffmpeg into $ff_dir ..."
    mkdir -p "$ff_dir" ~/.local/bin
    curl -sL https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.1-latest-linux64-gpl-8.1.tar.xz \
        | tar xJ -C "$ff_dir" --strip-components=1
    ln -sf "$ff_dir/bin/ffmpeg" ~/.local/bin/ffmpeg
    ln -sf "$ff_dir/bin/ffprobe" ~/.local/bin/ffprobe
    hash -r
    encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
fi
if [[ "$encoders" == *libx264* ]]; then
    echo "ok  ffmpeg with libx264: $(command -v ffmpeg)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "MISSING ffmpeg with libx264 (needed for MP4). On macOS run: brew install ffmpeg"
else
    echo "MISSING ffmpeg with libx264 (needed for MP4). Install a static build and put it on PATH."
fi

CHROME="${AM_CHROME:-$(find_chrome || true)}"
if [[ ! -x "$CHROME" ]] && command -v npx >/dev/null; then
    echo "Installing a headless Chromium for frame capture (npx playwright install chromium) ..."
    npx -y playwright install chromium >/dev/null
    CHROME=$(find_chrome || true)
fi
[[ -x "$CHROME" ]] && echo "ok  chrome: $CHROME" \
    || echo "MISSING Chrome/Chromium (needed for MP4). Set AM_CHROME, or install Node.js and re-run setup."
command -v node >/dev/null && echo "ok  node: $(node --version)" || echo "MISSING Node.js 22+ (runs the renderer)"

AM="$SKILL_DIR/vendor/am/am.mjs"
[[ -f "$AM" ]] && echo "ok  am CLI (vendored): $AM" || echo "MISSING vendored am CLI: $AM"

detect_hardware
echo "ok  hardware plan: $HW_SUMMARY"
