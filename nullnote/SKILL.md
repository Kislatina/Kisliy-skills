---
name: nullnote
description: Author .nn (NullNote) files — interactive documents that extend Markdown with callouts, charts, diagrams, data blocks and buttons that run real shell commands. Use when the user asks for a .nn file, a NullNote document, an interactive report, or output “in nn format”.
---

# Writing NullNote `.nn` files

A `.nn` file is a plain-text UTF-8 document: optional YAML frontmatter + extended
Markdown. The NullNote desktop app renders it as a live document — charts,
diagrams, data blocks and buttons that run real shell commands.

Write the document **in the user's language**. Save it with the `.nn` extension.
The app auto-saves and live-reloads, so a file you rewrite on disk updates in
place in an open window.

## Frontmatter (optional, recommended)

```yaml
---
nn: 2                  # format version
title: Document title  # rendered as H1 and window title
font: sans             # sans | serif | mono | rounded
width: normal          # normal | wide | full
---
```

Light/dark is an app-level setting — `theme:` in the file is ignored. So is
`accent:`: the palette is strictly monochrome, colour carries meaning only in
status tones (ok / warn / danger / info).

## Core Markdown

All standard Markdown works: headings, bold/italic/strike, GFM tables, lists,
quotes, links, images, fenced code. Raw HTML is stripped — never use it.

- Highlight: `==text==`
- Attributes: `[span]{.class}` inline, `{.class}` at the end of a block line.
  Utility classes: `.muted .big .small`,
  `.serif .mono`, `.center .right`, `.badge`, `.kbd`, `.box`.
- Task lists `- [ ]` / `- [x]` — checkboxes write back into the file.
- Footnotes `[^1]` plus `[^1]: text`; math `$E = mc^2$` and `$$…$$` — a
  ` ```math ` block does the same for a display formula and takes a caption in
  the fence line.

## Two ways to write every block

Most blocks accept a **simple row form** (`A | B | C`, one item per line) and a
**YAML form**. Prefer the simple form — it is shorter and easier to get right.
In YAML values, quote any string containing `: `.

## Containers

```
::: tip Optional title
Any markdown inside.
:::
```

Callout types: `info`, `tip`, `success`, `warn`, `danger`, `note`.
Collapsible: `::: details Title` … `:::`.
Columns (outer container uses FOUR colons):

```
:::: columns
::: col
left
:::
::: col
right
:::
::::
```

## Action buttons

Clicking runs the command through `/bin/zsh -lc` on the user's machine and shows
stdout/stderr and the exit code under the button. Prefer the one-line form:

```
@[Run tests](npm test)
@[Open report](open coverage/index.html) {cwd=~/project noconfirm ghost icon=chart}
```

Options inside `{}`: `cwd=path`, `icon=name`, `desc="explanation"`,
`confirm=false`, flags `danger`, `ghost`, `noconfirm`. The YAML form
` ```nn:button ` (label/command/cwd/confirm/icon/variant/description) exists for
complex cases.

Buttons must be honest: the label and description must match what the command
does. Destructive commands get `variant: danger` and never `confirm: false`.

## Code

A normal fenced block gets highlighting, a language label, line numbers and a
copy button. Fence options: `title=src/app.ts`, `lines` / `nolines`, `hl=3-5,8`,
`fold`, `wrap`, and `run` (bash/sh/zsh only — adds an execute button).

Show code changes as a diff, never as two code blocks to compare by eye:

````
```diff src/app.ts
@@ -1,3 +1,3 @@
 const port = 3000;
-app.listen(port);
+app.listen(port, () => console.log("ready"));
```
````

Full `git diff` output is understood as-is. With two versions instead of a patch:

````
```nn:diff
file: config.json
mode: split          # unified | split
before: |
  { "debug": true }
after: |
  { "debug": false }
```
````

Other code-shaped blocks:

````
```terminal title=zsh
$ npm test
✓ 42 passed
```

```log build.log
12:04:31 INFO server started
12:04:32 WARN slow query 240ms
12:04:33 ERROR connection refused
```

```nn:json
{ "name": "nullnote", "blocks": ["code", "diff"] }
```

```api
method: POST
path: /v1/documents
desc: Create a document
auth: Bearer token
params:
  - title | string | required | Document title
  - body  | string | optional | Markdown source
status: [201, 400, 401]
```
````

`log` recognises TRACE/DEBUG/INFO/WARN/ERROR/FATAL and counts them in the header.
`api` also takes a compact list: `GET | /v1/documents | List documents`.

## Charts

Prefer the simple table form: fence language `chart <type> <title>`, body lines
`Label | value [| value2 …]`, with an optional leading `| Series1 | Series2`
line naming the series.

````
```chart bar Tokens per day
| Input | Output
Mon | 12 | 30
Tue | 18 | 41
```

```chart area stacked Load
| API | Web
Mon | 40 | 20
Tue | 55 | 32
```

```chart hbar Top endpoints
/v1/documents | 1240
/v1/search | 830
```

```chart radar Profile
| Current | Target
Speed | 7 | 9
Docs | 5 | 8
Tests | 8 | 9
UX | 6 | 9
```

```chart donut Share
A | 60
B | 40
```
````

Types: `bar`, `hbar`, `line`, `area`, `scatter`, `radar`, `donut` (default
`bar`). Add the `stacked` flag to `bar` and `area`. The YAML form ` ```nn:chart `
(type/title/labels/series/data/colors/height/stacked/connect) is for colors and
height.

`bar`, `line`, `area`, `scatter` and `radar` are readable under the pointer:
a guide snaps to the nearest category and each series shows its value there,
so a chart can carry more points than its axis labels do. `scatter` joins its
points with a thin line — set `connect: false` in the YAML form to turn that off.

Mermaid diagrams: a fenced block with language `mermaid` (flowchart,
sequenceDiagram, pie, gantt…). The theme matches the document automatically.

## Data blocks

````
```stats
Revenue | 1.2M | +12% | vs last month
Errors | 12 | -40%
```

```big
99.98% | Uptime | +0.4 | last 30 days
```

```progress
Frontend | 80
Backend | 45
```

```gauge
CPU | 72 | %
Memory | 45 | %
```

```table sort search total
Service | Requests | Status
API | 1240 | ok
Web | 830 | ok
```

```heatmap
| Mon | Tue | Wed
API | 12 | 40 | 8
Web | 3 | 22 | 51
```

```activity Commits
2026-08-03 | 4
2026-08-04 | 9
2026-08-11 | 7
```

```matrix
| Free | Pro | Team
Documents | ✓ | ✓ | ✓
Command buttons | ✗ | ✓ | ✓
Shared workspace | ✗ | ~ | ✓
```

```waterfall unit=s
install | 0 | 12.4
build | 12.4 | 48.2
test | 48.2 | 71 | warn
```

```rating
Performance | 4.5
Documentation | 3
```

```kv
Version: 1.4.0
Tags: [docs, live]
```
````

- `stats` deltas starting with `+`/`-` are colored; the YAML form takes
  `items: [{label, value, delta, hint, spark}]` for a sparkline.
- `heatmap` and `activity` shade cells by value; `activity` wants ISO dates.
- `matrix` turns `✓ ✗ ~` into icons; anything else stays as text.
- `waterfall` takes `Label | start | end | status` and draws a shared timeline —
  ideal for build, CI and request traces.

````
```funnel Signup funnel
Visits | 12400
Signups | 3100
Paid | 240
```

```tests Test run
parser | 24 | 0 | 0 | 120 ms
renderer | 18 | 1 | 0 | 340 ms
```

```deps Runtime
tauri | 2.11.5 | MIT | window, filesystem, dialogs
markdown-it | 14.1.0 | MIT | parser
```

```env
NN_HOME | ~/Documents/NullNote | Where documents live
NN_TOKEN | sk-live-91f4c2d8 | secret | API key
```

```swatches Brand
Ink | #101013 | Text and glyphs
Accent | #0a84ff | Links and focus
```

```pros
+ One file, nothing to install
+ Works offline
- No live collaboration yet
```

```pricing
Free | $0 | forever | 3 documents; Local files
Pro | $8 | per month | Unlimited; Sync | featured
```
````

- `funnel` shows each step's share of the top and the drop from the previous one.
- `tests` takes `suite | passed | failed | skipped | time` and prints a verdict.
- `env` masks a row marked `secret`, showing only its tail; clicking a value
  copies it. `swatches` copies the colour code the same way.
- `pros` reads `+`/`-` lines into two columns; column titles come from
  `pros=` and `cons=` in the fence line.
- `pricing` splits features on `;`; a final `featured` marks the highlighted plan.

## Structure blocks

````
```steps
Install | npm install
Run | npm run dev
```

```timeline
12 Mar | Kickoff | Team assembled
28 Mar | Beta | First release | active
```

```changelog
- version: 1.2.0
  date: 2026-08-12
  tag: minor
  changes:
    - Tabs and FAQ blocks
    - Radar and area charts
```

```tabs
Overview | What the project does.
Install | Run **npm install** and start the app.
```

```faq
What is a .nn file? | Plain text: frontmatter plus extended Markdown.
Can buttons run commands? | Yes — every run asks for confirmation first.
```

```checklist Release
[x] Parser | done
[ ] Editor
[ ] Docs
```

```cards
rocket | Ship | Release notes and build status
shield | Secure | Every command asks first
```

```people
Anna Ivanova | Frontend | anna@example.com
Boris Petrov | Backend | boris@example.com
```

```kanban
Todo | Write docs
Done | Diff viewer
```

```tree
src/
  main.ts   # entry point
README.md
```

```terms
.nn | NullNote document format
block | Top-level unit of a document
```

```badges
build | passing | ok
coverage | 92% | warn
```

```keys
⌘ S | Save the document
⌘ E | Toggle editing
```

```quote
A document that can act beats one that only describes.
— NullNote
```

```toc Contents
depth: 2
```

```flow How a document travels
Write | Agent produces .nn | wand
Open | NullNote renders it | file | active
Act | Buttons run commands | play
```

```gantt Release plan
Design | 2026-03-02 | 2026-03-13 | done
Build | 2026-03-10 | 2026-04-03 | active
Beta | 2026-04-06 | 2026-04-24 | risk
```

```calendar 2026-04
3 | Design freeze | done
10 | Feature freeze | active
27 | Launch
```

```chat Support thread
system | Session started
You | How do I export this to PDF?
Agent | Press **⌘P** and pick *Save as PDF*.
```

```refs Sources
Tauri v2 documentation | https://tauri.app/start | the runtime
markdown-it | https://github.com/markdown-it/markdown-it
```
````

`checklist` checkboxes are interactive and write back into the file, same as
task lists. `badges` tones: `ok`, `warn`, `fail`, `info`, `new`, `beta`.

- `flow` chains stages left to right with arrows; statuses `done` / `active`.
- `gantt` needs ISO dates (`YYYY-MM-DD`); statuses `done` / `active` / `risk`.
  Today is drawn as a thin line when it falls inside the range.
- `calendar` takes the month from the fence line (` ```calendar 2026-04 `) and
  a day number or full date per row.
- `chat` puts `You` on the right, `system` in the middle, anything else on
  the left — good for prompt logs and support threads.

## Media

Media comes as one-liners. Paths resolve next to the document, so reference
files that actually exist (`./shot.png`); a missing file renders as a
"File not found" note.

```
@img[Caption](./photo.jpg) {w=70% frame}
@video[Caption](./clip.mp4) {loop muted}
@audio[Track](./episode.mp3)
@link[Title](https://…) {desc="Short description"}
@embed[](https://youtu.be/ID)
@file[Report](./report.pdf)
```

Several files at once, and a before/after wipe:

````
```gallery columns=3
./before.png | Before the redesign
./after.png | After
./detail.png | Toolbar detail
```

```compare
./before.png | ./after.png | Before | After
```
````

- `gallery` takes `path | caption` per row, mixes images and video, and opens
  a lightbox on click; the fence line accepts `columns=` and `height=`.
- `compare` wipes between two images with a slider; `start=30` sets where the
  handle starts.

## Icons

Blocks with an icon field (`cards`, `timeline`, `tabs`, `people`, `big`,
buttons) accept a **name** from the built-in monoline set, and fall back to
drawing any emoji or character as text. Useful names:

`check x info warn danger tip sparkle star heart flag clock timer calendar
rocket flame zap target award shield lock key eye bug wrench settings sliders
file folder code terminal database server cloud globe cpu wifi package layers
git branch chart line pie gauge activity trending table list grid columns
user users message mail quote book bookmark tag home building play image video
music mic camera download upload copy trash edit search filter link pin
keyboard robot brain wand coffee gift scale percent hash power`

Prefer names over emoji: they match the document's typography and theme.

## Reader notes — ` ```nn:note `

The reader can pin a note to any element right in the app. It is written into
the file as a fenced block **directly after the element it comments on**, so
you read it in place, together with what it is about:

````
```stats
Revenue | 1.24M | +12%
```

```nn:note by="Vlad" at=2026-08-19T21:04:00+03:00 ai
Check the March numbers — the CRM shows a different revenue.
```
````

Fence keys: `by=` author, `at=` ISO 8601 timestamp, and the flag `ai`
(same as `to=ai`).

**The `ai` flag means the note is addressed to you.** When you open or edit
a `.nn` file, scan it for `nn:note` blocks and treat every `ai` one as an
instruction about the block above it. Then:

- do what it asks, editing the document as needed;
- reply with a note of your own right after it, signed with your name
  (` ```nn:note by=claude at=<now> `) — short, concrete, what you changed;
- clear the request: either delete the note you fulfilled, or drop its `ai`
  flag so it stops asking. Never rewrite the human's text.

A note placed before the first block is about the whole document. Notes
without the `ai` flag are the reader's own memory — leave them alone.

You can also leave notes yourself: use one when a remark belongs to a specific
block but does not belong in the document text.

## Authoring rules

- Lead with a short intro, then use callouts for key facts, tables and charts
  for data, and buttons for every action the reader would otherwise run by hand.
- One idea per block. Don't nest `nn:*` blocks more than one level deep.
- Charts, stats and tables need real numbers you actually have — never invent data.
- The app also opens plain `.md` and converts it to `.nn` on request, so an
  existing README can become a live document instead of being rewritten.

## Minimal complete example

````
---
nn: 2
title: Build report
---

Build **passed** [ok]{.badge}.

::: success
All 42 tests green.
:::

```chart line Build time, s
| CI
Mon | 130
Tue | 118
Wed | 95
```

```waterfall unit=s
install | 0 | 12.4
build | 12.4 | 48.2
test | 48.2 | 71
```

@[Open coverage report](open coverage/index.html) {cwd=~/project}
````

<!-- nullnote-skill v2.1 -->