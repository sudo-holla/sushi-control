# Changelog

## Unreleased

### Added

- Serving statistics can be reset from the dashboard. `Reset stats` starts an app-local window covering totals, request outcomes, cache efficiency, completed-request speeds, mean time to first token and the two trend charts; the snapshot survives app restarts and `Show server totals` returns to the lifetime view. Standard Sushi exposes no statistics-reset endpoint, so the reset is local to the app: when the server restarts and counters move backwards, the stale window is retired and lifetime totals are shown again.
- Saved usage accepts a custom start/end date range in addition to Today, 7 days and 30 days. The date pickers are clamped to the 30 days retained locally, and the panel labels the range that was actually queried.
- GPU and CPU die temperature monitoring, read from the Apple System Management Controller without administrator rights. The dashboard shows a GPU temperature card and a GPU/CPU trend chart next to output, prefill and GPU allocation; Status shows the hottest sensor of each group beside utilization and thermal state; and GPU temperature can be selected as a menu-bar metric or title. Each group is reduced to its hottest sensor, the reading that drives fan speed and clock throttling. Machines that expose no readable sensor show a dash.

## 0.1.0 — 2026-11-05

First standalone release of Sushi Control, a macOS app for launching, monitoring
and controlling a local Sushi inference server.

### Added

- Dashboard controls for a managed Sushi server, with a menu-bar status badge.
- Model library with publisher browsing, local model file import and conversion,
  and model load/unload.
- Admission pause/resume for new requests, available on Status and in the menu bar;
  paused admission shows in the status badge.
- Saved usage and tuning presets.
- Server login startup and crash recovery.
- Optional desktop controller: attach to a compatible controller's authenticated
  `/control/status` and `/control/action` endpoints. The app remembers the selected
  control-token file for the current server and reads the token on launch; the token
  itself is never stored in app preferences, and disconnecting or changing servers
  forgets the file. Controller actions (pause/resume, load/unload) appear alongside
  the server controls.
- Benchmark panel, offline compatibility checks and design previews.

### Documentation

- README focused on Sushi Control, with screenshots of the dashboard, model library
  and integrations; setup, privacy, packaging and private security reporting clarified;
  app documentation and issue links point at this repository.
- Upstream license attribution (Apache-2.0) in `LICENSE-APACHE-2.0` and `NOTICE`.

### Build

- CI runs the offline Swift test suite and the app build on macOS 26 using the
  macOS 26 SDK.
