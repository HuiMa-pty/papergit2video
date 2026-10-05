"""Kokoro narration for `am video`, used by tts_server.py and as an espeak-ng-compatible CLI.

`am video` calls `espeak-ng -v cmn` for Chinese lines, `-v ja` for Japanese and `-v en-us`
otherwise. Kokoro is a local neural TTS, so narration never leaves the machine. It runs on
CUDA when torch sees a GPU (PAPER_VIDEO_TTS_DEVICE=cpu|cuda overrides), else on the CPU.

Chinese uses the dedicated Kokoro-82M-v1.1-zh model. The base model's Chinese path skips
English entirely (CLM, GRPO, FLOPs reach the acoustic model as raw Latin letters and get
mumbled) and has no tone sandhi, which makes speech choppy. v1.1-zh adds a proper Chinese
frontend and routes embedded English through the English G2P below.

Voices are overridable with PAPER_VIDEO_VOICE_EN / _ZH / _JA and PAPER_VIDEO_SPEED.
"""

import argparse
import os
import re
from collections.abc import Callable
from functools import cache
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from kokoro import KPipeline

BASE_REPO = "hexgrad/Kokoro-82M"
ZH_REPO = "hexgrad/Kokoro-82M-v1.1-zh"
SAMPLE_RATE = 24000
# Breath between sentences inside one narration line; Kokoro returns one chunk per sentence.
SENTENCE_PAUSE_S = 0.12

EN_VOICE = os.environ.get("PAPER_VIDEO_VOICE_EN", "am_michael")
ZH_VOICE = os.environ.get("PAPER_VIDEO_VOICE_ZH", "zm_010")
JA_VOICE = os.environ.get("PAPER_VIDEO_VOICE_JA", "jm_kumo")
SPEED = float(os.environ.get("PAPER_VIDEO_SPEED", "1.0"))

# Terms the English G2P gets wrong. Values are misaki phonemes, used verbatim.
PHONEME_LEXICON = {
    "Qwen": "kwˈɛn",
    "PFLOPs": "pˈi flˈɑps",
    "PFLOP": "pˈi flˈɑp",
}

CJK = r"一-鿿　-〿＀-￯"


def tts_device() -> str:
    """Pick the torch device: CUDA when available, unless PAPER_VIDEO_TTS_DEVICE overrides."""
    requested = os.environ.get("PAPER_VIDEO_TTS_DEVICE", "auto")
    if requested != "auto":
        return requested
    return "cuda" if torch.cuda.is_available() else "cpu"


def normalize_chinese(text: str) -> str:
    """Remove artifacts that make Chinese TTS pause or misread.

    Spaces next to Chinese characters or digits ("3 万 2 千") become audible pauses, and a
    hyphen between alphanumerics ("Qwen3.5-9B") is read as 减/负 (minus).
    """
    text = re.sub(rf"(?<=[{CJK}0-9])\s+(?=[{CJK}0-9])", "", text)
    text = re.sub(rf"(?<=[{CJK}])\s+|\s+(?=[{CJK}])", "", text)
    return re.sub(r"(?<=[A-Za-z0-9])-(?=[A-Za-z0-9])", " ", text)


def make_en_callable(en_g2p: KPipeline) -> Callable[[str], str]:
    """English phonemizer for words embedded in Chinese/Japanese lines, with lexicon overrides."""

    def en_callable(run: str) -> str:
        return " ".join(
            PHONEME_LEXICON.get(word) or next(en_g2p(word)).phonemes for word in run.split()
        )

    return en_callable


def zh_speed(len_ps: int) -> float:
    """Slow down long phoneme runs slightly, as in the v1.1-zh reference usage, so long
    sentences don't sound rushed."""
    if len_ps <= 83:
        speed = 1.0
    elif len_ps < 183:
        speed = 1.0 - (len_ps - 83) / 500
    else:
        speed = 0.8
    return speed * 1.1 * SPEED


@cache
def pipeline_for(lang: str) -> KPipeline:
    """Build (once per process) the Kokoro pipeline for an espeak language code."""
    device = tts_device()
    if lang == "cmn":
        en_g2p = KPipeline(lang_code="a", repo_id=ZH_REPO, model=False)
        return KPipeline(
            lang_code="z", repo_id=ZH_REPO, en_callable=make_en_callable(en_g2p), device=device
        )
    if lang == "ja":
        en_g2p = KPipeline(lang_code="a", repo_id=BASE_REPO, model=False)
        return KPipeline(
            lang_code="j", repo_id=BASE_REPO, en_callable=make_en_callable(en_g2p), device=device
        )
    return KPipeline(lang_code="a", repo_id=BASE_REPO, device=device)


def synthesize(lang: str, text: str) -> np.ndarray:
    """Return float32 audio for one narration line."""
    pipeline = pipeline_for(lang if lang in ("cmn", "ja") else "en-us")
    if lang == "cmn":
        results = pipeline(normalize_chinese(text), voice=ZH_VOICE, speed=zh_speed)
    elif lang == "ja":
        results = pipeline(text, voice=JA_VOICE, speed=SPEED)
    else:
        results = pipeline(text, voice=EN_VOICE, speed=SPEED)

    pause = np.zeros(int(SAMPLE_RATE * SENTENCE_PAUSE_S), dtype=np.float32)
    chunks: list[np.ndarray] = []
    for result in results:
        if result.audio is None:
            continue
        if chunks:
            chunks.append(pause)
        chunks.append(result.audio.cpu().numpy())
    # An empty line still needs a valid WAV, or `am` aborts the whole render.
    return np.concatenate(chunks) if chunks else np.zeros(SAMPLE_RATE // 4, dtype=np.float32)


def write_wav(lang: str, text: str, out_path: str) -> None:
    """Synthesize one line and write it as a 16-bit PCM WAV."""
    sf.write(out_path, synthesize(lang, text), SAMPLE_RATE, subtype="PCM_16")


def main() -> None:
    """espeak-ng-compatible CLI: `-v <lang> -w <out.wav> -f <text.txt>`."""
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", default="en-us")
    parser.add_argument("-w", required=True)
    parser.add_argument("-f", required=True)
    args = parser.parse_args()
    write_wav(args.v, Path(args.f).read_text(encoding="utf-8").strip(), args.w)


if __name__ == "__main__":
    main()
