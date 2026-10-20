# Hermes Agent (sandboxed)

[Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent) with
internet access limited to the domains in `allowed_domains.txt`.

## Setup

```sh
cp .env.example .env     # set OPENAI_API_KEY, model, HERMES_UID/GID (`id -u` / `id -g`)
cp allowed_domains.example.txt allowed_domains.txt   # your endpoint's host
docker compose up -d
```

## Default provider and model

Set these in `.env`:

| Variable          | Meaning                                                    | Example                       |
|-------------------|------------------------------------------------------------|-------------------------------|
| `HERMES_PROVIDER` | Inference provider (`custom` = any OpenAI-compatible API)  | `custom`                      |
| `HERMES_MODEL`    | Default model name, as the endpoint expects it             | `gpt-oss:20b`                 |
| `HERMES_BASE_URL` | Endpoint URL (defaults to `OPENAI_BASE_URL`)               | `https://host/ollama/v1`      |
| `OPENAI_API_KEY`  | API key for the endpoint                                   |                               |

Hermes takes its default model from `config.yaml`, not from env vars. So on
every `docker compose up`, a short-lived `hermes-config` service (no network
access) writes these values into `data/config.yaml` with `hermes config set`.
Then `hermes-agent` starts. Leave a variable empty to keep whatever is already
in `config.yaml`.

- After changing `.env`, apply it with `docker compose up -d` (a plain `restart`
  doesn't re-run the init service).
- Check the result: `docker compose exec hermes-agent hermes config get model`.
- To switch model for one session only, pass `-m` / `--provider`, e.g.
  `docker compose exec hermes-agent hermes -m other-model`, or use `hermes model`
  to change the default interactively. The `.env` values win again on the next `up`.
- Other providers (`openrouter`, `anthropic`, `nous`, `gemini`, …) need their API
  domain whitelisted in `allowed_domains.txt` and their own key variable (e.g. `OPENROUTER_API_KEY`).

## All models of the endpoint

Hermes discovers them itself: for a `custom` endpoint, its model picker fetches
the live `GET <base_url>/models` list (through the proxy) and caches it in `data/`.
Nothing extra runs at startup.

- In a chat: `/model` lists every model the endpoint serves and switches the
  current session.
- `docker compose exec hermes-agent hermes model` changes the default
  interactively. `hermes model --refresh` drops the cache after models were
  added on the server. The `.env` default (`HERMES_MODEL`) applies again on the next `up`.
- Unlike the other folders, Hermes shows the endpoint's raw list, including
  embedding and reranker models. Don't pick those for chat.

## Persistent sessions and state

Everything Hermes keeps lives in `HERMES_HOME=/opt/data`: `config.yaml`, the
SQLite session store, `memories/`, `skills/`, logs, and so on. It's mounted from the
location set by `HERMES_DATA` in `.env`:

- `HERMES_DATA=./data` (default): a folder next to this README. Easy to inspect,
  back up or copy to another machine. It's owned by `HERMES_UID`/`HERMES_GID`.
- `HERMES_DATA=hermes-data`: a Docker-managed named volume (`hermes_hermes-data`).
  It's kept out of the project folder, and you list or remove it with `docker volume ls` / `rm`.

Either way, sessions survive `docker compose down`, image updates and container
recreation. Only `docker compose down -v` (named volume) or deleting `./data`
removes them. Switching `HERMES_DATA` starts with an empty state; it doesn't move
existing data.

To resume a previous session:

```sh
docker compose exec hermes-agent hermes --continue          # most recent session
docker compose exec hermes-agent hermes --resume <SESSION>  # a specific one
docker compose exec hermes-agent hermes sessions list       # list sessions (see `sessions --help`)
```

## Interactive console

The container's main process **is** the interactive `hermes` CLI, so attach to it:

```sh
docker compose attach hermes-agent
```

- Detach without stopping it: `Ctrl-p` then `Ctrl-q`.
- Do **not** use `Ctrl-c` / `/exit` while attached. That ends the main process
  and the container restarts (`restart: unless-stopped`).

To open an additional, independent session instead (safe to exit):

```sh
docker compose exec hermes-agent hermes            # new interactive chat
docker compose exec hermes-agent hermes -z "hi"    # one-shot prompt, prints result
```

`docker compose exec` runs as root, but the image's `hermes` shim drops to the
`hermes` user automatically, so files in `./data` keep the correct owner.

## Useful commands

```sh
docker compose exec hermes-agent hermes setup     # interactive setup wizard
docker compose exec hermes-agent hermes model     # pick provider / model
docker compose exec hermes-agent hermes doctor    # check config + connectivity
docker compose exec hermes-agent hermes --help
docker compose exec hermes-agent bash             # shell in the sandbox
docker compose logs -f                            # logs (agent + proxy)
```

When choosing a provider, use a **custom / OpenAI-compatible** endpoint pointing
at `OPENAI_BASE_URL`. Hosted providers (Nous Portal, OpenRouter, …) are blocked
unless you whitelist their domains in `allowed_domains.txt`.

## Offline skill installation

The sandbox can't reach skill registries (skills.sh, ClawHub, GitHub), so install
skills **before**, from outside the sandbox, into the folder the sandbox mounts.
A skill is a folder with a `SKILL.md` (plus optional scripts and reference files).
Skills are instructions and often scripts that the agent will follow, so review
what you install.

### 1. Install the skill files (needs internet, outside the sandbox)

Hermes reads skills from `HERMES_HOME/skills`, which is `data/skills/<name>/` here.

**Option A (simplest): `npx skills` on the host.** Needs Node.js on the host.
It works for any skill on [skills.sh](https://skills.sh) or in a GitHub repo.
A skills.sh page `skills.sh/<owner>/<repo>/<skill>` means repo `<owner>/<repo>`:

Install into a temporary folder, then copy the skill into `data/skills/`:

```sh
cd /tmp
npx skills add https://github.com/mattpocock/skills --skill grill-me -a universal -y
cd -
cp -r /tmp/.agents/skills/grill-me data/skills/
```

- The CLI has no target that matches Hermes' folder here (its `hermes-agent`
  target writes `.hermes/skills/`), hence the copy step.
- Name **one** agent with `-a`, so the prompt asking for additional agents is
  skipped. With several agents, the CLI keeps one real copy and symlinks the
  rest; those symlinks can break inside the container.
- Don't add `-g`. That installs into your own home folder on the host, which the
  sandbox doesn't mount.
- `--skill` can be repeated to install several skills from the same repo.
- Hermes ships its own skills in the same folder (e.g. `productivity/pdf`). A skill
  with the same name as a built-in one doesn't show up separately.

Check offline, then start a new chat session to use the skill:

```sh
docker compose exec hermes-agent hermes skills list
```

**Option B: Hermes' own installer, without Node on the host.** It also searches
other registries. A plain `docker run` uses Docker's default network, which has
internet, and writes into `./data`:

```sh
# search the registries
docker run --rm -v "$PWD/data:/opt/data" -e HERMES_UID=$(id -u) -e HERMES_GID=$(id -g) \
  nousresearch/hermes-agent:latest skills search pdf

# install (skills.sh/mattpocock/skills/grill-me -> skills-sh/mattpocock/skills/grill-me)
docker run --rm -v "$PWD/data:/opt/data" -e HERMES_UID=$(id -u) -e HERMES_GID=$(id -g) \
  nousresearch/hermes-agent:latest skills install skills-sh/mattpocock/skills/grill-me --yes
```

- With `HERMES_DATA=hermes-data`, use `-v hermes_hermes-data:/opt/data` instead.
- Don't use `docker compose run` for this. It joins the internal network and has no internet.

**Option C: the skills.sh CLI in a throwaway container**, if you want `npx skills`
but have no Node on the host. Its global `hermes-agent` target is `~/.hermes/skills`,
so mount `./data` there:

```sh
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp/h -e npm_config_cache=/tmp/npm -e DISABLE_TELEMETRY=1 \
  -v "$PWD/data:/tmp/h/.hermes" node:24 \
  npx -y skills@1.7.2 add mattpocock/skills -s grill-me -a hermes-agent -g -y --copy
```

- `node:24` is the full Node image (the CLI needs `git`). The CLI is pinned
  (`skills@1.7.2`) and telemetry is off. `--copy` writes real files instead of symlinks.
- **Check the folder afterwards.** The CLI exits with `0` even when it couldn't
  write, e.g. when Docker created a missing mount folder as root.

### 2. Skills that need extra packages

Many skills ship scripts that need Python packages or CLI tools. The `pdf` skill
needs `pypdf`, for example, which the image doesn't have, and the sandbox can't
install it later. Put those into a derived image, built with internet. The
Hermes image has neither `pip` nor `uv`, so copy `uv` in. `image/Dockerfile`:

```dockerfile
FROM nousresearch/hermes-agent:latest
COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /usr/local/bin/uv
RUN uv pip install --python /opt/hermes/.venv/bin/python pypdf
```

Add `build:` to the service in `docker-compose.yml`. `image:` then becomes the
local tag of your build:

```yaml
  hermes-agent:
    build: ./image
    image: hermes-agent-skills:local
```

Then `docker compose build && docker compose up -d`. Rebuild after `docker compose pull`
to pick up upstream updates.

## Notes

- Tools that need the web (browser, web search, `pip install`, `git clone`)
  fail by design. Whitelist specific domains in `allowed_domains.txt` if needed, then
  `docker compose restart llm-proxy`.
- Updates: `docker compose pull && docker compose up -d`.
