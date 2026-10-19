# Sandboxed LLM harnesses

Each folder runs one LLM harness in Docker with **no direct internet access**.
The harness lives on an `internal` Docker network; its only way out is a Squid
proxy (`llm-proxy`) that forwards requests to whitelisted domains only.

```
harness ──(agent-internal, no gateway)──> llm-proxy ──(upstream-lan)──> whitelisted LLM endpoint
```

| Folder              | Harness                              | Web UI (opt-in, `ui` profile) |
|---------------------|--------------------------------------|--------------------------|
| `hermes/`           | `nousresearch/hermes-agent`          | – (attach via CLI)       |
| `openclaw/`         | `ghcr.io/phioranex/openclaw-docker`  | http://127.0.0.1:18789   |
| `deepseek-harness/` | `moelin/deepseek-harness:workstation`| http://127.0.0.1:56789   |
| `opencode2/`        | `ghcr.io/anomalyco/opencode:2.x` (v2) | http://127.0.0.1:4096    |
| `harness2/`         | google-research/harness2 (built locally, JobBench) | – (batch CLI)  |

Every folder is self-contained (own compose project, own proxy, own networks,
own whitelist), so you can copy one out on its own or run several side by side.

## Usage

```sh
cd <harness>
cp .env.example .env          # fill in API key / tokens
cp allowed_domains.example.txt allowed_domains.txt
$EDITOR allowed_domains.txt   # your LLM endpoint's host
docker compose up -d
```

Harness-specific notes (see each folder's README for details):

- **hermes** – default model/provider come from `.env` (written to `config.yaml` on start);
  attach to the interactive agent with `docker compose attach hermes-agent`
  (detach with `Ctrl-p Ctrl-q`).
- **openclaw** – default model/provider and the API key come from `.env` and are
  written to `openclaw.json` on start. Terminal UI: `docker compose exec openclaw-gateway
  node /app/dist/index.js tui` (optional web UI: token `OPENCLAW_GATEWAY_TOKEN`).
- **opencode2** – attach the TUI: `docker compose exec opencode opencode --server http://127.0.0.1:4096`
  (optional web UI: sign in as `opencode` / `OPENCODE_PASSWORD`).
- **harness2** – build first (`docker compose build`, needs internet), then run
  `harness2 --bench jb …` via `docker compose exec harness2`.
- **deepseek-harness** – one-shot tasks: `docker compose exec -u node deepseek-harness dsh headless "…"`
  (no terminal chat UI; optional web UI: `admin` / `AUTH_PASSWORD`). Files go in `./workspace`.

## Web UIs are opt-in

By default **no port is published**. You use each harness through its
interactive CLI via `docker compose exec` (see each folder's README). The only
exception is deepseek-harness, which has no terminal chat UI; there you get one-shot `dsh headless`.

To get a web UI, start that folder with the `ui` profile:

```sh
docker compose --profile ui up -d       # or COMPOSE_PROFILES=ui in .env
docker compose rm -sf ui-gateway        # turn it off again
```

This adds a small `ui-gateway` (socat) service. Docker doesn't publish ports of
containers that are only on an `internal` network, so the gateway sits on both
networks, listens on `127.0.0.1:<port>` on the host and forwards only to the
harness's UI port. The harness itself still has no route out.

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
