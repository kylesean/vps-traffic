# VPS Traffic

**[English](README.md)** | **[简体中文](README_zh.md)**

Native [Omarchy](https://omarchy.org/) bar widget that shows your VPS provider's
**official billed bandwidth** — used / total, percent, and reset countdown.

Built for [BandwagonHost](https://bandwagonhost.com/) KiwiVM, with reference support for [Vultr](https://www.vultr.com/).

## Features

- Official counter: used / total / percent, matching the provider panel
- Reset countdown (`17d 2h left`) and exact reset date
- Colour carries the state: calm → yellow past 80% → red past 95% or when suspended
- Click for a panel with the usage meter, plan / location / OS / IP
- Configurable refresh interval; **middle-click** switches provider
- Zero dependencies: one self-contained CLI script, pure-JS report model

## Install

Requires `curl` and `python3` (both standard on Omarchy).

```bash
omarchy plugin add https://github.com/kylesean/vps-traffic --enable
```

Or manually: copy this folder to `~/.config/omarchy/plugins/kylesean.vps-traffic/`,
run `omarchy-shell shell rescanPlugins`, then `omarchy plugin enable kylesean.vps-traffic`.

Place it in the bar with:
```bash
omarchy bar put kylesean.vps-traffic --after omarchy.clock
```

## Configure

Right-click the widget → **Settings** → paste the credentials:
`VEID` + `API key` (KiwiVM) or `Instance ID` + `API key` (Vultr). They are stored
in `~/.config/vps-traffic/<provider>/env` (mode 600) and never committed.

Or manually:

```bash
mkdir -p ~/.config/vps-traffic/kiwivm && chmod 700 ~/.config/vps-traffic ~/.config/vps-traffic/kiwivm
cat > ~/.config/vps-traffic/kiwivm/env <<'EOF'
KIWIVM_VEID=your_veid
KIWIVM_API_KEY=private_xxxxxxxx
EOF
chmod 600 ~/.config/vps-traffic/kiwivm/env
```

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `provider` | enum | `kiwivm` | Which backend to fetch (`kiwivm`, `vultr`) |
| `refreshIntervalSec` | int | 300 | Poll interval (30–3600) |
| `warnPercent` | int | 80 | Yellow above this usage % |
| `criticalPercent` | int | 95 | Red above this usage % |
| `showPercent` | bool | true | Show the % in the bar |
| `showHost` | bool | false | Prefix the VPS hostname |

Settings live inline in `~/.config/omarchy/shell.json`; set them with
`omarchy bar set kylesean.vps-traffic <key> <value>`.

## Interaction

- **Left click / Esc** — open / close the panel
- **Right click** — settings
- **Wheel** — refresh now; **middle click** — switch provider
- **R / F5** — refresh

## Provider Notes

- **BandwagonHost (KiwiVM)**: Fully verified in production. Reads the counter directly via `getServiceInfo`; traffic is counted bidirectionally and lags ~15 minutes behind real use.
- **Vultr**: *Untested reference backend*. Retained primarily to demonstrate and preserve multi-provider extensibility. Sums monthly outbound egress from `/instances/{id}/bandwidth` against `allowed_bandwidth`. (Community testing and feedback welcome!)
- **Security & Secrets**: KiwiVM authenticates via query parameters, whereas Vultr uses an `Authorization: Bearer` header. The settings helper writes credentials over `stdin` into isolated `mode 600` files and never passes them as command arguments, keeping them out of `ps aux`.

## Roadmap & Contributing

- **Official Marketplace Submission**: Once further verified and polished in daily use, this plugin will be submitted to the official [Omarchy Plugin Marketplace](https://github.com/omacom/omarchy-plugin-marketplace).
- **Feel Free to Fork**: The functional logic is intentionally simple, modular, and lightweight. You are warmly encouraged to **fork** this repository, tailor it to your preferences, or add backends for other providers (e.g. Hetzner, DigitalOcean, Linode).

## Development

```bash
node omarchy/model.test.mjs   # pure-JS contract tests (no node_modules)
omarchy plugin validate .     # manifest + entry-point check
```

Adding a provider = one row in `omarchy/Model.js` (`PROVIDERS` + credentials), one
`case` in `bin/vps-traffic`, and an option in `manifest.json` — the UI adapts automatically.

## License

MIT. Not affiliated with BandwagonHost or Vultr.
