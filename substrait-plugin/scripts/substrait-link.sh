#!/usr/bin/env bash
# Link the current project to a Substrait app. Subcommands:
#   auth   --portal-url URL --token TOKEN   save credentials to ~/.substrait/config.json
#   list                                    print the caller's apps (JSON) to pick from
#   set    --project-id N                   link this directory to an existing app
#   status                                  show current auth + link state
#
# Auth lives globally in ~/.substrait/config.json; the per-project link lives in
# ./.substrait/project.json (gitignored). Run from the project root.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=substrait-common.sh
. "$DIR/substrait-common.sh"

die() { echo "Error: $*" >&2; exit 1; }

cmd_auth() {
  local portal="" token=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --portal-url) portal="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done
  [ -n "$portal" ] || die "--portal-url is required (e.g. https://api.substrait.build)"
  [ -n "$token" ]  || die "--token is required (create one on the portal's Upload tab)"
  mkdir -p "$SUBSTRAIT_CONFIG_DIR" && chmod 700 "$SUBSTRAIT_CONFIG_DIR"
  umask 177
  python3 - "$SUBSTRAIT_CONFIG_FILE" "${portal%/}" "$token" <<'PY'
import json, sys
path, portal, token = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump({"portal_url": portal, "token": token}, open(path, "w"))
PY
  chmod 600 "$SUBSTRAIT_CONFIG_FILE"
  echo "Saved credentials to $SUBSTRAIT_CONFIG_FILE (portal: ${portal%/})."
}

cmd_list() {
  local body; body="$(substrait_api GET /api/projects)"; local rc=$?
  [ $rc -eq 0 ] || exit $rc
  [ "${HTTP_STATUS:-}" = "200" ] || die "list failed (HTTP $HTTP_STATUS): $body"
  python3 - <<PY
import json, sys
apps = json.loads('''$body''')
if not apps:
    print("(no apps yet — deploy a new one with /substrait:deploy --new \\"My App\\")")
else:
    for a in apps:
        print(f"  [{a['id']}] {a['slug']}  —  {a.get('display_name','')}  ({a.get('status','?')})  https://{a.get('preview_hostname') or a['slug']+'.apps.substrait.build'}")
PY
}

cmd_set() {
  local pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-id) pid="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done
  [ -n "$pid" ] || die "--project-id is required"
  local body; body="$(substrait_api GET "/api/projects/$pid")"; local rc=$?
  [ $rc -eq 0 ] || exit $rc
  [ "${HTTP_STATUS:-}" = "200" ] || die "could not fetch app $pid (HTTP $HTTP_STATUS): $body"
  mkdir -p .substrait
  python3 - "$body" <<'PY'
import json, sys, os
p = json.loads(sys.argv[1])
host = p.get("preview_hostname") or (p["slug"] + ".apps.substrait.build")
json.dump({"project_id": p["id"], "slug": p["slug"], "host": host}, open(".substrait/project.json", "w"), indent=2)
print(f"Linked this project to [{p['id']}] {p['slug']} (https://{host}).")
PY
  # Keep credentials/link state out of git.
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
  if [ -n "$portal" ] && [ -n "$token" ]; then
    echo "Auth: configured (portal $portal)."
  else
    echo "Auth: NOT configured — run /substrait:link."
  fi
  if [ -f "$SUBSTRAIT_PROJECT_FILE" ]; then
    echo "Link: $(_json_get "$SUBSTRAIT_PROJECT_FILE" slug) (project $(_json_get "$SUBSTRAIT_PROJECT_FILE" project_id))"
  else
    echo "Link: this directory is not linked to an app yet."
  fi
}

case "${1:-status}" in
  auth)   shift; cmd_auth "$@" ;;
  list)   shift; cmd_list "$@" ;;
  set)    shift; cmd_set "$@" ;;
  status) shift || true; cmd_status ;;
  *) die "unknown command: ${1}. Use auth|list|set|status." ;;
esac
