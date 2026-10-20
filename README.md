# Sandboxed LLM harnesses

Each folder runs one LLM harness in Docker with **no direct internet access**.
The harness lives on an `internal` Docker network; its only way out is a Squid
proxy (`llm-proxy`) that forwards requests to whitelisted domains only.

```
harness ──(agent-internal, no gateway)──> llm-proxy ──(upstream-lan)──> whitelisted LLM endpoint
```

| Folder       | Harness                               | Interactive terminal UI (run in the folder)                          |
|--------------|---------------------------------------|----------------------------------------------------------------------|
| `hermes/`    | `nousresearch/hermes-agent`           | `docker compose attach hermes-agent`                                 |
| `openclaw/`  | `ghcr.io/phioranex/openclaw-docker`   | `docker compose exec openclaw-gateway node /app/dist/index.js tui`   |
| `opencode2/` | `ghcr.io/anomalyco/opencode:2.x` (v2) | `docker compose exec opencode opencode --server http://127.0.0.1:4096` |

Every folder is self-contained (own compose project, own proxy, own networks,
own whitelist), so you can copy one out on its own or run several side by side.

## Quick setup

For each harness, first create your local config from the examples:

```sh
cd <folder>                                          # hermes/, openclaw/ or opencode2/
cp .env.example .env
cp allowed_domains.example.txt allowed_domains.txt   # put your LLM endpoint's host in there
```

### Hermes (`hermes/`)

1. In `.env`, set `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `HERMES_MODEL`, and
   `HERMES_UID` / `HERMES_GID` (output of `id -u` / `id -g`).
2. `docker compose up -d`
3. `docker compose attach hermes-agent` (detach with `Ctrl-p Ctrl-q`; don't exit
   the chat, that restarts the container)

### OpenClaw (`openclaw/`)

1. In `.env`, set `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENCLAW_MODEL`, and
   `OPENCLAW_GATEWAY_TOKEN` (e.g. `openssl rand -hex 32`).
2. `docker compose up -d`
3. `docker compose exec openclaw-gateway node /app/dist/index.js tui`

### OpenCode v2 (`opencode2/`)

1. In `.env`, set `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL`,
   `OPENCODE_PASSWORD` (e.g. `openssl rand -hex 24`), and `OPENCODE_UID` /
   `OPENCODE_GID` (output of `id -u` / `id -g`).
2. `mkdir -p data && docker compose up -d`
3. `docker compose exec opencode opencode --server http://127.0.0.1:4096`

All other settings in `.env` have working defaults. Each folder's README covers
them, and everything else: all models of the endpoint, sessions, skills, the optional web UI.

By default **no port is published**. You use each harness only through its
interactive terminal UI in the container.

## Whitelisting more endpoints

Each folder's proxy only allows the domains in its `allowed_domains.txt`, one
per line (a leading dot matches subdomains, e.g. `.example.com`). The file is
gitignored, so private endpoint names don't end up in the repository;
`allowed_domains.example.txt` shows the format. After editing it, run
`docker compose restart llm-proxy`.

`squid.conf` itself only contains generic rules (HTTPS on 443, deny everything
else, no caching) and normally needs no changes.

## Skills

The sandboxes can't download skills, so install them beforehand from outside
the sandbox, into the folder the sandbox mounts. Skills that need extra packages
go into a small derived image built with internet. Each folder's README has an
**Offline skill installation** section with the exact commands.

## Verifying the sandbox

```sh
docker compose exec <service> curl -sI https://example.com          # should fail (403 from proxy)
docker compose exec <service> curl -sI --noproxy '*' https://example.com  # should fail (no route)
```

## Optional: web UIs (off by default)

Nice to have, but not needed. OpenClaw and OpenCode also ship a web UI:

| Folder       | Web UI                   | Login                                       |
|--------------|--------------------------|---------------------------------------------|
| `hermes/`    | –                        | –                                           |
| `openclaw/`  | http://127.0.0.1:18789   | `OPENCLAW_GATEWAY_TOKEN`                    |
| `opencode2/` | http://127.0.0.1:4096    | user `opencode`, password `OPENCODE_PASSWORD` |

To turn one on, start that folder with the `ui` profile:

```sh
docker compose --profile ui up -d       # or COMPOSE_PROFILES=ui in .env
docker compose rm -sf ui-gateway        # turn it off again
```

This adds a small `ui-gateway` (socat) service. Docker doesn't publish ports of
containers that are only on an `internal` network, so the gateway sits on both
networks, listens on `127.0.0.1:<port>` on the host and forwards only to the
harness's UI port. The harness itself still has no route out.
