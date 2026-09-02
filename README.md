# VPS Traffic

Native [Omarchy](https://omarchy.org/) bar widget that shows your VPS provider's
**official billed bandwidth** — used / total, percent, and reset countdown.

Built for [BandwagonHost](https://bandwagonhost.com/) KiwiVM and [Vultr](https://www.vultr.com/).

## Features

- Official counter: used / total / percent, matching the provider panel
- Reset countdown (`17d 2h left`) and exact reset date
- Colour carries the state: calm → yellow past 80% → red past 95% or when suspended
- Click for a panel with the usage meter, plan / location / OS / IP
- Configurable refresh interval; **middle-click** switches provider
- Zero dependencies: one `curl` + `python3` script, pure-JS report model

## Install

Requires `curl` and `python3` (both on Omarchy).

```bash
omarchy plugin add https://github.com/kylesean/vps-traffic --enable
```

Or by hand: copy this folder to `~/.config/omarchy/plugins/kylesean.vps-traffic/`,
run `omarchy-shell shell rescanPlugins`, then `omarchy plugin enable kylesean.vps-traffic`.

Place it in the bar with `omarchy bar put kylesean.vps-traffic --after omarchy.clock`.

> Also listed on [omarchyplugins.com](https://omarchyplugins.com).

## Configure

Right-click the widget → **Settings** → paste the credentials:
`VEID` + `API key` (KiwiVM) or `Instance ID` + `API key` (Vultr). They're stored
in `~/.config/vps-traffic/<provider>/env` (mode 600), never committed.

Or by hand:

```bash
mkdir -p ~/.config/vps-traffic && chmod 700 ~/.config/vps-traffic
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

## Notes

- **KiwiVM** gives the counter directly; traffic is counted bidirectionally and
  lags ~15 minutes behind real use.
- **Vultr** doesn't expose a counter, so the widget sums the monthly
  `outgoing_bytes` from `/instances/{id}/bandwidth` vs `allowed_bandwidth`.
  Vultr bills outbound egress, marks inbound free, resets monthly, and accrues
  hourly — so this is an approximation of the billing view.
- Both provider APIs authenticate via query string, so the key is briefly visible
  in `ps` each poll; the settings helper itself writes the key over stdin and
  never puts it in the process list.

## Development

```bash
node omarchy/model.test.mjs   # pure-JS contract tests (no node_modules)
omarchy plugin validate .     # manifest + entry-point check
```

Adding a provider = one row in `omarchy/Model.js` (`PROVIDERS` + credentials), one
`case` in `bin/vps-traffic`, and an option in `manifest.json` — the UI comes free.

## License

MIT. Not affiliated with BandwagonHost or Vultr.
