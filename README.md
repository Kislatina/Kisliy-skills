# Kisliy-skills

A collection of [Claude Code](https://code.claude.com/docs/en/skills) skills by Kisliy — GUI automation on macOS, code-generated motion films, and interactive documents.

## Skills

| Skill | What it does | Docs |
|-------|--------------|------|
| [`offstage`](./offstage) | Run a macOS app on a hidden virtual display, screenshot it and drive its UI — without touching your screen, cursor, or focus. | [`offstage/SKILL.md`](./offstage/SKILL.md) |
| [`motion-film`](./motion-film) | Make a finished, showreel-grade motion-graphics video entirely in code — procedural visuals, synthesized score, mastered MP4. | [`motion-film/SKILL.md`](./motion-film/SKILL.md) |
| [`nullnote`](./nullnote) | Author `.nn` (NullNote) files — interactive documents with callouts, charts, diagrams, and buttons that run shell commands. | [`nullnote/SKILL.md`](./nullnote/SKILL.md) |
| [`local-jev`](./local-jev) | Local analogue of TypeSafe's Jev: open decision models (vLLM-SR d3, Perplexity Decider, Clef, Kev, Laya…) serving typed choice / score / yes-no decisions with calibrated probabilities through llama.cpp's `/v1/systemone`. | [`local-jev/SKILL.md`](./local-jev/SKILL.md) |

### offstage

GUI operator for macOS. Creates an off-screen virtual display, launches an isolated copy of the app there, and drives it via screenshots, accessibility tree, clicks, typing, menus, and shortcuts. The real cursor never moves and the front app never changes.

Highlights:

- Hidden virtual display (`CGVirtualDisplay`), parked off-screen
- Isolated launch (APFS clone + own `$HOME`) or `--as-is` mode
- Screenshot, AX tree, click / type / scroll / drag / resize / menus
- Parallel sessions, multi-window warden
- Agent-flagged runs (`OFFSTAGE=1`, `NULL_AGENT=1`)

Requires: macOS (arm64, verified on 26.5), Xcode CLT / Swift toolchain.

### motion-film

Solo motion-designer skill. Every frame, note, and SFX is generated in code — no stock footage, no stock music.

Defaults: 1920×1080 @ 60 fps, H.264 CRF 16, 48 kHz stereo, −14 LUFS. See [`motion-film/SKILL.md`](./motion-film/SKILL.md) for the full method (storyboard → cue sheet → render → QA).

### nullnote

Plain-text `.nn` format: YAML frontmatter + extended Markdown. Rendered live by the NullNote desktop app with auto-save and live-reload.

Supports: callouts, charts, diagrams, data blocks, and buttons that run real shell commands. See [`nullnote/SKILL.md`](./nullnote/SKILL.md).

### local-jev

A local [System One](https://docs.typesafe.ai/concepts/system-one) decision engine. Decision models don't write text: one forward pass returns a typed answer — `choice`, `score` or `noul` — with calibrated probabilities and a confidence, in tens of milliseconds. The skill installs the newest llama.cpp runtime, downloads a model sized for your Mac, and gives Claude Code a CLI (`jev choose | score | yesno | ask | panel | guard | bench | hook`) on top of the TypeSafe-compatible `POST /v1/systemone` API.

Ten ranked models from the [Decision Index](https://huggingface.co/spaces/multimodalart/jev-decision-index): vLLM-SR d3 27B (66.3, above hosted Jev 1.13 at 60.1), Perplexity Decider v1.1 27B, d3-flash 9B (default for 16 GB), Bespoke Nimble v3, d3-mini 4B, Cloudflare clef-flash, Kev 9B, LiquidAI d1-3B, d3-nano, Laya. One-line setup: `jev setup`.

Requires: macOS (arm64/x64) or Linux x64, Python 3.9+. Everything is fetched by `jev setup`.

## Install

Copy the skills you need into your Claude skills dir:

```bash
cp -R offstage ~/.claude/skills/offstage
cp -R motion-film ~/.claude/skills/motion-film
cp -R nullnote ~/.claude/skills/nullnote
cp -R local-jev ~/.claude/skills/local-jev
```

Or symlink them so updates come in with `git pull`:

```bash
ln -s "$(pwd)/offstage" ~/.claude/skills/offstage
ln -s "$(pwd)/motion-film" ~/.claude/skills/motion-film
ln -s "$(pwd)/nullnote" ~/.claude/skills/nullnote
ln -s "$(pwd)/local-jev" ~/.claude/skills/local-jev
```

Rebuild `offstage` if the binary is missing:

```bash
~/.claude/skills/offstage/build.sh
```

Verify:

```bash
ls ~/.claude/skills
```

## Repo layout

```text
Kisliy-skills/
├── offstage/       # skill + Swift tool (see offstage/README.md for maintainers)
├── motion-film/    # skill
├── nullnote/       # skill
├── local-jev/      # skill + `jev` CLI (Python, stdlib only)
├── LICENSE         # MIT
└── README.md
```

## Contributing

Issues and PRs welcome. Keep skills self-contained: `SKILL.md` is the contract, everything else is implementation detail.

## License

[MIT](./LICENSE) — see [LICENSE](./LICENSE) for details.
