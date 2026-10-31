#!/bin/sh
# Registers (or with --off removes) the terse-updates hook in ~/.claude/settings.json.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
MODE="${1:-on}"
command -v python3 >/dev/null || {
  echo "python3 not found — add this hook to $SETTINGS by hand:" >&2
  echo "  UserPromptSubmit → command: sh \"$DIR/hook.sh\"" >&2
  exit 0
}
python3 - "$SETTINGS" "$DIR/hook.sh" "$MODE" <<'PY'
import json, os, sys
path, hook, mode = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = f'sh "{hook}"'
data = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
    data = json.loads(txt) if txt else {}
groups = data.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])
# drop any earlier terse-updates entry, wherever it was installed from
for g in groups:
    g["hooks"] = [h for h in g.get("hooks", []) if "terse-updates/hook.sh" not in h.get("command", "")]
groups[:] = [g for g in groups if g.get("hooks")]
if mode != "--off":
    groups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
if not groups:
    del data["hooks"]["UserPromptSubmit"]
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print(("✓ terse-updates on" if mode != "--off" else "✓ terse-updates off") + f" ({path})")
PY
