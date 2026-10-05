---
name: papergit2video
description: Use when the user wants a research paper (PDF, arXiv link, uploaded file), a GitHub repository, or a source-code project explained as a narrated explainer video or an interactive one-page explainer, for example "make a video to understand this paper" or "explain this repo as a video", for any audience level or language.
---

# papergit2video

## Overview

Turns a research paper, a GitHub repository or a source-code project into a narrated, animated explainer MP4, or into an interactive one-page explainer (a single HTML file). You write only a Markdown draft; the bundled `am` CLI draws the diagrams, and local Kokoro TTS voices videos with a male narrator. Nothing about the source leaves the machine.

Self-contained: the CLI is vendored and patched in `vendor/am/` (MIT, see `SOURCE.txt`); no plugin is needed. **Read `draft-format.md` in this skill's directory before writing a draft**: it covers components, `>` narration lines, `[Name]` zoom, page panels and STE rules. When talking to the user, call the outputs "the video" or "the interactive page", never by the tool's name.

## Step 1: Ask four questions first

Before downloading or reading anything, ask these four questions together, in one turn. Use the agent's structured question tool if it has one (`AskUserQuestion` in Claude Code, `AskQuestion` in Cursor); otherwise ask them as one numbered message with the options listed:

| Header | Question | Options |
|---|---|---|
| Language | Narration and on-screen language? | English (American male voice) · Mandarin Chinese (male voice) · Japanese (male voice) |
| Style | Visual style? | 3Blue1Brown dark video (`theme: 3b1b`) · Blueprint video (`theme: blueprint`) · Clean cards video (`theme: shadcn`) · Interactive page: a one-page visual explainer to read and click through, no narration (`template: sheet`) |
| Audience | Audience knowledge level? | Middle school · High school · College · Expert/researcher |
| Output | Where should the video and its files go? | `$PAPER_VIDEO_HOME/<slug>/` (Recommended; default `~/.papergit2video/<slug>/`) · `./papergit2video/<slug>/` in the current directory. "Other" accepts any path. |

Show the resolved paths in the Output options (expand `$PAPER_VIDEO_HOME` and `<slug>`). Skip only the questions the user already answered in the request. If they pick **Interactive page**, the language and audience answers still apply, but there is no voice and Step 4 uses `page` mode.

## Step 2: Get the source

Work dir `W` = the Output folder from Step 1. The source, the draft and every output go there. Run `mkdir -p "$W"`, confirm it is writable, and check `df -h "$W"`: a 10-minute video needs about 1 GB free during export. If the user picked a path under `/tmp`, warn that it may be wiped, and suggest the default instead.

| Source | How to read it |
|---|---|
| arXiv `abs/ID` | Download `https://arxiv.org/pdf/ID`, run `pdftotext paper.pdf plain.txt`, and read the WHOLE text, including result tables and limitations. |
| Local or uploaded PDF | Copy it into the work dir, then read it the same way. If `plain.txt` is nearly empty, the PDF is scanned: ask for a text PDF. |
| GitHub repo URL | `git clone --depth 1 <url> repo`. Read the README, `docs/`, any paper or design PDF in the repo, and the entry points and core modules (the files the README and build config point to). Note the commit hash. Docs newer than a paper win: label which numbers come from where. |
| Local source code | Read it in place, in the same order: README, docs, build or config files, entry points, core modules. |
| Login-only links (SharePoint, Google Drive) | They return 403: ask the user to upload the file into the work dir. |

For code, explain what problem it solves, the architecture and data flow, the key design decisions, and measured results. Do not narrate the code line by line.

## Step 3: Write `<slug>[_zh|_ja].md` for the audience

Save the draft in the work dir. Its file name becomes the MP4 name, so use the slug (for example `clm_paper_zh.md`), not `draft.md`.

| Audience | Include | Avoid |
|---|---|---|
| Middle school | everyday analogies, every term defined, rounded numbers | formulas, jargon |
| High school | analogies plus one simple formula in words | dense tables |
| College | formal definitions, equations in plain notation, method details, a scene on what is new vs prior work | hand-waving |
| Expert | novelty, design choices, ablations, exact numbers, limitations | basics |

**Video** recipe: 11–14 scenes. Hook → problem → prior approaches → core idea → method (one scene each) → results with the source's real numbers → novelty summary → limitations/future work. Each scene has one component (flow, tree, timeline, limits, or table) and 3–6 spoken narration lines. Every number must come from the source. For non-English, the whole draft is in that language (`lang: zh` / `lang: ja`); keep model and benchmark names in English.

**Interactive page** recipe: `template: sheet` (or `doc` for step-by-step reading), `theme: blueprint`, 6–10 panels. Put the conclusion first, in a `callout` and the lead line. The same scene topics become panels, with no `>` lines; the numbers still come only from the source. Name the file `<slug>_page.md`.

## Step 4: Check, then render

```bash
S=<directory containing this SKILL.md>/scripts
W=<the Output folder from Step 1>
bash $S/setup.sh            # once per machine; add --ja for Japanese
bash $S/render.sh check <slug>.md    # seconds; fix every error, STE and [caption] warning, then re-run
bash $S/render.sh full <slug>.md $W   # video: minutes; run it in the background or a long-running terminal
bash $S/render.sh page <slug>_page.md $W   # interactive page: seconds
```

`check` prints the estimated length (`… 558.2s`). `full` prints a `hardware:` line first. Use it for the ETA you give the user:

| `hardware:` line shows | `full` time, as a share of video length |
|---|---|
| TTS cuda, Chrome gpu, h264_nvenc, 8 workers | about 0.6× (T4, 8 vCPU: 10.3 min of video in 6 min) |
| TTS cpu, libx264, 4 workers (no GPU) | about 1× (estimate: the export benchmark ran 2.7× faster than serial) |

## Hardware: CUDA is detected automatically

`scripts/hw.sh` runs on every `full` render and `setup.sh` run, and checks each stage on its own:

| Stage | With a usable NVIDIA GPU | Without one |
|---|---|---|
| Narration (Kokoro, a warm server that loads the model once) | CUDA torch | CPU torch |
| Frame drawing (headless Chrome, parallel workers) | GPU raster via ANGLE EGL, one worker per core | software raster, cores ÷ 2 workers |
| Encoding | `h264_nvenc`, proven by a test encode | `libx264` |

`setup.sh` installs CUDA torch and an NVENC-capable ffmpeg when it finds a GPU. On macOS there is no CUDA, so every stage takes the CPU path; if `setup.sh` reports ffmpeg missing, run `brew install ffmpeg`. The scripts are written for macOS's default bash 3.2 and BSD tools (no `mapfile`, `nproc`, `sha1sum` or GNU-only regex). Overrides: `PAPER_VIDEO_GPU=off` forces CPU, and `AM_EXPORT_WORKERS`, `AM_EXPORT_ENCODER`, `PAPER_VIDEO_TTS_DEVICE` and `AM_CHROME_FLAGS` each override one stage. Unchanged narration lines are cached, so edits re-render faster.

## Step 5: Verify and report

Video: read the `CONTACT_SHEET` PNG and confirm every scene shows its diagram. Report `FINAL_MP4`, duration, and scene list. Say you cannot hear the audio.

Interactive page: read the `SCREENSHOT` PNG and confirm the panels render. Report `PAGE_HTML`; it is one self-contained file that opens in any browser.

## Voices

Defaults: `am_michael` (en), `zm_010` (zh, Kokoro-82M-v1.1-zh), `jm_kumo` (ja). Override with `PAPER_VIDEO_VOICE_EN/_ZH/_JA`, and set speed with `PAPER_VIDEO_SPEED`. Changing a voice wipes the narration cache automatically.

English terms inside Chinese lines go through the English G2P. If a term is misread, add its phonemes to `PHONEME_LEXICON` in `scripts/kokoro_tts.py`. In Chinese narration, write versions as `Qwen 3.5`, not `Qwen3.5-9B`, and write large numbers as words (`3万2千`).

## Common Mistakes

| Mistake | Fix |
|---|---|
| Rendering `full` before `check` passes | A full render costs minutes. Always run `check` first. |
| `hardware:` says cpu on a GPU machine | Run `setup.sh`: it installs CUDA torch and NVENC ffmpeg. |
| `[Name]` in narration doesn't match a node label | The camera won't zoom. Copy the label exactly. |
| Inventing illustrative numbers | Use only numbers from the source, or say "illustrative" on screen. |
| Passive voice or long sentences | STE warnings. Rewrite as active voice and short sentences. |
| `[caption]` warning from `check` | That beat's subtitle would wrap to 3 lines and cover the diagram. Split it into two `>` lines. |
| Robotic voice or English voice on Chinese text | `bin/espeak-ng` is not first on PATH. Use `render.sh`, not raw `am`. |
