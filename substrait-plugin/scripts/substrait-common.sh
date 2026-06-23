#!/usr/bin/env bash
# Shared helpers for the Substrait plugin's link/deploy scripts. Sourced, not run —
# so it sets no shell options of its own and never exits the caller.
#
# Config resolution (first hit wins):
#   portal URL : $SUBSTRAIT_PORTAL_URL  ->  ~/.substrait/config.json "portal_url"
#   token      : $SUBSTRAIT_TOKEN       ->  ~/.substrait/config.json "token"
# The config file is written by `substrait-link.sh auth` (chmod 600). Per-project link
# state lives in <project>/.substrait/project.json (written by `substrait-link.sh set`).

SUBSTRAIT_CONFIG_DIR="${SUBSTRAIT_CONFIG_DIR:-$HOME/.substrait}"
SUBSTRAIT_CONFIG_FILE="$SUBSTRAIT_CONFIG_DIR/config.json"
SUBSTRAIT_PROJECT_FILE=".substrait/project.json"   # relative to the project root (cwd)

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

# substrait_api METHOD PATH [extra curl args...]
# Prints the response body to stdout and sets HTTP_STATUS. Returns 2 if unconfigured,
# 1 on a transport error.
substrait_api() {
  local method="$1" path="$2"; shift 2
  local base token tmp status
  base="$(substrait_portal_url)" || {
    echo "Not linked yet — run /substrait:link to set your portal URL and token." >&2; return 2; }
  token="$(substrait_token)" || {
    echo "No token configured — run /substrait:link to set one." >&2; return 2; }
  tmp="$(mktemp)" || return 1
  status="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $token" "$base$path" "$@" 2>/dev/null)"
  local rc=$?
  HTTP_STATUS="$status"
  cat "$tmp"
  rm -f "$tmp"
  return $rc
}
