# Changelog

All notable changes to this project are documented here.
This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-02

### Added
- Omarchy bar widget showing a VPS provider's official billed bandwidth usage.
- BandwagonHost (KiwiVM) backend via `getServiceInfo` — native used/total/reset.
- Vultr backend via `/instances/{id}` + `/instances/{id}/bandwidth` — sums the
  current month's outbound egress vs `allowed_bandwidth`.
- In-panel details: usage meter, percent, reset countdown, plan/location/OS/IP.
- Provider registry + middle-click provider cycle + settings selector.
- Per-provider credentials (`~/.config/vps-traffic/<provider>/env`, mode 600,
  atomic write over stdin).
- Contract tests in `omarchy/model.test.mjs` and a `bin/vps-traffic` CLI.
