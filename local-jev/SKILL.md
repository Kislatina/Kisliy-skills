---
name: local-jev
description: Run open-weight "decision models" — local analogues of TypeSafe's Jev (System One) — on this Mac and use them for fast, typed, calibrated decisions. A decision model does not write text; in one forward pass it returns a choice (pick one option), a score (rate on a rubric) or a noul (probability a statement is true), each with per-option probabilities and a confidence. Ten ranked models (vLLM-SR d3, Perplexity Decider, Bespoke Nimble, Cloudflare clef-flash, Kev, LiquidAI d1, Laya…) are served through llama.cpp's TypeSafe-compatible /v1/systemone API. Use when a decision point needs a cheap, repeatable, calibrated answer instead of a reasoned essay: routing or classifying many items (tickets, issues, files, logs, commits, messages), triaging or pre-filtering a large batch before spending your own tokens, gating a risky action (is this command/diff/output safe?), scoring items on a rubric, guardrails (jailbreak, PII, secrets), "act now or escalate" confidence gating, a second opinion from another model, or building software that needs choice/score/yes-no decisions. Also use when the user mentions Jev, TypeSafe, System One, decision models, Decision Index, or wants a free/offline/private decision engine.
---

# local-jev — local System One decision models for Claude Code

**What a decision model is.** TypeSafe's **Jev** is not a chat LLM. You send a *state*
(text or JSON) and *typed questions*; one forward pass returns typed answers with
calibrated probabilities. No generated text, nothing to parse, nothing to hallucinate.
An open ecosystem of such models now exists (ranked on the
[Decision Index](https://huggingface.co/spaces/multimodalart/jev-decision-index)),
and llama.cpp serves them via `POST /v1/systemone` — the same API TypeSafe's SDK speaks.
This skill installs the runtime, downloads a model, and gives you a CLI on top.

You (Claude) stay the reasoner. `jev` is a **reflex**: use it where a gut-check
decision is enough, and escalate to yourself when confidence is low.

> Prompting a general LLM (Qwen, Llama, Gemma…) to "answer with one letter" is *not*
> this: such models are confidently wrong (measured: 75 % accurate at 0.998 mean
> confidence). Native decision models are trained for calibrated probabilities.

## Setup (once)

```bash
~/.claude/skills/local-jev/bin/jev setup      # fetch llama.cpp, pick a model for this Mac's RAM, download, start
jev models                                    # the ten models, their Decision Index, what fits
jev doctor                                    # health + self-test
```

`setup` downloads the newest prebuilt llama.cpp into `~/.local/share/local-jev`
(Homebrew's bottle lags and lacks the d3/clef/pplx architectures — run
`jev setup --update` whenever `jev serve` says *unsupported decision model type*).
The server auto-starts on the first decision and keeps one model resident.
Default by RAM: ≥30 GB `d3` (27B), ≥11 GB `d3-flash` (9B), ≥7 GB `d3-mini`, else `d3-nano`.

## The three primitives

```bash
# CHOICE — pick one. choice, probabilities, confidence.
jev choose -q "Which team should handle this?" \
  -o "billing=charges, invoices, refunds" -o "technical=bugs, crashes" -o "sales=pricing, demos" \
  --state "I was charged twice this month" --min-confidence 0.7

# SCORE — rate on ordered levels, lowest first. Expected score + confidence.
jev score -q "How urgent is this?" -l "can wait" -l "this week" -l today -l "right now" --state "$MSG"

# NOUL — probability (0..1) that a statement is true of the state.
jev yesno -s "The message requests a refund" --state "$MSG"
```

State comes from `--state`, `--state-file` or stdin (string or JSON). Add
`--instructions` for standing rules. Output is JSON; with `--min-confidence X` it adds
`"action": "act"|"escalate"` and exits **3** on escalate:
`jev yesno ... --min-confidence 0.8 || echo "decide it yourself"`.

### Many questions, one state (fan-out)

```bash
cat <<'JSON' | jev ask --min-confidence 0.7
{ "state": {"title": "App crashes on export", "body": "…stack trace…"},
  "questions": {
    "area":    {"type": "choice", "instructions": "Which area?", "criteria": {"ui": null, "backend": null, "build": null}},
    "urgency": {"type": "score",  "instructions": "How urgent?", "criteria": ["low","medium","high","outage"]},
    "repro":   {"type": "noul",   "instructions": "Does it include reproduction steps?"}
  } }
JSON
```
This is TypeSafe's native request format (the list form with `"id"` also works).
Questions are answered independently, so adding questions barely costs time and does
not dilute the others. Decompose complex judgments into atomic questions and combine
them **in code** with weights you control.

### More

```bash
jev guard --risk jailbreak --state "$USER_TEXT"   # harm | jailbreak | pii | secrets | toxicity | violence | free text
jev panel -q "Safe to merge?" -o safe -o unsafe --state-file diff.txt   # 3 models vote, one at a time
jev choose ... --model best        # one-off switch (restarts the server on that model)
jev bench --models d3-flash,d3-mini,laya        # accuracy / calibration / latency on THIS Mac
jev serve d3 | jev stop | jev status | jev pull --all
```

## Reading the output

- `probabilities` sum to 1. `confidence` is 0 for a flat distribution, 1 for certain
  (choice: `(n·pmax − 1)/(n − 1)`, same as TypeSafe). Probabilities are scaled with the
  temperature stored in the model file but are **not guaranteed calibrated on your
  data** — run `jev bench`, pick the threshold where `accuracy_when_conf>=0.7` is high
  enough, and keep a deterministic check for anything irreversible.
- Description matters: bare option names are ambiguous. `jev bench --bare` vs default
  shows the gap; give boundaries (`-o "sales=pricing, demos, plans"`).
- Keep the state under a few thousand tokens (server context is 8k; Laya reads 8k but
  truncates long questions). Questions are scored independently; clef-flash/clef
  decide jointly.

## The ten models (Decision Index 0.3, board of 2026-10-06; hosted Jev 1.13 = 60.1)

| key | model | index | size | RAM | license | use it for |
|---|---|---|---|---|---|---|
| `d3` | vLLM-SR d3 27B | **66.3** | 19.4 GB | 32 GB | Apache-2.0 | #1 overall; costly mistakes; images |
| `pplx` | Perplexity Decider v1.1 27B | 62.8 | 19.6 GB | 32 GB | Apache-2.0 | language/retrieval, relevance ranking |
| `d3-flash` | vLLM-SR d3-flash 9B | 55.8 | 6.6 GB | 12 GB | Apache-2.0 | **default for 16 GB**; near-Jev quality |
| `nimble` | Bespoke Nimble v3 9B | 54.7 | 6.3 GB | 12 GB | CC-BY-NC | second 9B opinion (non-commercial only) |
| `d3-mini` | vLLM-SR d3-mini 4B | 52.6 | 3.7 GB | 8 GB | Apache-2.0 | best under 4 GB; 8 GB Macs |
| `clef-flash` | Cloudflare clef-flash 9B | 47.6 (56.1 public) | 6.5 GB | 12 GB | Apache-2.0 | joint multi-question, images |
| `kev-9b` | Kev 9B | 43.3 | 6.4 GB | 12 GB | Apache-2.0 | reference TypeSafe-API behaviour |
| `d1-3b` | LiquidAI d1-3B | 38.9 (49.0 public) | 1.7 GB | 6 GB | LFM Open | always-on reflex, multimodal |
| `d3-nano` | vLLM-SR d3-nano 2B | 38.9 | 2.6 GB | 6 GB | Apache-2.0 | bulk tagging |
| `laya` | Laya 0.4B | 4.4 (routing only) | 0.45 GB | 4 GB | Apache-2.0 | ~30 ms router, 100+ languages |

Larger boards entries (Decider 31B, Darwin-27B, Torchcast 27B…) need CUDA-class
hardware or are not yet supported by llama.cpp; check the board and `jev setup --update`
as support lands. Not all models are equal: pick by `jev bench` on your own data.

## When to use this skill

Use it when the decision is **narrow, repeated, and has a cheap way to catch a mistake**:

1. **Bulk triage** — classify/tag/route hundreds of files, issues, logs, commits, messages.
2. **Pre-filtering** — "is this file relevant?" before reading it; "is this log line an error?".
3. **Gating actions** — is this command read-only? does this diff touch secrets? is this
   output safe to send? (`jev hook`, below.)
4. **Rubric scoring** — rank PRs, copy variants, search hits on atomic scores.
5. **Confidence-gated routing** — act when sure, else escalate to yourself or the user;
   cascade `d3-mini` → `d3-flash` → `d3` → you.
6. **Guardrails** — `jev guard` on user/tool text for prompt injection, PII, secrets.
7. **Second opinion** — `jev panel` when you suspect your own bias.
8. **Private data** — content that must not go to a cloud API.
9. **Building products** — when the code you write needs a typed `choice`/`score`/`noul`:
   prototype against `http://127.0.0.1:9931/v1/systemone` (TypeSafe-compatible), later
   point the TypeSafe SDK at hosted Jev for production calibration, unchanged.

Do **not** use it for writing code or prose, multi-step reasoning, tool use, long-document
understanding, or decisions with no cheap way to catch a confident mistake. Think for yourself.

## Patterns

**Confidence cascade**
```bash
jev yesno -s "$CLAIM" --state-file ctx.txt --model fast --min-confidence 0.8 \
  || jev yesno -s "$CLAIM" --state-file ctx.txt --model default --min-confidence 0.8 \
  || echo "ESCALATE: decide yourself"
```

**Atomic composite** — ask `impact`, `risk`, `effort` as three `score` questions in one
`jev ask`, then combine: `0.5*impact + 0.3*risk + 0.2*effort` in Python.

**Direct HTTP** — the server is plain TypeSafe-style JSON; any language can use it:
`curl localhost:9931/v1/systemone -d '{"state":…,"questions":{…}}'`. Images:
add `"files": ["data:image/png;base64,…"]` and start the server with
`JEV_MMPROJ=1 jev serve d3-flash` (loads the vision projector; models marked images).

**Permission gate (opt-in)** — a conservative PreToolUse hook: auto-approves only plainly
read-only commands, asks on risky ones, never auto-denies, stays silent when the server is
down. Print the snippet and add it to `~/.claude/settings.json` only if the user asks:
`jev hook --print-config`.

## Operating rules

- First use in a session: `jev doctor`. If nothing is installed, tell the user what
  `jev setup` will do (≈20 MB runtime + a 4–7 GB model download, Apache-2.0 unless noted)
  before running it.
- One narrow question per decision; 2–6 options with descriptions; thing judged in
  `--state`, rules in `--instructions`.
- Never let a local-model decision alone authorise something destructive or
  irreversible (deletes, force-push, deploy, sending data out): use it to *route to
  review*, not to *skip review*.
- Tell the user the confidence, and say when you escalated.
- `JEV_MODEL`, `JEV_MMPROJ`, `JEV_PORT`, `JEV_URL` (remote server), `JEV_LLAMA_SERVER`, `JEV_SERVER_ARGS`
  tune it; state lives in `~/.local/state/local-jev`, runtime in `~/.local/share/local-jev`,
  models in the Hugging Face cache (`~/.cache/huggingface/hub`).
