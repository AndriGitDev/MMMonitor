# Security Policy

## Supported versions

Security fixes are applied to the latest source and the current GitHub release. Older releases are not supported.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature. Do not open a public issue for a vulnerability that could expose local data, execute code, or bypass macOS protections.

For ordinary non-sensitive bugs, use the repository issue tracker and omit personal paths, process names, exported snapshots, or other identifying system details unless they are essential and have been reviewed first.

MMMonitor is intended to remain local-only and free of persistent privileged helpers. DNS cache flushing is user-initiated, uses a fixed command with no dynamic input, and requires the normal macOS administrator authorization flow. Keep Awake is also user-initiated, uses public unprivileged IOKit power assertions, and releases them when the session stops, expires, changes mode, or the app quits. A change that broadens those privileges or weakens any of these boundaries should be treated as security-sensitive.
