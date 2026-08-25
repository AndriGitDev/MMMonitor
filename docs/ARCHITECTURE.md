# MMMonitor Architecture and IT Review

MMMonitor is a single native `arm64` menu-bar application. It runs as a macOS UI agent (`LSUIElement`) and has no daemon, privileged helper, kernel extension, browser component, account, or cloud service.

## Data flow

```text
Public local macOS APIs → in-process sampler → in-memory snapshot/history → menu bar and dashboard
                                                       └───────────────→ optional local notification
                                                       └───────────────→ user-requested JSON export
```

Monitoring data stays in the MMMonitor process. It is not transmitted and is not automatically written to disk.

## Local data sources

| Metric | Local API or framework |
| --- | --- |
| CPU and per-core activity | Mach `host_processor_info` |
| Memory and swap | Mach host statistics and `sysctl` |
| Network throughput | Darwin `getifaddrs` interface byte counters |
| Disk capacity and mounted volumes | Foundation file and volume resource values |
| Battery and charge state | IOKit power-source APIs |
| Battery health and cycles | read-only IOKit registry properties |
| Top processes | read-only `libproc` task summaries |
| Thermal state and uptime | Foundation `ProcessInfo` |
| Load averages | Darwin `getloadavg` |

MMMonitor calculates rates from counter differences. It does not inspect network packets, destinations, file contents, keystrokes, window contents, or process arguments.

## Sampling cadence

The user chooses a one-, two-, or five-second main refresh interval. More expensive or slowly changing values are cached:

- top processes: five seconds
- battery details: 30 seconds
- disk and mounted-volume capacity: 60 seconds

The optional menu-bar sparkline reuses existing in-memory CPU samples and creates no extra sampling work.

## Storage

- Preferences are stored in the app's standard macOS `UserDefaults` domain.
- Live graph history is memory-only and is discarded when the app quits.
- A JSON snapshot is created only when the user chooses Copy Snapshot or Save Snapshot.
- MMMonitor has no database, analytics SDK, update service, or background network client.

## Permissions and persistence

MMMonitor requires no administrator access. Optional features may prompt through normal macOS controls:

- **Notifications**: requested only when threshold alerts are enabled.
- **Launch at login**: registered through `SMAppService`; macOS may require approval in Login Items.

Disabling launch at login and removing `MMMonitor.app` stops all executable persistence. Preferences can be removed separately through the standard defaults domain `local.mmmonitor.app` if desired.

## Release trust

Local development archives are ad-hoc signed and checksummed. A future public GitHub release may be Developer ID signed and notarized, but App Store distribution is intentionally out of scope. Organizations can reproduce the arm64 build from source with `scripts/build-app.sh` and validate it with `scripts/verify-app.sh`.
