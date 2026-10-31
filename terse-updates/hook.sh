#!/bin/sh
# UserPromptSubmit hook: stdout is added to Claude's context on every prompt.
[ "${TERSE_UPDATES:-1}" = "0" ] && exit 0
cat "$(dirname "$0")/rule.txt" 2>/dev/null
exit 0
