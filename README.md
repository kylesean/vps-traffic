# VPS Traffic

An [Omarchy](https://omarchy.org/) bar widget showing the **official billed
bandwidth usage** of your proxy VPS — the counter that decides when the
machine gets suspended for running out of traffic.

It queries the provider's panel API (`used / total / reset time`) and shows
usage in your bar, with a clickable panel for the details. Two providers are
wired today — [BandwagonHost](https://bandwagonhost.com/) (搬瓦工) KiwiVM and
[Vultr](https://www.vultr.com/) — behind a single script with one JSON shape,
so more panels can be added with one registry row plus one CLI case.

<!-- TODO: add an anonymized screenshot once you publish.
![bar](screenshots/bar.png) -->

## Why the panel API instead of local measurement?

VPS providers bill **bidirectional** traffic (upload + download) against a
monthly quota that resets on your plan anniversary. Local tools like `vnstat`
measure the network interface, not the billing counter, so they never quite
match. This widget reads the same counter the provider panel displays, which
is the number that matters. Note the counter lags ~15 minutes behind real
usage.

## Features

- Official counter: used / total / percent, identical to the provider panel
- Reset countdown (`17d 2h left`) and exact reset date
- Colour carries the state, the number is detail (nexthop design language):
  calm bar when healthy, yellow past 80%, red past 95% or when suspended
- Click panel: big verdict number, usage meter, plan / location / OS / IP
- Configurable refresh interval (the panel counter is not real-time)
- Zero dependencies: a single `curl` + `python3` script, plus pure-JS QML

## Install

Requires `curl` and `python3` (both present on Omarchy).

### 1. Add the plugin

```bash
# TODO: replace with your repository URL before publishing
git clone https://github.com/<your-username>/vps-traffic ~/.config/omarchy/plugins/kylesean.vps-traffic
```

or copy this folder to `~/.config/omarchy/plugins/kylesean.vps-traffic/`.

### 2. Add your KiwiVM credentials

**Easiest: right-click the widget in the bar → paste VEID and API key in the
settings panel.** The key is written to `~/.config/vps-traffic/<provider>/env`
(mode 600, atomic write) and never reaches the process list through the
settings helper. Note the KiwiVM API authenticates via query string, so the key
is visible in `ps` for the brief instant of each poll — unavoidable with this
endpoint (it cannot take the key in a header).

Or from the terminal — grab your **VEID** and **API KEY** from the KiwiVM
panel (<https://kiwivm.64clouds.com/> → sidebar **API** → Show API Key) and
store them locally, never commit them:

```bash
mkdir -p ~/.config/vps-traffic && chmod 700 ~/.config/vps-traffic
cat > ~/.config/vps-traffic/env <<'EOF'
KIWIVM_VEID=your_veid
KIWIVM_API_KEY=private_xxxxxxxx
EOF
chmod 600 ~/.config/vps-traffic/env
```

Alternatively export `KIWIVM_VEID` / `KIWIVM_API_KEY`, or point the script
elsewhere with `VPS_TRAFFIC_CONF=/path/to/env`.

### 3. Enable the widget in your bar

```bash
omarchy plugin enable kylesean.vps-traffic
omarchy bar put kylesean.vps-traffic --after akitaonrails.ai-usagebar
```

The shell hot-reloads `shell.json` on save, so the widget appears
immediately. Verify with `omarchy plugin list` and
`omarchy plugin validate .`.

## Configuration

Settings live inline in `~/.config/omarchy/shell.json`:

```bash
omarchy bar set kylesean.vps-traffic refreshIntervalSec 300
omarchy bar set kylesean.vps-traffic warnPercent 80
omarchy bar set kylesean.vps-traffic criticalPercent 95
omarchy bar set kylesean.vps-traffic showPercent true
omarchy bar set kylesean.vps-traffic showHost false
```

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `refreshIntervalSec` | int | 300 | API poll interval (30–3600) |
| `warnPercent` | int | 80 | Yellow highlight above this usage % |
| `criticalPercent` | int | 95 | Red highlight above this usage % |
| `provider` | string | `kiwivm` | Which backend to fetch (`kiwivm`, `vultr`) |
| `showPercent` | bool | true | Show `󰒋 42%` in the bar |
| `showHost` | bool | false | Prefix the VPS hostname |

## Multiple providers

Backends are a registry in `omarchy/Model.js` plus one case in `bin/vps-traffic`.
Switch with **middle-click**, or pick one in the panel/settings; each provider
keeps its own credentials at `~/.config/vps-traffic/<provider>/env`, falling
back to the shared `~/.config/vps-traffic/env`.

- **KiwiVM** (BandwagonHost): the native `getServiceInfo` counter — used/total
  and reset arrive directly. Traffic is counted bidirectionally and lags
  ~15 minutes behind real use.
- **Vultr**: the counter is not exposed, so the widget sums the daily
  `outgoing_bytes` from `/instances/{id}/bandwidth` for the current month and
  compares it to `allowed_bandwidth`. Vultr bills **outbound** egress, marks
  inbound free, resets the allowance at the start of each calendar month, and
  accrues it hourly — so a monthly pool is an approximation of the billing
  view.

## Interaction

- **Left click** — open/close the panel
- **Right click** — settings
- **Mouse wheel** — refresh now
- **Middle click** — cycle between the registered providers (`kiwivm`, `vultr`)
- **R / F5** in the panel — refresh
- **Esc** — close

## Command-line tool

The plugin bundles the same script as a standalone CLI:

```bash
~/.config/omarchy/plugins/kylesean.vps-traffic/bin/vps-traffic          # human report
~/.config/omarchy/plugins/kylesean.vps-traffic/bin/vps-traffic --json   # widget JSON
~/.config/omarchy/plugins/kylesean.vps-traffic/bin/vps-traffic --raw    # raw API JSON
```

The widget emits no secrets: the JSON report only carries the hostname, plan,
location, OS, IP, counters, reset timestamp and suspended flag.

## Development

```bash
node omarchy/model.test.mjs   # pure-JS contract tests (no node_modules)
omarchy plugin validate .     # manifest + entry-point check
```

The QML is a thin adapter; all report logic lives in `omarchy/Model.js` so
behaviour is covered by the node tests and shared with any future frontend.

### Adding a new provider

Every backend funnels into one report shape (`used_gb`, `total_gb`, `percent`,
`next_reset`, `suspended`, `provider`). To add one, wire three places and the
selector lights up automatically:

1. **`omarchy/Model.js`** — add a row to `PROVIDERS` (id + label) and an entry
   to `CREDENTIAL_FIELDS` (the fields the settings form shows and their env var
   names). The provider pill, middle-click cycle and provider-specific
   `metric_detail` all read from here.
2. **`bin/vps-traffic`** — add a `case` for the provider that fetches and emits
   the canonical JSON. Keep the exact `provider` id in step 1.
3. **`manifest.json`** — add the id to the `provider` schema `options`.

Credentials live at `~/.config/vps-traffic/<provider>/env` (mode 600), written
atomically by the SettingsView helper over stdin. That helper keeps a per-provider
field map in `omarchy/SettingsView.qml` — keep its env names in sync with
`CREDENTIAL_FIELDS`.

## License

MIT. This project is not affiliated with BandwagonHost.