#!/usr/bin/env bash
# Hardware detection, sourced by render.sh and setup.sh. Sets and exports:
#   PAPER_VIDEO_TTS_DEVICE  cuda | cpu   (Kokoro)
#   AM_EXPORT_ENCODER       h264_nvenc | libx264
#   AM_EXPORT_WORKERS       parallel Chrome+ffmpeg export workers
#   AM_CHROME_FLAGS         GPU raster flags for headless Chrome on CUDA machines
#   HW_SUMMARY              one human-readable line
# PAPER_VIDEO_GPU=off forces the CPU path. Explicitly set variables are respected.

detect_hardware() {
    local venv_py="$PAPER_VIDEO_HOME/tts/.venv/bin/python"
    local cores gpu_name="" cuda=0
    cores=$(nproc)

    if [[ "${PAPER_VIDEO_GPU:-auto}" != "off" ]] && nvidia-smi -L >/dev/null 2>&1; then
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        cuda=1
    fi

    # Kokoro: CUDA only if this venv's torch was built with CUDA and sees the GPU.
    if [[ -z "${PAPER_VIDEO_TTS_DEVICE:-}" ]]; then
        PAPER_VIDEO_TTS_DEVICE=cpu
        if (( cuda )) && "$venv_py" -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
            PAPER_VIDEO_TTS_DEVICE=cuda
        fi
    fi

    # NVENC: listed by ffmpeg is not enough (driver or session limits can still refuse), so
    # encode a tiny clip to prove it works.
    if [[ -z "${AM_EXPORT_ENCODER:-}" ]]; then
        AM_EXPORT_ENCODER=libx264
        if (( cuda )) && ffmpeg -hide_banner -loglevel error -f lavfi -i color=size=320x240:duration=0.2 \
            -c:v h264_nvenc -f null - >/dev/null 2>&1; then
            AM_EXPORT_ENCODER=h264_nvenc
        fi
    fi

    # Chrome draws frames on the GPU through ANGLE's EGL backend (measured faster than Vulkan
    # on a T4, frames within 51 dB PSNR of CPU drawing). Without a usable GPU Chrome silently
    # falls back to software drawing, so these flags are safe to pass.
    if (( cuda )) && [[ -z "${AM_CHROME_FLAGS+set}" ]]; then
        AM_CHROME_FLAGS="--enable-gpu --ignore-gpu-blocklist --use-gl=angle --use-angle=gl-egl --enable-gpu-rasterization"
    fi

    # Workers: GPU drawing + NVENC leave the CPU only screenshot plumbing, so one worker per
    # core pays (T4, 8 cores: 6 -> 74 s, 8 -> 69 s, 10 -> 66 s); x264 needs CPU per worker.
    if [[ -z "${AM_EXPORT_WORKERS:-}" ]]; then
        if [[ -n "${AM_CHROME_FLAGS:-}" && "$AM_EXPORT_ENCODER" == "h264_nvenc" ]]; then
            AM_EXPORT_WORKERS=$cores
        elif [[ "$AM_EXPORT_ENCODER" == "h264_nvenc" ]]; then
            AM_EXPORT_WORKERS=$(( cores * 3 / 4 ))
        else
            AM_EXPORT_WORKERS=$(( cores / 2 ))
        fi
        (( AM_EXPORT_WORKERS < 1 )) && AM_EXPORT_WORKERS=1
        (( AM_EXPORT_WORKERS > 12 )) && AM_EXPORT_WORKERS=12
    fi

    export PAPER_VIDEO_TTS_DEVICE AM_EXPORT_ENCODER AM_EXPORT_WORKERS AM_CHROME_FLAGS
    HW_SUMMARY="GPU: ${gpu_name:-none} | TTS: $PAPER_VIDEO_TTS_DEVICE | Chrome drawing: $([[ -n "${AM_CHROME_FLAGS:-}" ]] && echo gpu || echo cpu) | encoder: $AM_EXPORT_ENCODER | export workers: $AM_EXPORT_WORKERS of $cores cores"
    export HW_SUMMARY
}
