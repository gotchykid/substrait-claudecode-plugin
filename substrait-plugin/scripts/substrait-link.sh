#!/usr/bin/env bash
# Link the current project to a Substrait app using an APP-scoped deploy token.
#   save  --portal-url URL --token TOKEN   write .substrait/config.json + verify the token
#   status                                 show the configured portal + bound app
#
# The token determines the app (it was minted on that app's Deploy tab), so there's no
# app to pick here. Config is per-project in ./.substrait/config.json (gitignored).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=substrait-common.sh
. "$DIR/substrait-common.sh"

die() { echo "Error: $*" >&2; exit 1; }

cmd_save() {
  local portal="" token=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --portal-url) portal="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done
  [ -n "$portal" ] || die "--portal-url is required (e.g. https://api.substrait.build)"
  [ -n "$token" ]  || die "--token is required (create one on the app's Deploy tab)"

  mkdir -p .substrait
  umask 177
  python3 - "$SUBSTRAIT_CONFIG_FILE" "${portal%/}" "$token" <<'PY'
import json, sys
path, portal, token = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump({"portal_url": portal, "token": token}, open(path, "w"), indent=2)
PY
  chmod 600 "$SUBSTRAIT_CONFIG_FILE"

  # Verify the token + discover the app it's bound to.
  substrait_call GET /api/deploy/app || exit $?
  [ "${SUBSTRAIT_STATUS:-}" = "200" ] || die "token rejected (HTTP $SUBSTRAIT_STATUS): $SUBSTRAIT_BODY"
  # Cache slug/host alongside the creds for nicer messages.
  python3 - "$SUBSTRAIT_CONFIG_FILE" "$SUBSTRAIT_BODY" <<'PY'
import json, sys
path, body = sys.argv[1], sys.argv[2]
cfg = json.load(open(path)); p = json.loads(body)
cfg["slug"] = p["slug"]
cfg["host"] = p.get("preview_hostname") or (p["slug"] + ".apps.substrait.build")
json.dump(cfg, open(path, "w"), indent=2)
print(f"Linked this project to {p['slug']} (https://{cfg['host']}). Run /substrait:deploy to ship it.")
PY

  if [ -f .gitignore ] && ! grep -qx '.substrait/' .gitignore 2>/dev/null; then
    printf '\n# Substrait CLI link state\n.substrait/\n' >> .gitignore
  elif [ ! -f .gitignore ]; then
    printf '# Substrait CLI link state\n.substrait/\n' > .gitignore
  fi
}

cmd_status() {
  local portal token
  portal="$(substrait_portal_url 2>/dev/null)" || portal=""
  token="$(substrait_token 2>/dev/null)" || token=""
  if [ -z "$portal" ] || [ -z "$token" ]; then
    echo "This project is not linked — run /substrait:link."
    return 0
  fi
  substrait_call GET /api/deploy/app
  if [ $? -eq 0 ] && [ "${SUBSTRAIT_STATUS:-}" = "200" ]; then
    python3 - "$SUBSTRAIT_BODY" "$portal" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
host = p.get("preview_hostname") or (p["slug"] + ".apps.substrait.build")
print(f"Linked to {p['slug']} ({p.get('display_name','')}) on {sys.argv[2]} — https://{host}")
PY
  else
    echo "Configured for $portal, but the token was rejected (HTTP ${SUBSTRAIT_STATUS:-?}) — re-run /substrait:link."
  fi
}

case "${1:-status}" in
  save)   shift; cmd_save "$@" ;;
  status) shift || true; cmd_status ;;
  *) die "unknown command: ${1}. Use save|status." ;;
esac
