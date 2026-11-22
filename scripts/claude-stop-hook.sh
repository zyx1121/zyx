#!/bin/bash
# Claude Code Stop hook: tells the zyx island that a session in tmux
# finished its turn, with the session name and the first line of the reply.
# The island opens the tmux tab when the notice is clicked.
#   "Stop": [{"hooks": [{"type": "command", "command": "<repo>/scripts/claude-stop-hook.sh"}]}]
TMUX_BIN=/opt/homebrew/bin/tmux
input=$(cat)
[ -n "$TMUX_PANE" ] || exit 0
active=$("$TMUX_BIN" display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}' 2>/dev/null)
title=$("$TMUX_BIN" show -wqv -t "$TMUX_PANE" @cc_title 2>/dev/null)
url=$(printf '%s' "$input" | PANE="$TMUX_PANE" TITLE="$title" ACTIVE="$active" /usr/bin/python3 -c '
import json, os, sys, urllib.parse
hook = json.load(sys.stdin)
# Still waiting on background work: the session is paused, not done.
if hook.get("background_tasks"):
    sys.exit(0)
lines = [l.strip() for l in (hook.get("last_assistant_message") or "").splitlines() if l.strip()]
query = {"pane": os.environ["PANE"], "title": os.environ["TITLE"],
         "message": lines[0][:160] if lines else "", "active": os.environ["ACTIVE"]}
print("zyx://done?" + urllib.parse.urlencode(query, quote_via=urllib.parse.quote))
') || exit 0
[ -n "$url" ] && open -g "$url"
exit 0
