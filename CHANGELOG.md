# Changelog

## Unreleased

No changes since 0.1.0.

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
