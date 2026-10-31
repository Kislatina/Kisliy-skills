---
name: terse-updates
description: Keeps Claude's in-progress status lines between tool calls down to 2-5 words, on by default in every session. A UserPromptSubmit hook injects the rule each turn, so it works without being invoked. Use when the user asks to toggle, tune or explain the short progress updates, or says the running commentary is too long.
---

# terse-updates

The lines Claude writes between tool calls ("Применяю правки: делаю сушу светлее воды, здания темнее…") shrink to **2–5 words** ("Правлю цвета карты."). The final answer is not affected.

## How it is on by default

Skills only load when the model decides to read them, so a skill alone cannot be "always on". `setup.sh` adds a `UserPromptSubmit` hook to `~/.claude/settings.json` that runs `hook.sh`; its output (`rule.txt`) lands in context on every prompt, survives compaction and needs no invocation.

```sh
sh ~/.claude/skills/terse-updates/setup.sh        # turn on (the site installer runs this)
sh ~/.claude/skills/terse-updates/setup.sh --off  # remove the hook
TERSE_UPDATES=0 claude                             # one session without it
```

## The rule (what Claude follows)

- Every status/progress line between tool calls: 2–5 words, one line, no explanation of *why*, no list of details. Examples: «Проверяю исходник.», «Чиню луч.», «Собираю и смотрю.», "Running tests."
- Don't narrate a step at all if the tool call speaks for itself.
- Same language the user writes in.
- Not affected: the final answer at the end of a turn, questions to the user, and warnings about something destructive or failing — those stay as long as they need to be.

## When the user asks about it

- "Too short / I want details" → `setup.sh --off`, or tell them `TERSE_UPDATES=0` for one session.
- Edit `rule.txt` to change the word limit; it is read on every prompt, no restart needed.
