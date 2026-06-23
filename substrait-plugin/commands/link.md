---
description: Link this project to a Substrait app (set your portal URL + token, then pick the app)
argument-hint: "[app id or slug]"
allowed-tools: Bash
---

You are linking the current working directory to an app on the **Substrait** platform so
the user can deploy it with `/substrait:deploy`. Work through these steps; do not skip the
status check.

1. **Check current state.** Run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" status`

2. **Set up auth if needed.** If status reports auth is NOT configured, the user needs a
   Substrait **personal access token**:
   - Tell them to open the portal's **Upload** tab → **Personal access tokens** → create one,
     and copy the `sbt_…` value (shown only once).
   - Ask them for the token, and for their portal/API base URL (default
     `https://api.substrait.build` — accept it unless they say otherwise).
   - Save it: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" auth --portal-url <URL> --token <TOKEN>`
   - Never echo the token back in plain text in your summary.

3. **List the user's apps:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" list`

4. **Pick the target.**
   - If the user passed an app id or slug in `$ARGUMENTS`, match it to a listed app.
   - Otherwise show the list and ask which app to link.
   - If they have no apps yet, or want a fresh one, tell them to run
     `/substrait:deploy --new "App name"` instead — that creates the app on first deploy and
     links it automatically. This command only links to apps that already exist.

5. **Link it:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" set --project-id <ID>`

6. **Confirm** the linked slug + preview URL, and remind them they can now run
   `/substrait:deploy` to ship the current code.
