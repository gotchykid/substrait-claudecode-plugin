#!/usr/bin/env bash
# Package the current project (source only) and deploy it to Substrait.
#   (default)         redeploy the linked app (see /substrait:link)
#   --new "App name"  create a brand-new app instead of using the link
#   --watch           poll the deploy until it finishes and print the preview URL
# Run from the project root (the dir containing backend/, frontend/, cicd/).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=substrait-common.sh
. "$DIR/substrait-common.sh"

die() { echo "Error: $*" >&2; exit 1; }

WATCH=0
NEW_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH=1; shift ;;
    --new) NEW_NAME="${2:-}"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -d backend ] || die "no backend/ here — run this from the project root (the dir with backend/, cicd/)."

# 1. Zip the project root, source only. The platform discards build artifacts anyway,
#    and the 16 MB cap is easy to blow with node_modules/.venv present.
zip_path="$(mktemp -t substrait-XXXXXX).zip"
trap 'rm -f "$zip_path"' EXIT
echo "Packaging (source only)…"
zip -rq "$zip_path" . \
  -x '.git/*' '*/.git/*' \
     'node_modules/*' '*/node_modules/*' \
     '.venv/*' '*/.venv/*' 'venv/*' '*/venv/*' \
     '__pycache__/*' '*/__pycache__/*' '*.pyc' \
     'dist/*' '*/dist/*' 'build/*' '*/build/*' \
     '.substrait/*' '.DS_Store' '*/.DS_Store' \
  || die "zip failed"

size=$(wc -c < "$zip_path" | tr -d ' ')
max=$((16 * 1024 * 1024))
if [ "$size" -gt "$max" ]; then
  die "zip is $((size/1024/1024)) MB (max 16 MB). Exclude build output / large assets and retry."
fi
echo "Packaged $((size/1024)) KB."

# 2. Upload — to the linked app, or as a new app with --new.
if [ -n "$NEW_NAME" ]; then
  echo "Creating new app \"$NEW_NAME\"…"
  body="$(substrait_api POST /api/projects/upload \
    -F "file=@$zip_path;type=application/zip;filename=upload.zip" \
    -F "display_name=$NEW_NAME" -F "backend_stack=fastapi")" || exit $?
elif [ -f "$SUBSTRAIT_PROJECT_FILE" ]; then
  pid="$(_json_get "$SUBSTRAIT_PROJECT_FILE" project_id)" || die "corrupt .substrait/project.json — re-run /substrait:link."
  slug="$(_json_get "$SUBSTRAIT_PROJECT_FILE" slug)"
  echo "Deploying to linked app: $slug (project $pid)…"
  body="$(substrait_api POST "/api/projects/$pid/upload" \
    -F "file=@$zip_path;type=application/zip;filename=upload.zip" \
    -F "backend_stack=fastapi")" || exit $?
else
  die "not linked — run /substrait:link first, or pass --new \"App name\" to create a new app."
fi

case "${HTTP_STATUS:-}" in
  200|201|202) : ;;
  *) die "upload failed (HTTP $HTTP_STATUS): $body" ;;
esac

run_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("run_id",""))' "$body" 2>/dev/null)"
host="$(python3 -c 'import json,sys; p=json.loads(sys.argv[1]).get("project",{}); print(p.get("preview_hostname") or (p.get("slug","")+".apps.substrait.build"))' "$body" 2>/dev/null)"
proj_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("project",{}).get("id",""))' "$body" 2>/dev/null)"

# A brand-new app: persist the link so the next /substrait:deploy targets the same app.
if [ -n "$NEW_NAME" ] && [ -n "$proj_id" ]; then
  mkdir -p .substrait
  python3 - "$body" <<'PY'
import json, sys
p = json.loads(sys.argv[1]).get("project", {})
host = p.get("preview_hostname") or (p.get("slug", "") + ".apps.substrait.build")
json.dump({"project_id": p["id"], "slug": p["slug"], "host": host}, open(".substrait/project.json", "w"), indent=2)
PY
  grep -qx '.substrait/' .gitignore 2>/dev/null || printf '\n# Substrait CLI link state\n.substrait/\n' >> .gitignore
  echo "Created and linked new app: $(_json_get "$SUBSTRAIT_PROJECT_FILE" slug)."
fi

echo "Deploy queued — run #$run_id."

if [ "$WATCH" -ne 1 ]; then
  echo "Track it in the portal; once live it'll be at https://$host"
  exit 0
fi

# 3. Poll the deployment history until this run reaches a terminal state.
echo "Watching deploy… (Ctrl-C to stop watching; the deploy keeps running)"
deadline=$(( $(date +%s) + 900 ))   # 15 min ceiling
last=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 8
  dep="$(substrait_api GET "/api/projects/$proj_id/deployments")" || continue
  [ "${HTTP_STATUS:-}" = "200" ] || continue
  state="$(python3 - "$dep" "$run_id" <<'PY'
import json, sys
deps = json.loads(sys.argv[1]); rid = sys.argv[2]
row = next((d for d in deps if str(d.get("id")) == str(rid)), (deps[0] if deps else None))
print(row.get("state", "") if row else "")
PY
)"
  if [ "$state" != "$last" ] && [ -n "$state" ]; then echo "  • $state"; last="$state"; fi
  case "$state" in
    PREVIEW_LIVE) echo "✅ Live: https://$host"; exit 0 ;;
    FAILED|ERROR) die "deploy failed (state $state). Check the portal logs for run #$run_id." ;;
  esac
done
echo "Still running after 15 min — check the portal for run #$run_id (https://$host when live)."
