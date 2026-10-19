# OpenCode v2 (sandboxed)

[OpenCode](https://github.com/anomalyco/opencode/tree/v2) v2 (the `v2` branch,
released as `ghcr.io/anomalyco/opencode:2.x`) with internet access limited to
the domains in `allowed_domains.txt`.

The container runs `opencode serve` (the v2 API server) inside the sandbox. You
attach the terminal UI to it with `docker compose exec`. The web UI is opt-in.

## Setup

```sh
cp .env.example .env     # set OPENAI_API_KEY, OPENCODE_PASSWORD, model, UID/GID (`id -u` / `id -g`)
cp allowed_domains.example.txt allowed_domains.txt   # your endpoint's host
mkdir -p data
docker compose up -d
```

Create `./data` yourself before the first start. Otherwise Docker creates it
owned by root, and OpenCode (running as `OPENCODE_UID`) can't write to it.

## Default provider and model

`config/opencode.json` is mounted read-only as OpenCode's explicit config
(`OPENCODE_CONFIG`). Every value in it is a `{env:…}` reference, so you configure
everything in `.env`:

| Variable                                         | Meaning                                       | Example                  |
|--------------------------------------------------|-----------------------------------------------|--------------------------|
| `OPENAI_BASE_URL`, `OPENAI_API_KEY`              | OpenAI-compatible endpoint                    | `https://host/ollama/v1` |
| `OPENAI_MODEL`                                   | Default model                                 | `gpt-oss:20b`            |
| `OPENAI_CONTEXT_WINDOW`, `OPENAI_MAX_OUTPUT_TOKENS` | Token limits OpenCode assumes for it      | `131072`, `32768`        |
| `OPENCODE_PROVIDER_ID`, `OPENCODE_PROVIDER_NAME` | Provider key and label (model = `<id>/<model>`) | `llm`                  |

The key is substituted at load time and isn't written anywhere.

### All models of the endpoint

OpenCode itself only offers the models named in its config. So on every
`docker compose up`, a short-lived `opencode-models` service (`node:24-alpine`,
on the internal network, through the proxy) runs `config/discover-models.mjs`.
It calls `GET $OPENAI_BASE_URL/models` and writes every model into OpenCode's
global config (`data/config/opencode/opencode.json`), where the list merges with
the provider from `config/opencode.json`. Then `opencode` starts.

| Variable                  | Meaning                                              | Default             |
|---------------------------|------------------------------------------------------|---------------------|
| `OPENCODE_MODELS_INCLUDE` | Regex; only matching model IDs are offered           | (all)               |
| `OPENCODE_MODELS_EXCLUDE` | Regex; matching model IDs are dropped                | `embed\|rerank\|bge-` |

- Pick a model in the TUI/web UI model picker, or with `-m llm/<model>` on the CLI.
- The endpoint's `/models` doesn't report context sizes, so every discovered model
  gets `OPENAI_CONTEXT_WINDOW` / `OPENAI_MAX_OUTPUT_TOKENS`. Override single models
  in `config/opencode.json` under `providers.llm.models` if needed.
- To refresh the list after models were added on the server, run `docker compose up -d`
  (or `docker compose run --rm opencode-models`, then reopen the TUI).
- If the endpoint is unreachable, the previous list is kept and OpenCode still starts. After changing
`.env`, run `docker compose up -d`. To add more models or providers, edit
`config/opencode.json` (v2 format: `providers.<id>.package`, `.settings.baseURL`,
`.settings.apiKey`, `.models`).

## Web UI (optional, off by default)

The web UI is **off by default**; the interactive CLI is the normal way in.
To enable it, start with `docker compose --profile ui up -d` (or set
`COMPOSE_PROFILES=ui` in `.env`). Turn it off again with `docker compose rm -sf ui-gateway`.

Open <http://127.0.0.1:4096> (`OPENCODE_PORT`) and sign in with user **`opencode`**
and `OPENCODE_PASSWORD`. Without the password, the API (`/api/…`) answers 401.
For one-time sign-in links (e.g. for another browser), run
`docker compose exec opencode opencode pair`.

The agent works in `./workspace` (`/workspace` in the container). Put the
projects you want it to work on there.

## Interactive console (TUI)

Attach the terminal UI to the running server. `OPENCODE_PASSWORD` is already set
in the container:

```sh
docker compose exec opencode opencode --server http://127.0.0.1:4096            # TUI in /workspace
docker compose exec opencode opencode --server http://127.0.0.1:4096 -c         # continue last session
docker compose exec opencode opencode mini --server http://127.0.0.1:4096       # minimal interface
```

One-shot prompts and other commands:

```sh
docker compose exec opencode opencode run --server http://127.0.0.1:4096 "explain this repo"
docker compose exec opencode opencode session list --server http://127.0.0.1:4096
docker compose exec opencode opencode models --server http://127.0.0.1:4096
docker compose exec opencode opencode --help
docker compose exec opencode sh                                                 # shell in the sandbox
```

Always pass `--server http://127.0.0.1:4096`. Without it, the CLI starts its own
background service next to the one compose runs.

## Persistent sessions and state

All OpenCode state (sessions database, config, logs, cache) lives under `/data`
(`XDG_*` point there). It's mounted from `OPENCODE_DATA` in `.env`:

- `OPENCODE_DATA=./data` (default): a folder next to this README.
- `OPENCODE_DATA=opencode-data`: a Docker-managed named volume (`opencode2_opencode-data`).

Sessions survive `down`, image updates and container recreation. Only
`down -v` (named volume) or deleting `./data` removes them.

## Offline skill installation

The sandbox can't reach skill registries (skills.sh, ClawHub, GitHub), so install
skills **before**, from outside the sandbox, into the folder the sandbox mounts.
A skill is a folder with a `SKILL.md` (plus optional scripts and reference files).
Skills are instructions and often scripts that the agent will follow, so review
what you install.

### 1. Install the skill files (needs internet, on the host)

OpenCode v2 has no skill installer. It scans folders, and these are persisted here:

| Folder on the host                         | Scope         |
|--------------------------------------------|---------------|
| `data/home/.agents/skills/<name>/` (`~/.agents/skills`, `HOME=/data/home`) | all projects |
| `data/home/.claude/skills/<name>/` (`~/.claude/skills`)                  | all projects |
| `workspace/<project>/.agents/skills/<name>/`                             | that project |

Get the skill folder with `git` on the host, e.g. Anthropic's pdf skill:

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/anthropics/skills /tmp/anthropic-skills
git -C /tmp/anthropic-skills sparse-checkout set skills/pdf
mkdir -p data/home/.agents/skills
cp -r /tmp/anthropic-skills/skills/pdf data/home/.agents/skills/
docker compose exec opencode opencode reload --server http://127.0.0.1:4096
```

With `OPENCODE_DATA=opencode-data`, copy the folder into the volume instead, e.g.
with `docker compose cp ./pdf opencode:/data/home/.agents/skills/`.

### From skills.sh

skills.sh lists skills as `skills.sh/<owner>/<repo>/<skill>`, e.g.
`skills.sh/anthropics/skills/pdf`. The files live in the GitHub repo `<owner>/<repo>`.

**Simplest: `npx skills` on the host** (needs Node.js on the host):

```sh
mkdir -p data/home && cd data/home
npx skills add https://github.com/mattpocock/skills --skill tdd -a opencode -y
cd ../..
docker compose exec opencode opencode reload --server http://127.0.0.1:4096
```

This gives `data/home/.agents/skills/<skill>/` (`~/.agents/skills` for `HOME=/data/home`).

- Run it **in exactly that folder**. Without `-g`, the CLI installs relative to
  the current directory. Run one level too deep (e.g. inside `.agents/skills`)
  and you get a nested `.agents/skills/.agents/skills/…` that the harness doesn't find.
- Name **one** agent with `-a`, so the prompt asking for additional agents is
  skipped. With several agents, the CLI keeps one real copy and symlinks the
  rest; those symlinks can break inside the container.
- Don't add `-g`. That installs into your own home folder on the host, which the
  sandbox doesn't mount.
- `--skill` can be repeated to install several skills from the same repo.
- Skills with `disable-model-invocation: true` (e.g. `setup-matt-pocock-skills`)
  are installed but not offered to the model on its own. Ask for them by name.

**Without Node on the host**, run the same CLI in a throwaway container:

Use the skills.sh CLI (`npx skills`) with its `opencode` target (`~/.agents/skills`).
`HOME` is `/data/home` here, so mount `./data/home` as the CLI's home. **Create
the folder first**, or Docker creates it as root and the CLI can't write:

```sh
mkdir -p data/home
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp/h -e npm_config_cache=/tmp/npm -e DISABLE_TELEMETRY=1 \
  -v "$PWD/data/home:/tmp/h" node:24 \
  npx -y skills@1.7.2 add anthropics/skills -s pdf -a opencode -g -y --copy
docker compose exec opencode opencode reload --server http://127.0.0.1:4096
```

That gives `data/home/.agents/skills/<skill>/`.

- `node:24` is the full Node image (the CLI needs `git`). It runs on Docker's
  default network with internet, outside the sandbox. The CLI is pinned
  (`skills@1.7.2`) and telemetry is off.
- `--copy` writes real files instead of symlinks, which wouldn't resolve inside the sandbox.
- To see which skills a repo contains, run the same `docker run` with
  `npx -y skills@1.7.2 add <owner>/<repo> -l` (lists, installs nothing).
- **Check the folder afterwards.** The CLI exits with `0` even when it couldn't
  write, e.g. when Docker created a missing mount folder as root.

### 2. Skills that need extra packages

The OpenCode image is minimal Alpine **without Python**, so any skill with Python
scripts needs a derived image, built with internet. `image/Dockerfile`:

```dockerfile
ARG OPENCODE_VERSION=2.0.32
FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}
RUN apk add --no-cache python3 py3-pip \
 && pip install --no-cache-dir --break-system-packages pypdf
```

Add `build:` to the service in `docker-compose.yml`. `image:` then becomes the
local tag of your build:

```yaml
  opencode:
    build:
      context: ./image
      args:
        OPENCODE_VERSION: ${OPENCODE_VERSION:-2.0.32}
    image: opencode2-skills:local
```

Then `docker compose build && docker compose up -d`. Rebuild when you change
`OPENCODE_VERSION`.

## Notes

- **Ports:** the `opencode` container is only on the internal network, and Docker
  doesn't publish ports for such containers. The optional `ui-gateway` (socat,
  `ui` profile) publishes `127.0.0.1:4096` and forwards it to `opencode:4096` only.
- `OPENCODE_DISABLE_MODELS_FETCH` / `OPENCODE_DISABLE_AUTOUPDATE` stop calls to
  models.dev and the update server. Web search, `opencode upgrade`, plugin
  installs from npm and MCP servers on the internet fail by design unless you
  whitelist their domains in `allowed_domains.txt`.
- Updates: set `OPENCODE_VERSION` in `.env`, then `docker compose pull && docker compose up -d`.
