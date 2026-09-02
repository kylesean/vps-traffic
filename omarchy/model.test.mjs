// Contract tests for the Bandwagon Traffic widget. Run: node omarchy/model.test.mjs
// Model.js is loaded the same way QtQml loads it (global script in a context),
// so these tests exercise exactly what the widget runs. The manifest and bar
// entry point are also checked, keeping the marketplace/runtime shape honest.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("./Model.js", import.meta.url), "utf8")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "Model.js" })

const {
  autoTextSafe,
  barLabel,
  booleanSetting,
  credentialFields,
  formatGb,
  formatReset,
  formatUpdated,
  headline,
  isAlarming,
  isMissingCredentials,
  metricDetail,
  parseReport,
  percentText,
  providerName,
  settingsWithOverrides,
  supportedProviders
} = model

// --- plugin contract -------------------------------------------------------

test("manifest declares a single bar-widget entry point", () => {
  const manifest = JSON.parse(fs.readFileSync(new URL("../manifest.json", import.meta.url), "utf8"))
  assert.deepEqual(manifest.kinds, ["bar-widget"])
  assert.equal(manifest.entryPoints.barWidget, "omarchy/BarWidget.qml")
  assert.equal(manifest.barWidget.allowMultiple, false)
  assert.equal(manifest.barWidget.defaults.showPercent, true)
  const showPercent = manifest.barWidget.schema.find((row) => row.key === "showPercent")
  assert.equal(showPercent.type, "boolean")
  assert.equal(showPercent.defaultValue, true)
})

test("BarWidget.qml forwards the panel lifecycle", () => {
  const barWidgetSource = fs.readFileSync(new URL("./BarWidget.qml", import.meta.url), "utf8")
  assert.match(barWidgetSource, /^BarWidget\s*\{/m)
  for (const method of ["open", "close", "toggle", "closeForPopoutSwitch", "refresh", "openSettings"])
    assert.match(barWidgetSource, new RegExp(`function\\s+${method}\\s*\\(`))
})

test("SettingsView.qml exposes the credential form and delegates to CLI", () => {
  const settingsSource = fs.readFileSync(new URL("./SettingsView.qml", import.meta.url), "utf8")
  assert.match(settingsSource, /function\s+saveCredentials\s*\(/)
  assert.match(settingsSource, /--creds-read/)
  assert.match(settingsSource, /--creds-write/)
  assert.match(settingsSource, /property string provider/)
})

test("bin/vps-traffic is executable and manages credentials with mode 0600", () => {
  assert.ok(fs.existsSync(new URL("../bin/vps-traffic", import.meta.url)))
  const binSource = fs.readFileSync(new URL("../bin/vps-traffic", import.meta.url), "utf8")
  assert.match(binSource, /--creds-read/)
  assert.match(binSource, /--creds-write/)
  assert.match(binSource, /0o700/)
  assert.match(binSource, /0o600/)
  assert.match(binSource, /KIWIVM_VEID/)
  assert.match(binSource, /VULTR_INSTANCE_ID/)
})

// --- report model ----------------------------------------------------------

const sample = {
  provider: "kiwivm",
  fetched_at: 1000,
  hostname: "perfect-gigs-3.localdomain",
  plan: "kvmv5-the-dc9-plan",
  location: "USCA_9 · US, California",
  os: "ubuntu-24.04-x86_64",
  ip: "104.194.85.47",
  used_gb: 315.58,
  total_gb: 750.0,
  multiplier: 1,
  percent: 42.08,
  next_reset: 1789845705,
  next_reset_iso: "2026-09-20 03:21 CST",
  suspended: false
}

test("parseReport accepts a valid report and clamps percent", () => {
  const ok = parseReport(JSON.stringify(sample))
  assert.equal(ok.ok, true)
  assert.equal(ok.report.percent, 42.08)

  const over = parseReport(JSON.stringify({ used_gb: 100, total_gb: 50 }))
  assert.equal(over.ok, true)
  assert.equal(over.report.percent, 100)
})

test("parseReport rejects garbage and missing fields", () => {
  assert.equal(parseReport("").ok, false)
  assert.equal(parseReport("not json {").ok, false)
  assert.equal(parseReport(JSON.stringify({ used_gb: 1 })).ok, false)
  assert.equal(parseReport(JSON.stringify({ total_gb: 1 })).ok, false)
})

test("isAlarming maps thresholds to severity", () => {
  assert.equal(isAlarming({ percent: 50 }, 80, 95), "")
  assert.equal(isAlarming({ percent: 85 }, 80, 95), "warn")
  assert.equal(isAlarming({ percent: 97 }, 80, 95), "critical")
  assert.equal(isAlarming(null, 80, 95), "critical")
})

test("barLabel renders icon + percent, optional host", () => {
  assert.equal(barLabel(sample, { showPercent: true, showHost: false }), "󰒋 42%")
  assert.equal(barLabel(sample, { showPercent: false, showHost: true }), "󰒋 perfect-gigs-3.localdomain")
  assert.equal(barLabel(null, { showPercent: true }), "󰒋")
})

test("headline/percentText/formatGb formatting", () => {
  assert.equal(headline(sample), "315.6 / 750 GB")
  assert.equal(percentText(sample), "42%")
  assert.equal(formatGb(0.5), "0.50")
  assert.equal(formatGb(12.3), "12.3")
  assert.equal(formatGb(123.456), "123.5")
  assert.equal(formatGb(750.0), "750")
})

test("formatReset computes countdown", () => {
  assert.equal(formatReset(1789845705, 1789845705 * 1000), "resets now")
  const day = 86400
  assert.equal(formatReset(sample.next_reset, (sample.next_reset - 5 * day - 3600) * 1000), "5d 1h left")
  assert.equal(formatReset(sample.next_reset, (sample.next_reset - 2 * 3600 - 600) * 1000), "2h 10m left")
  assert.equal(formatReset(0, Date.now()), "")
})

test("formatUpdated", () => {
  assert.equal(formatUpdated(1000, 1059 * 1000), "updated just now")
  assert.equal(formatUpdated(1000, (1000 + 120) * 1000), "updated 2m ago")
  assert.equal(formatUpdated(0, Date.now()), "")
})

test("autoTextSafe escapes untrusted text", () => {
  assert.equal(autoTextSafe("<script>"), "&lt;script&gt;")
  assert.equal(autoTextSafe('a"b&c'), "a&quot;b&amp;c")
})

test("booleanSetting", () => {
  assert.equal(booleanSetting(true, false), true)
  assert.equal(booleanSetting("true", false), true)
  assert.equal(booleanSetting("0", true), false)
  assert.equal(booleanSetting(undefined, true), true)
})

test("providerName defaults safely", () => {
  assert.equal(providerName(sample), "perfect-gigs-3.localdomain")
  assert.equal(providerName(null), "BandwagonHost")
})

test("supportedProviders exposes the registry copy", () => {
  assert.equal(JSON.stringify(supportedProviders()),
    JSON.stringify([{ id: "kiwivm", label: "BandwagonHost KiwiVM" }, { id: "vultr", label: "Vultr" }]))
  assert.equal(supportedProviders().length, 2)
})

test("credentialFields maps each provider's fields", () => {
  assert.equal(credentialFields("kiwivm")[0].key, "veid")
  assert.equal(credentialFields("kiwivm")[1].env, "KIWIVM_API_KEY")
  assert.equal(credentialFields("vultr")[0].key, "instance_id")
  assert.equal(credentialFields("vultr")[1].env, "VULTR_API_KEY")
  assert.equal(credentialFields("nope").length, 0)
})

test("isMissingCredentials flags the CLI not-configured message", () => {
  assert.equal(isMissingCredentials("error: set VULTR_INSTANCE_ID and VULTR_API_KEY (env or /x/env)"), true)
  assert.equal(isMissingCredentials("error: set KIWIVM_VEID and KIWIVM_API_KEY"), true)
  assert.equal(isMissingCredentials("API request failed"), false)
  assert.equal(isMissingCredentials(""), false)
})

test("metricDetail prefers the report field, then falls back", () => {
  assert.equal(metricDetail({ metric_detail: "Outbound egress · inbound is free" }), "Outbound egress · inbound is free")
  assert.equal(metricDetail({ multiplier: 2 }), "Usage counts at ×2 of actual transfer")
  assert.equal(metricDetail({}), "Bidirectional (upload + download)")
  assert.equal(metricDetail(null), "")
})

test("parseReport accepts a vultr-shaped report", () => {
  const vultr = {
    provider: "vultr",
    fetched_at: 1000,
    hostname: "my-vultr-guest",
    plan: "vc2-1c-1gb",
    location: "atl",
    os: "Ubuntu 24.04 x64",
    ip: "192.0.2.123",
    used_gb: 300.0,
    total_gb: 2000.0,
    multiplier: 1,
    percent: 15,
    next_reset: 1789845705,
    next_reset_iso: "2026-10-01 00:00 UTC",
    suspended: false,
    metric_detail: "Outbound egress · inbound is free"
  }
  const ok = parseReport(JSON.stringify(vultr))
  assert.equal(ok.ok, true)
  assert.equal(ok.report.percent, 15)
  assert.equal(metricDetail(ok.report), "Outbound egress · inbound is free")
  assert.equal(barLabel(ok.report, { showHost: true, showPercent: true }), "󰒋 my-vultr-guest 15%")
})

test("settingsWithOverrides preserves existing settings", () => {
  const next = settingsWithOverrides({ warnPercent: 77 }, "kylesean.vps-traffic", { showHost: true })
  assert.equal(JSON.stringify(next), JSON.stringify({ id: "kylesean.vps-traffic", warnPercent: 77, showHost: true }))
  assert.equal(settingsWithOverrides(null, "", { a: 1 }), null)
})