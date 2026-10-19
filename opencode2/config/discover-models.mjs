// Run by the opencode-models service on every `docker compose up`.
// Lists the models of the OpenAI-compatible endpoint (GET $OPENAI_BASE_URL/models,
// through llm-proxy) and writes them into OpenCode's global config, where they
// merge with the provider defined in config/opencode.json.
// On any failure the previous list is kept and startup continues.
import { mkdirSync, writeFileSync, renameSync } from "node:fs"
import { dirname } from "node:path"

const out = process.env.MODELS_CONFIG_FILE ?? "/data/config/opencode/opencode.json"
const provider = process.env.OPENCODE_PROVIDER_ID || "llm"
const base = (process.env.OPENAI_BASE_URL ?? "").replace(/\/+$/, "")
const include = new RegExp(process.env.OPENCODE_MODELS_INCLUDE || ".*", "i")
const exclude = process.env.OPENCODE_MODELS_EXCLUDE ? new RegExp(process.env.OPENCODE_MODELS_EXCLUDE, "i") : null
const limit = {
  context: Number(process.env.OPENAI_CONTEXT_WINDOW || 131072),
  output: Number(process.env.OPENAI_MAX_OUTPUT_TOKENS || 32768),
}

try {
  const res = await fetch(`${base}/models`, {
    headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY ?? ""}` },
    signal: AbortSignal.timeout(20000),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${base}/models`)
  const ids = ((await res.json()).data ?? []).map((m) => m.id).filter(Boolean)
  const kept = ids.filter((id) => include.test(id) && !(exclude && exclude.test(id))).sort()
  const models = Object.fromEntries(kept.map((id) => [id, { name: id, limit }]))
  mkdirSync(dirname(out), { recursive: true })
  writeFileSync(`${out}.tmp`, JSON.stringify({ providers: { [provider]: { models } } }, null, 2) + "\n")
  renameSync(`${out}.tmp`, out)
  console.log(`opencode-models: ${kept.length} of ${ids.length} models written to ${out}`)
} catch (err) {
  console.error(`opencode-models: discovery failed (${err.message}); keeping the previous list`)
}
