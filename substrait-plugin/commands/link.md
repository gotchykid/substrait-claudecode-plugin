---
description: Link this project to a Substrait app with an app-scoped deploy token
allowed-tools: Bash
---

You are linking the current working directory to one app on the **Substrait** platform so
the user can deploy it with `/substrait:deploy`. A Substrait **deploy token** is scoped to a
single app, so the token itself determines which app this project deploys to.

1. **Check current state:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" status`
   If it's already linked and the user only wanted to check, you're done.

2. **Get a deploy token.** The token must be created on the **specific app** the user wants
   this project to deploy to:
   - In the Substrait portal, open that app (Your apps → the app) → the **Deploy** tab →
     **Create deploy token**, and copy the `sbd_…` value (shown once).
   - The app must already exist. If the user hasn't created it yet, tell them to create it in
     the portal first — a deploy token can only be minted for an existing app.
   - Ask the user for the token and their portal/API base URL (default
     `https://api.substrait.build` — accept it unless they say otherwise).
   - Never echo the token back in plain text in your summary.

3. **Save + verify the link:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" save --portal-url <URL> --token <TOKEN>`
   This writes `.substrait/config.json` (gitignored) and confirms which app the token is
   bound to.

4. **Confirm** the linked app + preview URL, and remind the user they can now run
   `/substrait:deploy` to ship the current code.
