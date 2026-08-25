# Contributing to MMMonitor

Thanks for helping make Apple Silicon diagnostics easier to understand.

## Local setup

MMMonitor requires macOS 13 or later on an Apple Silicon Mac, plus Xcode or Apple's Command Line Tools.

```sh
swift build -Xswiftc -warnings-as-errors
swift run MMMonitor
```

Use `swift run MMMonitor --open-settings` when working on settings. Before opening a pull request, also verify the release bundle:

```sh
./scripts/build-app.sh
./scripts/verify-app.sh
```

The app icon source is `Resources/AppIcon.png`. If it changes, regenerate its multi-resolution container with `swift scripts/build-icon.swift Resources/AppIcon.png Resources/AppIcon.icns`.

Release screenshots use representative demo metrics rather than local process or volume names. Regenerate them with `swift run MMMonitor --export-screenshots docs/images`.

## Project principles

- Keep monitoring local and read-only.
- Prefer stable public macOS APIs and graceful unavailable states.
- Avoid administrator requirements, privileged helpers, analytics, and background network services.
- Measure the monitoring overhead introduced by new samplers.
- Gate model-specific telemetry behind capability checks.
- Keep the app useful without an account or cloud service.

## Pull requests

Describe the user-visible change, hardware and macOS version tested, and any measurable CPU or memory impact. Please keep unrelated changes separate and update the changelog when behavior changes.

Sensor support varies across M-series generations. A missing metric is not necessarily a bug in the UI; include a hardware report when diagnosing one.
