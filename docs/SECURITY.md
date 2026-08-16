# Overseer Computer Use security contract

- macOS automation runs in the signed `Overseer Computer Use.app` bundle (`com.libertydesignstudio.overseer-computer-use`), not in Terminal, the MCP host, or the command shim.
- Accessibility and Screen Recording are requested through system APIs and checked with live runtime preflight/TCC. Opening a System Settings pane never marks a permission as granted.
- The local app-agent Unix socket is owner-only, temporary, same-user, and nonce-authenticated; no TCP listener is opened.
- `click_method=global` remains an explicit opt-in because it can move the user's pointer or alter focus. The default action paths are process-directed where supported.
- Telemetry is opt-in. The v2 payload is closed to `schema`, `app`, `event`, `installId`, `version`, `platform`, `arch`, `day`, and (only for `usage`) lowercase UUIDv4 `batchId` plus fixed counters for the nine supported Computer Use tools. Launch and heartbeat forbid `batchId`; usage batches are immutable while in flight and retries reuse their batch ID/counters. No user content or dynamic tool data is allowed. Identifier rows expire within 34 UTC days; ID-free daily totals within 360 days. `overseer computer-use telemetry disable` deletes all local telemetry state.
- Update checks use the latest stable release from `michael-berardi/overseer-computer-use` at launch and at most daily. Install requires checksum, Developer ID identity/team/bundle/designated requirement, and notarization verification; failed replacement rolls back.
- Experimental Linux and Windows runtimes have platform-specific accessibility and foreground limitations and do not claim macOS TCC equivalence.
