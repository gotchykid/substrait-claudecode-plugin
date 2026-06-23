# Substrait plugin for Claude Code

Build apps to the Substrait upload/deploy contract and ship them without leaving the
terminal. The plugin bundles:

- the **`substrait-app`** skill — scaffolds a contract-compliant app (FastAPI `backend/`
  on port 8000, `cicd/` Dockerfiles, optional React+Vite+Tailwind `frontend/`, Flyway
  migrations); and
- two slash commands:
  - **`/substrait:link`** — set your portal URL + personal access token, then link this
    directory to one of your Substrait apps.
  - **`/substrait:deploy`** — package the project (source only) and deploy it to the linked
    app (`--watch` to follow the build; `--new "App name"` to create + link a fresh app).

## Install

```
/plugin marketplace add gotchykid/substrait-claudecode-plugin
/plugin install substrait@substrait
```

## Set up & deploy

1. In the Substrait portal, open the **Upload** tab → **Personal access tokens** → create
   one and copy the `sbt_…` value.
2. In your project, run `/substrait:link` and paste the token + portal URL when prompted,
   then pick the app to link (or skip to step 3 with `--new`).
3. Run `/substrait:deploy` to ship. First time on a new app:
   `/substrait:deploy --new "My App"`.

Credentials are stored in `~/.substrait/config.json` (chmod 600); the per-project link is
in `./.substrait/project.json` (gitignored). You can also set `SUBSTRAIT_PORTAL_URL` /
`SUBSTRAIT_TOKEN` in the environment to override the config file.

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
