---
description: Link this project to a Substrait app (account link — pick or create the app right here)
allowed-tools: Bash
---

You are linking the current working directory to one app on the **Substrait** platform so
the user can deploy it with `/substrait:deploy`. Two credential models exist:

- **Account link (preferred):** a **personal access token** (`sbt_…`) stored once per
  machine (`~/.substrait/config.json`). It authenticates the user; each project then just
  records **which app** it deploys to (a slug in `.substrait/config.json`, no secret).
- **Per-app deploy token** (`sbd_…`, the original flow): scoped to a single app, stored in
  the project. Still fully supported — and it wins over the account token if both exist.

1. **Check current state:**
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" status`
   It reports both layers: whether this machine has an account link, and what this project
   is bound to. If the project is already linked and the user only wanted to check, you're
   done.

2. **Ensure the account link (once per machine).** If status says there's no account link:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" account`
   This opens the Substrait portal in the user's browser, where they (already logged in)
   **authorize Claude Code on their account** — the personal token is minted and returned
   to the CLI automatically, no copy/paste. The command prints a URL and a short
   verification code; relay both to the user in case the browser didn't open, and tell
   them to complete the authorization in the browser. It blocks until they approve.
   - Only on a **self-hosted** Substrait portal, pass `--portal-url <URL>`.
   - Headless / CI fallback: the user mints a token on the portal's **Access tokens**
     page, then `… substrait-link.sh save-account --token <TOKEN>`. Ask **only for the
     token**; never echo it back in plain text.

3. **Bind this project to an app.** With the account link in place:
   - List the user's apps: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/substrait-link.sh" apps`
     (prints `slug<TAB>display name` lines). Show them to the user and ask which app this
     project should deploy to — or whether to create a new one.
   - Existing app: `… substrait-link.sh use --app <SLUG>`
   - New app:      `… substrait-link.sh create --name "<NAME>"`

4. **Per-app token fallback.** If the user prefers a token scoped to one app (shared
   machines, CI secrets):
   - Browser flow: `… substrait-link.sh login` (pick the app in the browser; the `sbd_…`
     token is fetched automatically).
   - Paste flow: mint on the app's **Deploy** tab, then
     `… substrait-link.sh save --token <TOKEN>` (add `--portal-url <URL>` only for
     self-hosted).

5. **Confirm** the linked app + preview URL, and remind the user they can now run
   `/substrait:deploy` to ship the current code.

Note: on a successful link, the script also records a **"Substrait deployment" section
in the project's `CLAUDE.md`** (creating the file if needed) so every future session
knows the deploy contract without loading the skill. It's a marker-delimited block the
plugin keeps current on later deploys; deleting the whole block opts the project out —
don't re-add it by hand if the user removed it.
