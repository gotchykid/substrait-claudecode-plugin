#!/usr/bin/env bash
# SessionStart hook for the `substrait` plugin: notify-only update check.
#
# Once per 24h (throttled, fail-silent) it asks GitHub whether a newer version of
# the bundled substrait-app skill has been published, and if so emits a one-line
# nudge to run `/plugin update substrait`. It NEVER mutates the plugin's files —
# applying the update is the user's `/plugin update`, so this can't race the
# plugin manager. Any network/parse error exits 0 so it never blocks a session.
#
# Version source of truth is the `version:` in skills/substrait-app/SKILL.md
# (a sortable UTC stamp, e.g. 2026.06.23.061341) — the same field publish-plugin.sh
# bumps. We compare the installed copy against the one published in the public repo.
#
# To disable: the user removes/disables the substrait plugin's SessionStart hook.
set -u

# The installed plugin root (Claude Code sets CLAUDE_PLUGIN_ROOT; fall back to our path).
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
[ -n "$ROOT" ] || exit 0
LOCAL_SKILL="$ROOT/skills/substrait-app/SKILL.md"
[ -f "$LOCAL_SKILL" ] || exit 0

STAMP="$ROOT/.last-version-check"

# Throttle: at most one check per 24h.
now="$(date +%s 2>/dev/null)" || exit 0
if [ -f "$STAMP" ]; then
  last="$(cat "$STAMP" 2>/dev/null || echo 0)"
  case "$last" in ""|*[!0-9]*) last=0 ;; esac
  [ "$((now - last))" -ge 86400 ] || exit 0
fi
echo "$now" > "$STAMP" 2>/dev/null || true

_skill_version() {  # reads SKILL.md frontmatter `version:` from stdin
  sed -n 's/^version:[[:space:]]*//p' | head -1 | tr -d '[:space:]'
}

local_ver="$(_skill_version < "$LOCAL_SKILL")"
[ -n "$local_ver" ] || exit 0

# Published SKILL.md in the public distribution repo (short timeout, fail-silent).
RAW="https://raw.githubusercontent.com/gotchykid/substrait-claudecode-plugin/main/substrait-plugin/skills/substrait-app/SKILL.md"
remote_ver="$(curl -fsS --max-time 5 "$RAW" 2>/dev/null | _skill_version)"
[ -n "$remote_ver" ] || exit 0

# Nothing to do if already current.
[ "$remote_ver" != "$local_ver" ] || exit 0
# Upgrade-only: skip unless remote sorts strictly after local (zero-padded stamps).
greater="$(printf '%s\n%s\n' "$local_ver" "$remote_ver" | sort | tail -1)"
[ "$greater" = "$remote_ver" ] || exit 0

# SessionStart: inject a note so Claude surfaces the nudge to the user.
python3 - "$local_ver" "$remote_ver" <<'PY' 2>/dev/null || exit 0
import json, sys
local, remote = sys.argv[1], sys.argv[2]
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": (
        f"A newer substrait plugin is available ({local} -> {remote}). "
        "Let the user know they can update it by running: /plugin update substrait"
    ),
}}))
PY
exit 0
