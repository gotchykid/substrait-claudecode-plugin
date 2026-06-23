---
description: Package the current project (source only) and deploy it to its linked Substrait app
argument-hint: "[--new \"App name\"]"
allowed-tools: Bash
---

You are deploying the current project to **Substrait**. The deploy script zips the project
(source only), uploads it, and (with `--watch`) follows the build until the preview is live.

1. **Check link/auth state:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" status`
   - If auth is NOT configured, stop and tell the user to run `/substrait:link` first.
   - If auth is fine but this directory isn't linked, AND the user did not pass `--new`,
     tell them to run `/substrait:link` (to attach an existing app) or re-run this command
     as `/substrait:deploy --new "App name"` to create a new app. Do not guess a name.

2. **Deploy.** Run from the project root:
   - Linked app:   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-deploy.sh" --watch`
   - New app:      `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-deploy.sh" --new "<name>" --watch`
     (use the name from `$ARGUMENTS`).

3. **Report the outcome:** the run number and, on success, the live preview URL. If the
   script reports a failure, surface the HTTP status / message and suggest checking the
   portal logs for that run — do not retry automatically.

Note: the script enforces the 16 MB source-only limit and excludes `node_modules/`,
`.venv/`, `dist/`, build output and `.git/`. If it reports the zip is too large, help the
user find and exclude the offending large files rather than bypassing the check.
