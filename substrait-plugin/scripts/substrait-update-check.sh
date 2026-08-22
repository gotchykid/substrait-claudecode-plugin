#!/usr/bin/env bash
# SessionStart hook for the `substrait` plugin: userConfig relay + notify-only update check.
#
# Two jobs, in order:
#   1. Mirror the plugin's `portal_url` userConfig answer into a sidecar file the link/deploy
#      scripts can read. Claude Code exports userConfig answers to HOOK processes only (as
#      $CLAUDE_PLUGIN_OPTION_<KEY>), not to the Bash tool that runs those scripts, so this
#      hook is the one place that sees the value. Runs before the 24h throttle below, so a
#      changed answer takes effect on the very next session.
#   2. The update check.
#
# Once per 24h (throttled, fail-silent) it asks GitHub whether a newer version of
# the bundled substrait-app skill has been published, and if so emits a one-line
# nudge to run `claude plugin update substrait@substrait` (the /plugin slash command ignores
# arguments — it only opens the plugin manager UI). It NEVER mutates the plugin's
# files — applying the update is the user's action, so this can't race the
# plugin manager. Any network/parse error exits 0 so it never blocks a session.
#
# Version source of truth is the PLUGIN RELEASE version in .claude-plugin/plugin.json
# (a sortable UTC stamp, e.g. 2026.08.13.053251) — bumped on ANY plugin change
# (commands, scripts, skill, hooks); publish-plugin.sh refuses to publish without it.
# The skill's own SKILL.md `version:` is the SCAFFOLD version (it drives the
# platform's scaffold-staleness surfacing) and is only used here as a fallback when
# either side predates the plugin.json version field.
#
# To disable: the user removes/disables the substrait plugin's SessionStart hook.
set -u

# The installed plugin root (Claude Code sets CLAUDE_PLUGIN_ROOT; fall back to our path).
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
[ -n "$ROOT" ] || exit 0
LOCAL_SKILL="$ROOT/skills/substrait-app/SKILL.md"
LOCAL_MANIFEST="$ROOT/.claude-plugin/plugin.json"
[ -f "$LOCAL_SKILL" ] || exit 0

# ── 1. Relay the portal_url userConfig answer ───────────────────────────────────
# Write only on change (no mtime churn), and only into the plugin's own directory — never
# the user's ~/.substrait/config.json, which holds their personal access token. Fail-silent:
# a read-only plugin dir must not break the session.
SIDECAR="$ROOT/.portal-url"
opt_portal="${CLAUDE_PLUGIN_OPTION_PORTAL_URL:-}"
if [ -n "$opt_portal" ]; then
  if [ "$(cat "$SIDECAR" 2>/dev/null)" != "$opt_portal" ]; then
    printf '%s\n' "$opt_portal" > "$SIDECAR" 2>/dev/null || true
  fi
elif [ -f "$SIDECAR" ]; then
  # The option was cleared — drop the stale value rather than pinning a dead portal.
  rm -f "$SIDECAR" 2>/dev/null || true
fi

# ── 2. Update check ─────────────────────────────────────────────────────────────
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
_plugin_version() {  # reads plugin.json "version" from stdin (flat, server-controlled)
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

RAW_BASE="https://raw.githubusercontent.com/substrait-build/substrait-claudecode-plugin/main/substrait-plugin"

# Prefer the plugin release version; fall back to the skill (scaffold) version when
# either side predates the plugin.json version field.
local_ver=""; [ -f "$LOCAL_MANIFEST" ] && local_ver="$(_plugin_version < "$LOCAL_MANIFEST")"
remote_ver="$(curl -fsS --max-time 5 "$RAW_BASE/.claude-plugin/plugin.json" 2>/dev/null | _plugin_version)"
if [ -z "$local_ver" ] || [ -z "$remote_ver" ]; then
  local_ver="$(_skill_version < "$LOCAL_SKILL")"
  remote_ver="$(curl -fsS --max-time 5 "$RAW_BASE/skills/substrait-app/SKILL.md" 2>/dev/null | _skill_version)"
fi
[ -n "$local_ver" ] || exit 0
[ -n "$remote_ver" ] || exit 0

# Nothing to do if already current.
[ "$remote_ver" != "$local_ver" ] || exit 0
# Upgrade-only: skip unless remote sorts strictly after local (zero-padded stamps).
greater="$(printf '%s\n%s\n' "$local_ver" "$remote_ver" | sort | tail -1)"
[ "$greater" = "$remote_ver" ] || exit 0

# Does THIS project carry its own project/local-scope install? It matters because
# `claude plugin update` defaults to --scope user, so a project-scope copy (the shape every
# scaffold produced before 2026-08-22, when .claude/settings.json still declared
# enabledPlugins) is invisible to the plain command — the user updates, is told it worked,
# and this project keeps running the old code.
#
# Matched on projectPath, NOT installPath: once two scopes are on the same version they share
# one cache directory, so the install path cannot tell them apart. Pure awk — no jq or python
# (Git Bash on Windows has neither).
#
# Deliberately never interpolates a path into the message: a Windows path is full of
# backslashes and the JSON below is assembled by printf with no escaping.
REGISTRY="$HOME/.claude/plugins/installed_plugins.json"
HERE="${CLAUDE_PROJECT_DIR:-$PWD}"
scope=""
if [ -f "$REGISTRY" ] && [ -n "$HERE" ]; then
  scope="$(awk -v here="$HERE" '
    /"scope"[[:space:]]*:/ {
      s = $0; sub(/.*"scope"[[:space:]]*:[[:space:]]*"/, "", s); sub(/".*/, "", s)
      cur = s; next
    }
    /"projectPath"[[:space:]]*:/ {
      p = $0; sub(/.*"projectPath"[[:space:]]*:[[:space:]]*"/, "", p); sub(/".*/, "", p)
      if (p == here && (cur == "project" || cur == "local")) { print cur; exit }
    }
  ' "$REGISTRY" 2>/dev/null)"
fi

if [ "$scope" = "project" ] || [ "$scope" = "local" ]; then
  cmd="claude plugin update substrait@substrait --scope $scope"
  where=" This project has its OWN ${scope}-scope copy of the plugin, so the command MUST carry --scope $scope and MUST be run from this project's folder — the plain command updates only the user-scope copy and would silently leave this one behind."
else
  cmd="claude plugin update substrait@substrait"
  where=""
fi

# SessionStart: inject a note so Claude surfaces the nudge to the user. Built with printf
# (no python) — the message has no JSON-special characters that need escaping.
msg="A newer substrait plugin is available ($local_ver -> $remote_ver). Let the user know they can update it by running \`$cmd\` in a terminal (NOT the /plugin slash command — that only opens the plugin manager; in there it's Installed -> substrait -> Update). In the Claude desktop app there is no Update button at all — open the built-in terminal with Ctrl+\` and run it there.$where"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
