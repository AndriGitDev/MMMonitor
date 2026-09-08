# Changelog

## 0.4.0 — 2026-09-08

- added battery design and full-charge capacity details where available
- added optional persisted one-day history with minute-level aggregation and an explicit clear action

## 0.3.1 — 2026-09-08

- added a one-click DNS cache flush action to the Network card
- kept elevated access scoped to a fixed, user-initiated command with no persistent privileged helper

## 0.3.0 — 2026-08-25

- replaced the single menu-bar reading with a configurable multi-metric layout
- added compact, balanced, network, and full menu-bar presets
- added left-to-right menu-bar metric ordering and an optional app icon
- added an optional live CPU sparkline to the menu bar
- stabilized value widths to prevent the menu-bar layout shifting as readings change
- made unavailable battery state explicit on desktop Macs
- added a clear dashboard empty state for Macs without an internal battery
- distinguished initial, unavailable, and disconnected states in network and storage cards
- added a fixed-width charging marker to the menu-bar battery reading
- moved settings to a standalone window so live samples cannot interrupt control interaction
- kept refresh and history controls connected even when the dashboard is closed
- added Command-comma settings access and richer menu-bar accessibility summaries
- stopped unsupported removable volumes from generating periodic capacity-query errors
- made release builds fail on compiler warnings
- made release checksums portable and added archive-integrity verification
- removed machine-specific Finder metadata from release archives
- made app builds use a fresh staged bundle so stale resources cannot leak into releases
- fixed sustained alerts so a persistent condition can notify again after its cooldown
- added MMMonitor's production app icon and reproducible ICNS build tooling
- added reproducible privacy-safe release screenshots rendered from the real SwiftUI views

## 0.2.0 — 2026-08-24

- added per-core CPU activity
- added swap usage and expanded battery diagnostics
- added top-process sampling with CPU and resident memory
- added thermal state, uptime, and load averages
- added selectable dashboard modules and menu-bar metrics
- added configurable sampling intervals
- added launch-at-login support
- added reproducible release packaging and verification
- added user-triggered JSON snapshot export
- added mounted local-volume monitoring
- added selectable per-interface network monitoring
- added compact and comfortable dashboard density options
- added opt-in sustained-threshold notifications and cooldowns
- added selectable 1-, 15-, and 60-minute live history
- added configurable notification quiet hours
- added persistent dashboard module ordering

## 0.1.0 — 2026-08-24

- initial native menu-bar dashboard
- added CPU, memory, network, disk, and battery monitoring
- added 60-second live graphs
- added local Apple Silicon app packaging
