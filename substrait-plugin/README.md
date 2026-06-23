# Substrait plugin for Claude Code

Build apps to the Substrait upload/deploy contract and ship them without leaving the
terminal. The plugin bundles:

- the **`substrait-app`** skill — scaffolds a contract-compliant app (FastAPI `backend/`
  on port 8000, `cicd/` Dockerfiles, optional React+Vite+Tailwind `frontend/`, Flyway
  migrations); and
- two slash commands:
  - **`/substrait:link`** — save this project's portal URL + app-scoped deploy token (the
    token determines which app this project deploys to).
  - **`/substrait:deploy`** — package the project (source only) and deploy it to the linked
    app (`--watch` to follow the build).

## Install

```
/plugin marketplace add gotchykid/substrait-claudecode-plugin
/plugin install substrait@substrait
```

## Set up & deploy

1. In the Substrait portal, open your app → its **Deploy** tab → **Create deploy token**,
   and copy the `sbd_…` value (shown once). The app must already exist — a deploy token is
   scoped to a single app.
2. In your project, run `/substrait:link` and paste the token + portal URL when prompted.
3. Run `/substrait:deploy` to ship (add `--watch` to follow the build to the live URL).

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
