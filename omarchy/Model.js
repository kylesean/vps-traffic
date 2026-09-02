// No exports here on purpose: QtQml's JS engine loads this file as a global
// script via `import "Model.js" as Model`, so every function is a member of
// the module. The node contract tests load it the same way (vm context) and
// call the same globals.

const ICON = "󰒋"

// Registry of supported backends. Adding a provider is one row here plus one
// case in bin/vps-traffic — no QML changes. The report's `provider` field
// keeps this in sync with whatever the CLI actually fetched.
const PROVIDERS = [
  { id: "kiwivm", label: "BandwagonHost KiwiVM" },
  { id: "vultr", label: "Vultr" }
]

// The credentials a provider needs, in the order they appear in the settings
// form. `env` is the variable name in ~/.config/vps-traffic/<provider>/env
// (kept in lockstep with the python helper in SettingsView.qml).
const CREDENTIAL_FIELDS = {
  kiwivm: [
    { key: "veid", env: "KIWIVM_VEID", label: "VEID", placeholder: "e.g. 1234567", secret: false },
    { key: "api_key", env: "KIWIVM_API_KEY", label: "API key", placeholder: "private_…", secret: true }
  ],
  vultr: [
    { key: "instance_id", env: "VULTR_INSTANCE_ID", label: "Instance ID", placeholder: "e.g. cb676a46-…", secret: false },
    { key: "api_key", env: "VULTR_API_KEY", label: "API key", placeholder: "VULTR_…", secret: true }
  ]
}

function credentialFields(providerId) {
  const value = String(providerId == null ? "" : providerId).trim()
  const list = CREDENTIAL_FIELDS[value] || []
  const out = []
  for (let i = 0; i < list.length; i++) out.push(list[i])
  return out
}

// Return a copy so callers can't mutate the registry.
function supportedProviders() {
  const out = []
  for (let i = 0; i < PROVIDERS.length; i++) out.push(PROVIDERS[i])
  return out
}

function isKnownProvider(id) {
  const value = String(id == null ? "" : id).trim()
  for (let i = 0; i < PROVIDERS.length; i++)
    if (PROVIDERS[i].id === value) return true
  return false
}

function providerLabel(id, fallback) {
  const value = String(id == null ? "" : id).trim()
  for (let i = 0; i < PROVIDERS.length; i++)
    if (PROVIDERS[i].id === value) return PROVIDERS[i].label
  return String(fallback || value || "Unknown")
}

function booleanSetting(value, fallback) {
  if (value === true || value === false) return value
  const normalized = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (["true", "1", "yes", "on"].indexOf(normalized) >= 0) return true
  if (["false", "0", "no", "off"].indexOf(normalized) >= 0) return false
  return fallback === true
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

// Untrusted text (API strings, hostname, plan, errors) reaches rendered
// output, so sanitize at the sink.
function autoTextSafe(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function cleanText(text, maxLength) {
  return String(text == null ? "" : text).slice(0, maxLength || 200)
}

// Merge widget settings saved inline in shell.json, preserving any settings a
// future version adds. Mirrors the ai-usagebar contract with Quattro.
function settingsWithOverrides(settings, moduleName, overrides) {
  const moduleId = cleanText(moduleName, 180).trim()
  if (moduleId === "" || !overrides || typeof overrides !== "object" || Array.isArray(overrides))
    return null
  const next = { id: moduleId }
  const current = settings && typeof settings === "object" && !Array.isArray(settings)
    ? settings : {}
  for (const key in current) {
    if (key === "id" || key === "__proto__" || key === "constructor" || key === "prototype")
      continue
    next[key] = current[key]
  }
  for (const overrideKey in overrides) {
    if (overrideKey === "id" || overrideKey === "__proto__" || overrideKey === "constructor"
        || overrideKey === "prototype") continue
    next[overrideKey] = overrides[overrideKey]
  }
  return next
}

function parseReport(stdout) {
  const text = String(stdout == null ? "" : stdout).trim()
  if (text === "") return { ok: false, error: "empty report" }
  let data
  try {
    data = JSON.parse(text)
  } catch (err) {
    return { ok: false, error: "invalid JSON: " + err.message }
  }
  if (!data || typeof data !== "object")
    return { ok: false, error: "report is not an object" }
  if (typeof data.used_gb !== "number" || typeof data.total_gb !== "number")
    return { ok: false, error: "report is missing used_gb/total_gb" }
  const percent = data.total_gb > 0
    ? clamp((data.used_gb / data.total_gb) * 100, 0, 100)
    : 0
  return {
    ok: true,
    report: Object.assign({}, data, { percent: Math.round(percent * 100) / 100 })
  }
}

// "" | "warn" | "critical"
function isAlarming(report, warnPercent, criticalPercent) {
  if (!report || report.error) return "critical"
  const warn = Number(warnPercent) || 80
  const critical = Number(criticalPercent) || 95
  if (report.percent >= critical) return "critical"
  if (report.percent >= warn) return "warn"
  return ""
}

function providerName(report) {
  return report && report.hostname ? autoTextSafe(report.hostname) : "BandwagonHost"
}

function headline(report) {
  if (!report) return ""
  return autoTextSafe(
    formatGb(report.used_gb) + " / " + formatGb(report.total_gb) + " GB"
  )
}

function formatGb(gb) {
  const value = Number(gb) || 0
  const s = value >= 1000 ? Math.round(value).toString()
    : value >= 10 ? value.toFixed(1)
    : value.toFixed(2)
  return s.endsWith(".0") ? s.slice(0, -2) : s
}

function barLabel(report, options) {
  const opts = options || {}
  let text = ICON
  if (opts.showHost && report && report.hostname)
    text += " " + autoTextSafe(report.hostname)
  if (opts.showPercent !== false && report && report.error === undefined)
    text += " " + Math.round(report.percent) + "%"
  return text
}

// "42%" or "" when no report
function percentText(report) {
  if (!report || report.percent === undefined) return ""
  return Math.round(report.percent) + "%"
}

function formatReset(resetEpoch, nowMs) {
  if (!resetEpoch) return ""
  const target = Number(resetEpoch) * 1000
  const now = Number(nowMs) || Date.now()
  let diffSec = Math.round((target - now) / 1000)
  if (diffSec <= 0) return "resets now"
  const days = Math.floor(diffSec / 86400)
  const hours = Math.floor((diffSec % 86400) / 3600)
  const minutes = Math.floor((diffSec % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h left"
  if (hours > 0) return hours + "h " + minutes + "m left"
  return minutes + "m left"
}

// The CLI prints "error: set VULTR_INSTANCE_ID and VULTR_API_KEY (env or …)"
// when a provider has no credentials. Treat that as "not configured", i.e. a
// gentle prompt, not a hard fetch failure.
function isMissingCredentials(text) {
  return /set\s+[A-Z0-9_]+/.test(String(text == null ? "" : text))
}

function metricDetail(report) {
  if (!report) return ""
  if (report.metric_detail) return report.metric_detail
  if (report.multiplier && report.multiplier !== 1)
    return "Usage counts at ×" + report.multiplier + " of actual transfer"
  return "Bidirectional (upload + download)"
}

function formatUpdated(fetchedAt, nowMs) {
  if (!fetchedAt) return ""
  const then = Number(fetchedAt) * 1000
  const now = Number(nowMs) || Date.now()
  const diffSec = Math.max(0, Math.round((now - then) / 1000))
  if (diffSec < 60) return "updated just now"
  if (diffSec < 3600) return "updated " + Math.round(diffSec / 60) + "m ago"
  return "updated " + Math.round(diffSec / 3600) + "h ago"
}

// No exports here on purpose: QtQml's JS engine loads this file as a global
// script via `import "Model.js" as Model`, so every function is a member of
// the module. The node contract tests load it the same way (vm context) and
// call the same globals.
