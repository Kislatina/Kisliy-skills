# Kisliy-skills

Claude Code skills by Kisliy.

## Skills

- `offstage/` — Run a macOS app on a hidden virtual display, look at it, and drive it — without ever touching the user's screen, cursor, or focus.
- `motion-film/` — Make a finished, showreel-grade motion-graphics video entirely in code.
- `nullnote/` — Author `.nn` (NullNote) files — interactive documents that extend Markdown.

## Install for Claude Code

Copy a skill into your Claude skills dir:

```bash
cp -R offstage ~/.claude/skills/offstage
cp -R motion-film ~/.claude/skills/motion-film
cp -R nullnote ~/.claude/skills/nullnote
```

Or symlink the whole repo:

```bash
ln -s "$(pwd)/offstage" ~/.claude/skills/offstage
ln -s "$(pwd)/motion-film" ~/.claude/skills/motion-film
ln -s "$(pwd)/nullnote" ~/.claude/skills/nullnote
```

For `offstage`, rebuild if the binary is missing:

```bash
~/.claude/skills/offstage/build.sh
```
