---
name: local-jev
description: A local, offline analogue of TypeSafe's Jev "System One" decision model for Claude Code. Gives you fast typed decisions — pick one option, rate on a rubric, or get the probability that a statement is true — each with per-option probabilities and a confidence number, computed on this Mac by a small local LLM (Ollama) instead of writing prose. Use when a decision point needs a cheap, repeatable, calibrated answer rather than a reasoned essay: routing or classifying many items (tickets, issues, files, logs, commits, messages), triaging or filtering a large batch before spending your own tokens, gating a risky action (is this command/diff/tool call safe?), scoring items against a rubric, deduplicating or tagging, deciding "act now or escalate", getting a second opinion from a different model, or building software that needs a `choice`/`score`/`yes-no` decision. Also use when the user mentions Jev, TypeSafe, System One, decision models, local classifiers, confidence-gated routing, or wants a free/offline/private decision engine.
---

# local-jev — a local decision model (System One) for Claude Code

TypeSafe's **Jev** is not a chat model. It takes a *state* and *typed questions* and
returns typed answers with probabilities and a confidence — no prose, no parsing.
This skill gives you the same shape **locally, for free, privately**: a small LLM
served by Ollama is asked for exactly one label, and the probability distribution
over the labels is read from its first-token logprobs. It answers in ~0.2–0.6 s on
Apple Silicon and the data never leaves the Mac.

You (Claude) stay the reasoner. `jev` is a **reflex**: use it where a gut-check
decision is enough, and escalate to yourself when it is unsure.

## The tool

`~/.claude/skills/local-jev/bin/jev` (Python 3 stdlib only; shown below as `jev`).

```bash
jev doctor                 # is Ollama up, is a model installed, does logprobs work
jev setup                  # one-shot: brew install ollama, start it, pull the default model
jev models                 # the 10 decision models + what fits this Mac
jev pull fast              # download by shortcut: tiny | fast | default | best | guard
```

If `jev doctor` fails, run `jev setup` (it is idempotent; ~5 GB download for the
default). On a Mac with < 12 GB RAM prefer `jev setup --model fast`.

### The three primitives (same as Jev)

```bash
# CHOICE — pick one. Returns choice, probabilities, confidence.
jev choose -q "Which team should handle this?" -o billing -o technical -o account \
  --state "I was charged twice this month" --min-confidence 0.7

# SCORE — rate on ordered levels (lowest first). Returns expected score + confidence.
jev score -q "How frustrated is this customer?" -l calm -l annoyed -l furious --state "$MSG"

# NOUL — probability (0..1) that a statement is true of the state.
jev yesno -s "The message requests a refund" --state "$MSG"
```

State comes from `--state`, `--state-file`, or stdin (strings or JSON). Options may
carry hints: `-o "billing=charges, invoices, refunds"`. Standing rules go in
`--instructions "..."`.

Every call prints JSON. With `--min-confidence X` it adds `"action": "act"|"escalate"`
and exits **3** when it would escalate, so you can branch in shell:
`jev yesno ... --min-confidence 0.8 || echo "ask Claude / a human"`.

### Fan-out: many questions, one state

```bash
cat <<'JSON' | jev ask --min-confidence 0.7
{ "state": {"title": "App crashes on export", "body": "…stack trace…"},
  "questions": [
    {"id": "area",    "type": "choice", "question": "Which area?", "options": ["ui","backend","build","docs"]},
    {"id": "urgency", "type": "score",  "question": "How urgent?", "levels": ["low","medium","high","outage"]},
    {"id": "has_repro","type": "noul",  "question": "Does the report include reproduction steps?"}
  ] }
JSON
```

Break a complex judgment into atomic questions and combine them **in code** with
weights you control (composite scoring); one narrow question per decision is what
makes small models reliable.

### Beyond one model

```bash
jev panel -q "Is this change safe to merge?" -o safe -o unsafe --state-file diff.txt   # 3 models vote
jev choose ... --debias            # also run reversed option order (kills position bias, 2x cost)
jev guard --risk jailbreak --state "$USER_TEXT"   # Granite Guardian: harm, jailbreak, social_bias, violence…
jev think "Why would this deadlock?"              # System-2: DeepSeek-R1 deliberates, prints the answer
jev bench --models qwen3:8b,gemma3:4b,llama3.2:3b # accuracy / calibration / latency on THIS Mac
```

## How to read the output

- `probabilities` — distribution over the options (sums to 1).
- `confidence` — 0 = spread evenly, 1 = certain. Choice uses `(n·pmax − 1)/(n − 1)`;
  score uses distance-from-peak, exactly like TypeSafe's definition. It measures
  **decisiveness, not truth**: a small model can be confidently wrong, so gate with
  a threshold *and* keep a cheap deterministic check for anything irreversible.
- `label_mass` — how much probability sat on valid labels. Under ~0.5 means the
  model ignored the format: treat as `escalate`, try another model.
- Calibration is not trained as in Jev. Run `jev bench` and pick the threshold
  where `accuracy_when_conf>=T` is high enough for the task.

### Lessons measured on this Mac (qwen3:8b, 16-item routing set, `jev bench`)

- **Bare option names are ambiguous.** `billing|technical|account|sales` scored 12/16
  with confidence ≈ 0.99 on the misses — confidently wrong. Adding one-line
  descriptions (`-o "sales=pricing, demos, plans, evaluation"`) plus `--debias`
  scored 16/16. Always describe options whose boundaries overlap.
- **Confidence is overconfident on small models**; never treat 0.99 as "correct".
  Use `jev bench --bare` vs `jev bench --debias` to see the gap, and `jev panel`
  where a wrong call is costly.

## Choosing a model (the ten)

| tier | model | size | use it for |
|---|---|---|---|
| reflex | `llama3.2:3b` (`tiny`) | 2.0 GB | bulk routing/tagging on small Macs |
| reflex | `qwen3:4b-instruct-2507` (`fast`) | 2.5 GB | best accuracy under 3 GB; multilingual |
| reflex | `phi4-mini:3.8b` | 2.5 GB | logic-flavoured yes/no, rubrics, code-adjacent |
| reflex | `gemma3:4b` | 3.4 GB | well-calibrated; second voice in a panel |
| core | `qwen3:8b` (`default`) | 5.2 GB | **default**: accuracy/speed/calibration balance |
| core | `granite3.3:8b` | 4.9 GB | policy checks, extraction-style classification |
| core | `gemma3:12b` | 8.2 GB | nuanced scoring, tone, sentiment |
| core | `qwen3:14b` (`best`) | 9.3 GB | highest single-model accuracy; costly mistakes |
| core | `phi4:14b` | 9.1 GB | reasoning-heavy gates (diff safety, evidence supports claim) |
| specialist | `granite3-guardian:8b` (`guard`) | 5.8 GB | risk detection via `jev guard` |

Companions for `jev think` (slow, thinking): `deepseek-r1:8b`, `deepseek-r1:14b`, `gpt-oss:20b`.
Rule of thumb on 16 GB: default or `fast`, one model resident at a time; on 8 GB:
`tiny`/`fast`; on 32 GB+: `best` and a panel.

## When to use this skill

Use it when the decision is **narrow, repeated, or cheap-to-be-wrong-and-checkable**:

1. **Bulk triage** — classify/tag/route hundreds of files, issues, logs, commits or
   messages; keep your own context for the ones that matter.
2. **Pre-filtering** — "is this file relevant to the task?" before reading it;
   "is this log line an error?" before pasting it.
3. **Gating actions** — is this shell command read-only? does this diff touch
   secrets? is this output safe to send? (`jev hook`, below.)
4. **Rubric scoring** — rank candidates (PRs, copy variants, search hits) on atomic
   scores you combine in code.
5. **Confidence-gated routing** — act when confident, otherwise escalate to you or
   to the user; cascade small → bigger model → `jev think`.
6. **Second opinion** — `jev panel` when you suspect your own bias on a call.
7. **Private data** — contents that must not go to a cloud API.
8. **Building products** — when the code you write needs a typed `choice`/`score`/
   `yes-no`, prototype it locally; swap in TypeSafe's hosted Jev later if you need
   trained calibration (same three primitives).

Do **not** use it for: writing code or prose, multi-step reasoning, anything needing
tool use, long-document understanding beyond a few thousand tokens, or decisions
with no cheap way to catch a confident mistake. There, think for yourself.

## Patterns

**Confidence cascade**
```bash
r=$(jev yesno -s "$CLAIM" --state-file ctx.txt --min-confidence 0.8 --model fast) && echo "$r" \
  || jev yesno -s "$CLAIM" --state-file ctx.txt --min-confidence 0.8 --model best \
  || echo "ESCALATE: decide yourself"
```

**Batch routing** — loop `jev choose` in a shell/Python loop with `--model fast`;
items are independent, the shared instruction prefix is KV-cached by Ollama.

**Atomic composite**
```bash
jev ask < q.json | python3 -c 'import json,sys; r={x["id"]:x for x in json.load(sys.stdin)["results"]}; \
print(0.5*r["impact"]["score"] + 0.3*r["risk"]["score"] + 0.2*r["effort"]["score"])'
```

**Permission gate (opt-in)** — a conservative Claude Code `PreToolUse` hook that
auto-approves only clearly read-only shell commands and flags risky ones; it never
auto-denies, and stays silent if no model is available. Print the snippet and add it
to `~/.claude/settings.json` only if the user asks:
```bash
jev hook --print-config
```

## Operating rules

- Ask one narrow question per decision; give 2–6 options; put the thing being judged
  in `--state`, rules in `--instructions`; name options by meaning, not by letters.
- Keep the state short (< ~2k tokens). Trim logs/diffs first.
- Never let a local-model decision alone authorise something destructive or
  irreversible (deletes, force-push, deploy, sending data out). Use it to *route to
  review*, not to *skip review*.
- Report decisions to the user with the confidence, and say when you escalated.
- First run in a session: `jev doctor`. If Ollama is missing, tell the user what
  `jev setup` will install (Ollama via Homebrew, ~5 GB model) before running it.
- Tuning: `JEV_MODEL` env or `~/.config/local-jev/config.json` sets the default;
  `OLLAMA_HOST` points at a remote box; `JEV_KEEP_ALIVE` (default `30m`) keeps the
  model resident.
