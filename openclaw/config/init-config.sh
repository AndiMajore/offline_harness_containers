#!/bin/sh
# Run by the openclaw-config service on every `docker compose up`.
# Writes the default provider/model from .env into openclaw.json.
# Existing models of the provider are kept; the new one is merged in by id.
set -e
oc() { node /app/dist/index.js "$@"; }
P="${OPENCLAW_PROVIDER:-custom}"

# Gateway must listen on all container interfaces for the published port to work
oc config set gateway '{"mode":"local","bind":"lan","port":18789}' --strict-json --merge

if [ -n "$OPENCLAW_MODEL" ]; then
  # apiKey is stored as a reference to the OPENAI_API_KEY env var, not as plain text
  oc config set "models.providers.$P" "{
    \"baseUrl\": \"$OPENCLAW_BASE_URL\",
    \"apiKey\": {\"source\": \"env\", \"provider\": \"default\", \"id\": \"OPENAI_API_KEY\"},
    \"models\": [{\"id\": \"$OPENCLAW_MODEL\", \"name\": \"${OPENCLAW_MODEL_NAME:-$OPENCLAW_MODEL}\"}]
  }" --strict-json --merge
  oc config set agents.defaults.model "$P/$OPENCLAW_MODEL"
fi

# Model discovery: add every model the endpoint lists (merged by id, so models
# added by hand stay). Filtered by OPENCLAW_MODELS_INCLUDE / _EXCLUDE (regexes).
# On failure the existing list is kept and startup continues.
if [ "${OPENCLAW_MODELS_DISCOVERY:-true}" = "true" ]; then
  rm -f /tmp/models.json /tmp/catalog.json
  node -e '
    const e = process.env
    const inc = new RegExp(e.OPENCLAW_MODELS_INCLUDE || ".*", "i")
    const exc = e.OPENCLAW_MODELS_EXCLUDE ? new RegExp(e.OPENCLAW_MODELS_EXCLUDE, "i") : null
    fetch(e.OPENCLAW_BASE_URL.replace(/\/+$/, "") + "/models", {
      headers: { Authorization: "Bearer " + (e.OPENAI_API_KEY || "") },
      signal: AbortSignal.timeout(20000),
    })
      .then((r) => { if (!r.ok) throw new Error("HTTP " + r.status); return r.json() })
      .then((d) => {
        const ids = (d.data || []).map((m) => m.id).filter(Boolean)
        // the default model keeps its own entry (and display name) from above
        const kept = ids.filter((id) => inc.test(id) && !(exc && exc.test(id)) && id !== e.OPENCLAW_MODEL).sort()
        console.error(`model discovery: ${kept.length} of ${ids.length} models`)
        const fs = require("node:fs")
        fs.writeFileSync("/tmp/models.json", JSON.stringify(kept.map((id) => ({ id, name: id }))))
        // also list them in the configured catalog, which the model pickers show
        const P = e.OPENCLAW_PROVIDER || "custom"
        fs.writeFileSync("/tmp/catalog.json", JSON.stringify(Object.fromEntries(kept.map((id) => [P + "/" + id, {}]))))
      })
      .catch((err) => console.error(`model discovery failed (${err.message}); keeping the existing list`))
  '
  if [ -s /tmp/models.json ] && [ "$(cat /tmp/models.json)" != "[]" ]; then
    oc config set "models.providers.$P.models" "$(cat /tmp/models.json)" --strict-json --merge
    oc config set agents.defaults.models "$(cat /tmp/catalog.json)" --strict-json --merge
  fi
fi

oc config validate
