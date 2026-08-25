# Roadmap

MMMonitor is moving faster than the original estimate: the native foundation and first diagnostics release were completed in the opening session. The estimates below are focused development time, not promises about undocumented hardware behavior.

## Shipped locally — 0.2

- [x] CPU, per-core activity, memory, swap, disk, network, and battery
- [x] selectable 1-, 15-, and 60-minute CPU, memory, and network graphs
- [x] top CPU processes and resident-memory use
- [x] battery health and cycle count
- [x] thermal state, uptime, and load averages
- [x] configurable refresh interval and visible modules
- [x] selectable menu-bar metric
- [x] launch at login
- [x] native Apple Silicon app bundle and reproducible GitHub artifact workflow
- [x] user-triggered JSON snapshot export

## Shipped locally — 0.3

- [x] glanceable multi-metric menu-bar layout
- [x] compact, balanced, network, and full menu-bar presets
- [x] independently toggle and reorder menu-bar metrics
- [x] stable-width readings and optional menu-bar icon
- [x] optional fixed-width CPU sparkline in the menu bar
- [x] standalone settings window isolated from live dashboard redraws
- [x] keyboard access to settings and expanded VoiceOver summaries

## Next focused session — roughly 1–2 hours

- [x] choose and inspect individual network interfaces
- [x] show mounted local volumes
- [x] sort top processes by CPU or memory
- [x] expand the process list on demand
- [x] compact and comfortable dashboard density options
- [x] About panel with build information
- [x] improve empty and unavailable states for network, storage, battery, and processes

## Following session — roughly 2–4 hours

- [x] threshold notifications for CPU, memory, disk, battery, and thermal state
- [x] notification cooldowns
- [x] configurable notification quiet hours
- [x] selectable one-hour in-memory history
- [ ] optional persisted one-day history with an explicit clear action
- [x] rearrangeable modules
- [x] export a point-in-time JSON report

## Deeper diagnostics — several focused sessions

- [ ] process detail view with threads and energy impact where available
- [ ] efficiency/performance core grouping
- [ ] battery design and full-charge capacity details
- [ ] GPU activity and memory use
- [ ] CPU/GPU power and frequency
- [ ] available temperature sensors
- [ ] fan speed on supported hardware

Apple does not expose every M-series sensor through stable public APIs. Experimental telemetry will be isolated behind capability checks and validated across hardware models. Read-only monitoring comes first. Fan control, if ever added, will be a separate opt-in component and will not be required by the main app.

## Public release checklist — roughly 1–2 hours after feature freeze

- [x] choose and integrate the app icon
- [x] capture privacy-safe dashboard and menu-bar settings screenshots
- [x] add contributor and security guidance
- [x] document data sources, permissions, and sampling cadence for IT review
- [x] exclude local build products from source control
- [x] initialize and review the Git history
- [x] create the public GitHub repository
- [x] publish a checksummed release archive
- [x] gather hardware reports through a structured issue template

App Store distribution remains intentionally out of scope. Notarized GitHub builds and a Homebrew Cask can be considered after the release process stabilizes.
