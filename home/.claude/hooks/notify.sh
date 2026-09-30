#!/usr/bin/env bash
# Desktop notification for Claude Code events (Stop / Notification hooks)
input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // "Stop"')
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')

# Session name as shown in the Claude Code job list (~/.claude/sessions/<pid>.json)
session_name() {
  local n
  n=$(cat ~/.claude/sessions/*.json 2>/dev/null \
      | jq -r --arg sid "$sid" 'select(.sessionId==$sid) | .name // empty' 2>/dev/null | head -1)
  [ -n "$n" ] && printf '%s' "$n" || printf '%s' "$(basename "${cwd:-Claude}") · ${sid:0:8}"
}

summarize() {
  printf '%s' "$1" \
    | sed -E 's/^result:[[:space:]]*//; s/^#+[[:space:]]*//; s/[`*_]//g; s/^[-*][[:space:]]+//' \
    | grep -m1 -v '^[[:space:]]*$' \
    | cut -c1-300
}

case "$event" in
  Notification)
    msg=$(printf '%s' "$input" | jq -r '.message // "Claude needs your attention"')
    notify-send -a "Claude Code" -u critical -t 0 "Claude [$(session_name)]" "$msg"
    ;;
  *)
    msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""')
    if [ -z "$msg" ] && [ -r "$transcript" ]; then
      msg=$(jq -r 'select(.type=="assistant") | .message.content
                   | (if type=="array" then map(select(.type=="text")|.text)|join("\n") else . end)' \
            "$transcript" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 20)
      if printf '%s\n' "$msg" | grep -q '^result:'; then
        msg=$(printf '%s\n' "$msg" | grep '^result:' | tail -1)
      else
        msg=$(printf '%s\n' "$msg" | tail -1)
      fi
    fi
    summary=$(summarize "$msg")
    notify-send -a "Claude Code" -u critical -t 0 \
      "Claude [$(session_name)]" "${summary:-Task finished}"
    ;;
esac
exit 0
