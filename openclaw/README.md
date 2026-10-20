# OpenClaw (sandboxed)

[OpenClaw](https://github.com/openclaw/openclaw) gateway with internet access
limited to the domains in `allowed_domains.txt`.

## Setup

```sh
cp .env.example .env     # set OPENAI_API_KEY, OPENCLAW_GATEWAY_TOKEN, model
cp allowed_domains.example.txt allowed_domains.txt   # your endpoint's host
docker compose up -d
```

There's no need to write `openclaw.json` by hand. It's created and updated from
`.env` on every start (see below). `config/openclaw.json.example` shows what the
result looks like.

## Default provider and model

Set these in `.env`:

| Variable              | Meaning                                                       | Example                  |
|-----------------------|---------------------------------------------------------------|--------------------------|
| `OPENCLAW_PROVIDER`   | Provider key in `openclaw.json` (`custom` = OpenAI-compatible) | `custom`                 |
| `OPENCLAW_MODEL`      | Default model ID, as the endpoint expects it                  | `gpt-oss:20b`            |
| `OPENCLAW_MODEL_NAME` | Optional display name in the UI                               | `GPT-OSS:20b`            |
| `OPENCLAW_BASE_URL`   | Endpoint URL (defaults to `OPENAI_BASE_URL`)                  | `https://host/ollama/v1` |
| `OPENAI_API_KEY`      | API key for the endpoint                                      |                          |

On every `docker compose up`, a short-lived `openclaw-config` service (no network
access) runs `config/init-config.sh`. That script uses OpenClaw's `config set` command (`node /app/dist/index.js config set …`) to:

- write the provider's `baseUrl`,
- add the model to the provider's model list (merged by ID, so models you added
  yourself are kept),
- set `agents.defaults.model` to `<provider>/<model>`,
- set `apiKey` as a **reference to the `OPENAI_API_KEY` env var**, so the key
  itself is never written to `openclaw.json`,

and then validates the config. After that, `openclaw-gateway` starts. Leave
`OPENCLAW_MODEL` empty to skip this and keep `openclaw.json` untouched.

- After changing `.env`, apply it with `docker compose up -d` (a plain `restart`
  doesn't re-run the init service).
- Check the result: `docker compose exec openclaw-gateway node /app/dist/index.js config get agents.defaults.model`.
- Switching models in the UI or with `docker compose exec openclaw-gateway node /app/dist/index.js models` works as usual. The `.env`
  default is set again on the next `up`.

## All models of the endpoint

`init-config.sh` also calls `GET $OPENCLAW_BASE_URL/models` on every start. For
that, the `openclaw-config` service runs on the internal network, through the
proxy. Every model it finds is added to the provider and to the configured model
catalog (`agents.defaults.models`), which is what `models list` and the model
pickers show. Both are merged by ID, so entries you added yourself stay.

| Variable                    | Meaning                                    | Default               |
|-----------------------------|--------------------------------------------|-----------------------|
| `OPENCLAW_MODELS_DISCOVERY` | `false` = only `OPENCLAW_MODEL`            | `true`                |
| `OPENCLAW_MODELS_INCLUDE`   | Regex; only matching model IDs are added   | (all)                 |
| `OPENCLAW_MODELS_EXCLUDE`   | Regex; matching model IDs are skipped      | `embed\|rerank\|bge-` |

- Pick a model in the TUI, or for a single call:
  `docker compose exec openclaw-gateway node /app/dist/index.js infer model run --model custom/<model> --prompt "…"`.
- Models removed on the server stay in the config (the merge only adds).
  Remove them with `config unset`, or edit `data/openclaw.json`.
- If the endpoint is unreachable, the existing list is kept and startup continues.

## Persistent sessions and state

Everything OpenClaw keeps lives in its home `/home/node/.openclaw`:
`openclaw.json`, the session and state databases (`state/`, `agents/`),
`workspace/`, logs, and so on. It's mounted from the location set by
`OPENCLAW_DATA` in `.env`:

- `OPENCLAW_DATA=./data` (default): a folder next to this README. Easy to
  inspect, back up or copy. Agent files are in `./data/workspace`.
- `OPENCLAW_DATA=openclaw-data`: a Docker-managed named volume
  (`openclaw_openclaw-data`). It's kept out of the project folder, and you list
  or remove it with `docker volume ls` / `rm`.

Either way, sessions survive `docker compose down`, image updates and container
recreation. Only `docker compose down -v` (named volume) or deleting `./data`
removes them. Switching `OPENCLAW_DATA` starts with an empty state; it doesn't
move existing data.

To pick up an earlier session: `docker compose exec openclaw-gateway node /app/dist/index.js resume`, or `docker compose exec openclaw-gateway node /app/dist/index.js sessions --help`.

## Web UI (optional, off by default)

The web UI is **off by default**; the interactive CLI is the normal way in.
To enable it, start with `docker compose --profile ui up -d` (or set
`COMPOSE_PROFILES=ui` in `.env`). Turn it off again with `docker compose rm -sf ui-gateway`.

Open <http://127.0.0.1:18789> and authenticate with `OPENCLAW_GATEWAY_TOKEN`
from `.env`. The port is bound to the host's loopback only.

## Interactive console

The image doesn't put an `openclaw` binary on PATH. Run the CLI as
`node /app/dist/index.js` inside the gateway container. From this folder:

```sh
docker compose exec openclaw-gateway node /app/dist/index.js tui        # terminal UI connected to the running gateway
docker compose exec openclaw-gateway node /app/dist/index.js chat       # local terminal UI (embedded agent, no gateway)
docker compose exec openclaw-gateway node /app/dist/index.js resume     # resume a recent gateway session in the TUI
docker compose exec openclaw-gateway node /app/dist/index.js agent --help
```

If the TUI asks for auth, pass the token. The variable is set inside the
container, so expand it there:

```sh
docker compose exec openclaw-gateway sh -c 'node /app/dist/index.js tui --token "$OPENCLAW_GATEWAY_TOKEN"'
```

## Useful commands

```sh
docker compose exec openclaw-gateway node /app/dist/index.js status          # gateway / channel / model status
docker compose exec openclaw-gateway node /app/dist/index.js health          # health of the running gateway
docker compose exec openclaw-gateway node /app/dist/index.js doctor          # health checks + quick fixes
docker compose exec openclaw-gateway node /app/dist/index.js configure       # interactive config (models, gateway, ...)
docker compose exec openclaw-gateway node /app/dist/index.js models --help   # model discovery / config
docker compose exec openclaw-gateway node /app/dist/index.js logs            # tail gateway logs
docker compose exec openclaw-gateway bash   # shell in the sandbox
docker compose logs -f                      # container logs (gateway + proxy)
```

## Offline skill installation

The sandbox can't reach skill registries (skills.sh, ClawHub, GitHub), so install
skills **before**, from outside the sandbox, into the folder the sandbox mounts.
A skill is a folder with a `SKILL.md` (plus optional scripts and reference files).
Skills are instructions and often scripts that the agent will follow, so review
what you install.

### 1. Install the skill files (needs internet, outside the sandbox)

**Option A (simplest): `npx skills` on the host.** Needs Node.js on the host.
It works for any skill on [skills.sh](https://skills.sh) or in a GitHub repo.
A skills.sh page `skills.sh/<owner>/<repo>/<skill>` means repo `<owner>/<repo>`:

```sh
cd data/workspace
npx skills add https://github.com/mattpocock/skills --skill tdd -a openclaw -y
```

This gives `data/workspace/skills/<skill>/`, the agent workspace's skill folder.

- Run it **in exactly that folder**. Without `-g`, the CLI installs relative to
  the current directory. Run one level too deep and you get a nested
  `skills/…/skills/…` that OpenClaw doesn't find.
- Name **one** agent with `-a`, so the prompt asking for additional agents is
  skipped. With several agents, the CLI keeps one real copy and symlinks the
  rest; those symlinks can break inside the container.
- Don't add `-g`. That installs into your own home folder on the host, which the
  sandbox doesn't mount.
- `--skill` can be repeated to install several skills from the same repo.

Check offline:

```sh
docker compose exec openclaw-gateway node /app/dist/index.js skills list
docker compose exec openclaw-gateway node /app/dist/index.js skills check   # missing requirements
```

**Option B: OpenClaw's own installer, without Node on the host.** It also covers
ClawHub skills. A plain `docker run` uses Docker's default network, which has
internet, and writes into `./data`, the OpenClaw home the sandbox mounts:

```sh
# search ClawHub
docker run --rm -v "$PWD/data:/home/node/.openclaw" -e OPENAI_API_KEY=unused \
  ghcr.io/phioranex/openclaw-docker:latest skills search pdf

# install: @owner/slug (ClawHub), skills-sh:owner/repo/slug, git:<repo>, or a local folder
# (skills.sh/anthropics/skills/pdf -> skills-sh:anthropics/skills/pdf)
docker run --rm -v "$PWD/data:/home/node/.openclaw" -e OPENAI_API_KEY=unused \
  ghcr.io/phioranex/openclaw-docker:latest skills install skills-sh:anthropics/skills/pdf
```

- Skills land in `data/workspace/skills/<name>/`.
- `OPENAI_API_KEY=unused` only satisfies the config's key reference; no model is called.
- The container runs as UID 1000. If your host UID differs, `chown` the new folder afterwards.
- With `OPENCLAW_DATA=openclaw-data`, use `-v openclaw_openclaw-data:/home/node/.openclaw`.
- Don't use `docker compose run` for this. It joins the internal network and has no internet.

**Option C: the skills.sh CLI in a throwaway container**, if you want `npx skills`
but have no Node on the host. Its global `openclaw` target is
`~/.openclaw/skills`, the shared managed folder, so mount `./data` there:

```sh
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp/h -e npm_config_cache=/tmp/npm -e DISABLE_TELEMETRY=1 \
  -v "$PWD/data:/tmp/h/.openclaw" node:24 \
  npx -y skills@1.7.2 add anthropics/skills -s pdf -a openclaw -g -y --copy
```

- That ends up in `data/skills/<skill>/` (listed as `openclaw-managed`).
- `node:24` is the full Node image (the CLI needs `git`). The CLI is pinned
  (`skills@1.7.2`) and telemetry is off. `--copy` writes real files instead of symlinks.
- **Check the folder afterwards.** The CLI exits with `0` even when it couldn't
  write, e.g. when Docker created a missing mount folder as root.

### 2. Skills that need extra packages

Skills that ship scripts often need packages the image doesn't have. The `pdf`
skill needs `pypdf`, for example, and the sandbox can't install it later. Put
them into a derived image, built with internet. The image has `python3` but
neither `pip` nor `apt-get`, so copy `uv` in. `image/Dockerfile`:

```dockerfile
FROM ghcr.io/phioranex/openclaw-docker:latest
USER root
COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /usr/local/bin/uv
RUN uv pip install --system --break-system-packages pypdf
USER node
```

Add `build:` to the service in `docker-compose.yml`. `image:` then becomes the
local tag of your build:

```yaml
  openclaw-gateway:
    build: ./image
    image: openclaw-skills:local
```

Then `docker compose build && docker compose up -d`. `openclaw-config` can keep
the upstream image. Rebuild after `docker compose pull` to pick up upstream updates.

## Notes

- Editing `data/openclaw.json` by hand requires `docker compose restart openclaw-gateway`.
- Chat channels (Telegram, Slack, WhatsApp, …), ClawHub, web tools and plugin
  installs need their domains whitelisted in `allowed_domains.txt`. Otherwise they fail by design.
- Updates: `docker compose pull && docker compose up -d`.
- **Ports:** the harness is only on the internal network, so the optional `ui-gateway`
  (socat, `ui` profile) publishes the UI port on 127.0.0.1 and forwards to it.
