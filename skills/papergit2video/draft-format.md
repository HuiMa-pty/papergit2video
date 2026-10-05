# `am video` draft format

Reference for the bundled CLI (`vendor/am/am.mjs`). Full help for any component: `node vendor/am/am.mjs help <component>`.

## Skeleton

````markdown
---
title: Title shown on the opening card
subtitle: One line under the title
theme: blueprint          # blueprint | shadcn | 3b1b
lang: en                  # en | zh | ja (sets UI text, STE rules and the TTS voice)
source: where the facts come from
---
> Opening narration (optional). One `>` line is one beat.

## Scene title
```flow LR
A -> B: label
```
> First narration line. The first diagram step appears with it.
> [B] zooms the camera to node B and highlights it.
````

- `## ` starts a scene. Each scene holds ONE visual (a component, a table or a list) and then 3–6 `>` lines.
- Beat N reveals step N. In flow, sequence and tree, each source line is one step. In timeline, limits, tables and lists, each item or row is one step. When there are more narration lines than steps, the extra lines come first as an intro.
- `[Name]` must match a node or participant label exactly. Nodes with the same name in adjacent scenes animate between positions.

## Components

| Component | Syntax |
|---|---|
| `flow [TB\|LR]` | `A -> B: label`, `A --> B` dashed, `A -> B & C` fan-out, `(rounded)`, `{decision?}`, `[(database)]`, `[text with: colon]`, `*Highlight`, `group Name: A, B`. Only `->` and `-->` work: **no `<-`**. |
| `sequence [num]` | `A -> B: msg`, `B --> A: reply`, `B -> B: self`, `note A: text`, `note A, B: text`, `== phase ==` |
| `tree [list]` | indentation = depth, `Label \| gray note`, `*highlight`. One root with 2–4 children draws an org chart; more children, or `list`, draws an indented list. |
| `timeline [h\|v]` | `When \| Title \| note`, `*When` highlights. More than 6 items are drawn vertically. |
| `limits` | `Label \| value / max \| unit \| note`, or `Label \| max 20 \| unit`. A value above the max is shown in red. |
| Markdown table | Plain pipe table. A status column can use `ok` / `no` / `warn` badges. |

## Style check (STE), applied to narration and labels

- English: descriptive sentences ≤ 25 words, active voice ("X sets the limit", not "X is limited by"), short common words.
- Chinese: ≤ 45 characters per sentence, no filler verbs (进行 / 加以), no more than two 的 in a row.
- Fix every warning `check` prints, then re-run it.

## Interactive one-page explainer (the "Interactive page" style)

The same components, laid out as panels on one web page. There is no narration and no audio.

````markdown
---
template: sheet           # sheet: grid of panels, one-screen overview | doc: single column with a table of contents
theme: blueprint          # blueprint | shadcn (switchable in the page)
title: Page title
subtitle: One line
cols: 3                   # sheet only: grid columns
lang: en
source: where the facts come from
---
Lead: one or two sentences with the core conclusion.

## Core result {span=2 meta="small note top-right"}
```callout ok The answer
Markdown body.
```

## How it works
```flow LR
A -> B: label
```
````

- `## ` starts a panel. Give the densest panels `span=2` (or `rows=2`). Use 6–10 panels; put the conclusion first.
- No `>` narration lines. Write any explanation as normal Markdown under the component.
- Page-only components:
  - `callout <info|ok|warn|err> Title`: a conclusion or warning bar.
  - `kv [cols=2]`: `Key: value` metadata grid, where `* Key: value` takes a full row.
  - `annot`: annotate parts of a sentence (`# heading | note`, `[span]{note}`, `[span]{!red note}`, `> footnote`).
- `doc` suits step-by-step reading. `sheet` suits a dashboard-style overview.
