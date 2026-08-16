# Security and privacy

## Reporting

Please report a suspected vulnerability privately to the repository maintainers before opening a public issue. Include the affected version, operating system, reproduction steps, impact, and any safe mitigation. Do not include credentials, personal data, screenshots, or user content.

## Trust boundaries

Overseer Computer Use is local-first. The signed macOS app owns Accessibility and Screen Recording permissions; the `overseer` shim and MCP host communicate with it over an owner-only Unix socket in the user's temporary directory. The socket is not a network listener and requests are authenticated for the same user. The runtime never grants TCC access merely because System Settings opened.

## Telemetry

Telemetry is undecided until the first-run modal. No network request or install identifier exists before opt-in. Opt-in events use `lds.app-telemetry.event.v2` and contain only the fixed launch/heartbeat/usage allowlist documented in the README. Usage events carry a lowercase UUIDv4 `batchId`; launch and heartbeat forbid it. Usage counters are persisted as an immutable in-flight batch for retry, and counters recorded later are kept separately. They exclude prompts, screenshots, coordinates, app/window names, arguments, paths, command text, user content, raw IP/UA, secrets, and machine identifiers. Failures are silent and cannot block a tool call. Disabling telemetry deletes the local identifier, counters, in-flight batch, and cadence markers.

## Update supply chain

Public releases require Developer ID Application and Developer ID Installer identities for team `T63VT9UAY2`, notarization, a stable designated requirement, and published SHA-256 checksums. The updater verifies all of these before an atomic replacement, keeps a previous app for rollback, and never uses an ad-hoc candidate as a public update. Local ad-hoc signing is available only with an explicit development flag.
