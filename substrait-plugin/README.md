# Substrait plugin for Claude Code

Build apps to the Substrait upload/deploy contract and ship them without leaving the
terminal. The plugin bundles:

- the **`substrait-app`** skill — scaffolds a contract-compliant app (FastAPI `backend/`
  on port 8000, `cicd/` Dockerfiles, optional React+Vite+Tailwind `frontend/`, Flyway
  migrations); and
- two slash commands:
  - **`/substrait:link`** — link this project to one of your apps. Opens the portal in your
    browser so you pick the app while logged in; the app-scoped deploy token is fetched
    automatically (no copy/paste). Falls back to pasting a token for headless/CI.
  - **`/substrait:deploy`** — package the project (source only) and deploy it to the linked
    app (`--watch` to follow the build).

## Install

```
/plugin marketplace add gotchykid/substrait-claudecode-plugin
/plugin install substrait@substrait
```

**Using the Claude desktop app?** The `/plugin` commands are terminal-only. Run the two
commands above once from the `claude` CLI in any terminal — CLI and desktop share the same
plugin store (`~/.claude/plugins`), so the plugin is immediately available in desktop
sessions too. (Alternatively, use the desktop plugin manager: the **+** button next to the
prompt box → **Plugins**.) Projects scaffolded by Substrait also ship a
`.claude/settings.json` that pre-registers this marketplace and enables the plugin, so
opening such a project offers the plugin automatically on every surface, including the
desktop app and claude.ai/code.

## Set up & deploy

1. In your project, run `/substrait:link`. It opens the portal in your browser (you're
   already logged in), where you **pick the app** to link — the deploy token is minted for
   that app and returned to the CLI automatically. The app must already exist.
2. Run `/substrait:deploy` to ship (add `--watch` to follow the build to the live URL).

**Headless / CI?** If there's no browser, mint a token by hand: portal → your app → its
**Deploy** tab → **Create deploy token**, copy the `sbd_…` value (shown once), then run
`/substrait:link` and paste it.

Config is **per project** in `./.substrait/config.json` (chmod 600, gitignored) — portal
URL + the app-scoped token. You can override with `SUBSTRAIT_PORTAL_URL` / `SUBSTRAIT_TOKEN`
in the environment.

## Maintainers

**This repository is published, not edited here.** It is generated from canonical sources
in the Substrait monorepo and pushed by `scripts/publish-plugin.sh`:

- `skills/substrait-app/` is assembled from `portal-backend/app/resources/` by
  `scripts/sync-plugin.sh` (the same sources the portal and agent-runner image build from).
- the plugin glue (`.claude-plugin/plugin.json`, `commands/`, `scripts/`) is authored in the
  monorepo under `substrait-plugin/`.

To ship a change, edit the sources in the monorepo, run `bash scripts/sync-plugin.sh`, then
`bash scripts/publish-plugin.sh`. Direct commits here will be overwritten on the next
publish.
