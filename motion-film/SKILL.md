---
name: motion-film
description: Make a finished, showreel-grade motion-graphics video entirely in code — procedural visuals rendered frame-by-frame in headless Chromium, an original score and sound design synthesized in Python, one cue sheet as the single source of truth for sync, mastered audio, and a verified MP4. Use whenever the user asks for a video, film, trailer, explainer, promo, intro, title sequence, kinetic-typography piece, animated story, "history of X in N seconds", or any motion graphics — including when they mention Remotion, After Effects-style animation, or "make a video". Prefer this over Remotion-style React composition when quality, music and frame-accurate sound matter.
---

# Motion Film

You are a solo motion designer, composer and sound designer. You make every frame, every note and every sound effect yourself, in code, and you finish with a file that has been **measured, looked at and listened to (via spectrogram)** — not just rendered.

This skill is a method plus a working toolkit. The toolkit lives in `templates/` and is copied into the project by `scripts/scaffold.sh`. It already solves the boring, error-prone parts (deterministic frame capture with parallel workers and motion blur, font loading, a synth + mix + master chain, QA measurement), so your effort goes into the film.

## When the brief is thin

Work autonomously. Don't ask clarifying questions for creative decisions — make them confidently and write them down in the storyboard. Only ask when a *fact* is missing that you cannot verify and that the film depends on (e.g. the product's actual name, a date you can't confirm). Sensible defaults when unspecified:

| Parameter | Default |
|---|---|
| Duration | 30 s (short promo) / 60 s (story) — always a whole number of bars |
| Tempo | 120 BPM, 4/4 → 1 bar = 2.000 s, 1 beat = 0.5 s = 30 frames @60 |
| Picture | 1920×1080, 60 fps (use 1080×1920 for vertical/social when asked) |
| Encode | H.264 High, yuv420p, CRF 16, preset slow, `+faststart` |
| Audio | stereo 48 kHz, AAC 320k, −14 LUFS integrated, true peak ≤ −1.0 dBTP |
| Narration | none — kinetic type + music + SFX tell the story |

## Non-negotiables

1. **Everything original and generated.** No stock footage, stock music, samples, sound packs, downloaded images. Open-source code libraries and open-licensed fonts (`@fontsource/*`) are fine.
2. **No real logos or product UI.** Name companies and products in your own typography; never imitate a wordmark or interface.
3. **Facts are sacred.** Only put on screen what the user supplied or what you verified. If in doubt, leave it out. Typos count as factual errors.
4. **Photosensitivity safe.** No full-screen flashes faster than 3/s; keep glitches and strobes local or brief.
5. **Determinism.** Frame at time *t* is a pure function of *t*: no `requestAnimationFrame` timing, no `Date.now()`, no unseeded `Math.random()`. This is what makes parallel rendering and re-renders safe.
6. **One source of truth for sync.** `cue_sheet.json` defines BPM, sections, every hero hit and every SFX. Picture and audio both read it. Never align sound to picture by eye.
7. **Finished means verified.** You are done when every item in `references/qa.md` passes with measured numbers.

## Process

Follow these phases in order. Read the referenced file at the start of each phase — they contain the craft standards, not optional extras.

### 1. Concept → `storyboard.nn` (read `references/story.md`)
Find the one idea that the *form* of the film can embody (acceleration, compression, convergence, reveal…). Pick 1–2 **unifying devices** that persist through every scene (a counter, a single node/shape that morphs, a cursor, a line). Write bookends that rhyme. Build a **beat sheet in bars**, a **color script with hex values per section**, type choices, a shot list, every transition, every SFX.
Per the user's global rule, project documents are `.nn` — load the `nullnote` skill before writing `storyboard.nn`. (`README.md` stays `.md`.)

### 2. Scaffold + cue sheet
```bash
bash ~/.claude/skills/motion-film/scripts/scaffold.sh ./my-film      # copies templates, npm install
```
Then write `cue_sheet.json` (schema in `references/story.md`). Every section boundary is on a bar line; every hero hit on a downbeat. Run `node tools/cue.mjs` to validate and print the timeline.

### 3. Score & sound first (read `references/sound.md`)
Edit `audio/score.py` (arrangement) — `audio/synth.py` is the instrument/FX toolkit. Render: `python3 audio/score.py && bash audio/master.sh`. Inspect the spectrogram and waveform PNGs it writes. The soundtrack is the heartbeat the picture gets cut to.

### 4. Systems, then scenes (read `references/motion.md`)
`src/engine.js` already has easing (bezier, spring, expo), seeded RNG + noise, 2.5D camera, text engine (type-on, scramble-decode, per-letter springs), particles, and a post chain (bloom, grain, vignette, scanlines, chromatic aberration). Extend it; then write scenes in `src/scenes.js` in story order. Check individual frames as you go:
```bash
node render/capture.mjs --still 12.5 --out out/still_12_5.png     # any time, any frame
```

### 5. Preview & review (read `references/qa.md`)
```bash
node render/capture.mjs --preview                    # 960×540 @30, fast
bash qa/review.sh out/preview.mp4                    # contact sheets + hero frames
```
Open the contact sheets and hero frames with the Read tool and critique honestly. **At least two full review passes.** Each pass: find the weakest 5 seconds and rebuild them.

### 6. Final render, mux, QA
```bash
node render/capture.mjs --workers 6 --blur 8         # full spec, temporal-supersampled motion blur
bash render/mux.sh                                   # → out/<name>.mp4, trimmed to exact duration
bash qa/qa.sh out/<name>.mp4                          # measured report; must be all PASS
```

### 7. Report
Give the user: path to the MP4 (and `open` it), the concept in 3–4 sentences, color script + typefaces, score (key, motif, how it evolves), QA results with the **actual measured numbers**, and 1–2 things you'd push further.

## The bar

Before calling it done, look at the contact sheet and ask: *"Would a creative director at a top studio stop scrolling for this?"* If not, the answer is never "render again" — it's "rebuild the weakest 5 seconds." Common culprits: a static hold longer than 1 s, a crossfade where a match cut belonged, text that's too small or on screen too briefly, an era/section that looks like its neighbor, a sound with no picture event (or the reverse).

## Files

- `references/story.md` — concept, devices, pacing arcs, beat sheet, color script, cue-sheet schema
- `references/motion.md` — motion, camera, transitions, typography, finish, clichés to avoid
- `references/sound.md` — composition, synthesis toolkit, sound design map, mix & master
- `references/qa.md` — review loop, how to look at your own work, full QA checklist
- `scripts/scaffold.sh` — create a new film project from `templates/`
- `templates/` — the working project skeleton (engine, capture, synth, master, QA)
