#!/usr/bin/env bash
# Shared helpers for the Substrait plugin's link/deploy scripts. Sourced, not run —
# so it sets no shell options of its own and never exits the caller.
#
# A deploy token is APP-scoped, so config is PER-PROJECT: it lives in this project's
# .substrait/config.json (gitignored), written by `substrait-link.sh`. Resolution order:
#   portal URL : $SUBSTRAIT_PORTAL_URL  ->  .substrait/config.json "portal_url"
#   token      : $SUBSTRAIT_TOKEN       ->  .substrait/config.json "token"

SUBSTRAIT_CONFIG_FILE="${SUBSTRAIT_CONFIG_FILE:-.substrait/config.json}"

# _json_get FILE KEY -> prints the string value, or exits 1 if absent. Uses python3
# (always present in a Claude Code env) so we need no jq dependency.
_json_get() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        v = json.load(f).get(sys.argv[2])
except Exception:
    sys.exit(1)
if v is None:
    sys.exit(1)
print(v)
PY
}

substrait_portal_url() {
  if [ -n "${SUBSTRAIT_PORTAL_URL:-}" ]; then printf '%s' "${SUBSTRAIT_PORTAL_URL%/}"; return 0; fi
  local v; v="$(_json_get "$SUBSTRAIT_CONFIG_FILE" portal_url)" || return 1
  printf '%s' "${v%/}"
}

substrait_token() {
  if [ -n "${SUBSTRAIT_TOKEN:-}" ]; then printf '%s' "$SUBSTRAIT_TOKEN"; return 0; fi
  _json_get "$SUBSTRAIT_CONFIG_FILE" token
}

# substrait_call METHOD PATH [extra curl args...]
# Performs the request and sets two globals in the CURRENT shell:
#   SUBSTRAIT_BODY    — the response body
#   SUBSTRAIT_STATUS  — the HTTP status code
# Returns 2 if unconfigured, else curl's exit code.
#
# IMPORTANT: call this as a plain statement, e.g.
#       substrait_call GET /api/deploy/app || exit $?
# NEVER inside a command substitution ( x="$(substrait_call ...)" ) — that runs it in a
# subshell, so the globals it sets would not reach the caller. (That was the original bug.)
substrait_call() {
  local method="$1" path="$2"; shift 2
  local base token tmp
  base="$(substrait_portal_url)" || {
    echo "Not linked yet — run /substrait:link to set this project's portal URL and token." >&2; return 2; }
  token="$(substrait_token)" || {
    echo "No deploy token configured — run /substrait:link." >&2; return 2; }
  tmp="$(mktemp)" || return 1
  SUBSTRAIT_STATUS="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $token" "$base$path" "$@" 2>/dev/null)"
  local rc=$?
  SUBSTRAIT_BODY="$(cat "$tmp")"
  rm -f "$tmp"
  return $rc
}
