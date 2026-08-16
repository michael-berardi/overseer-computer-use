# Overseer Computer Use

Overseer Computer Use is a local, open-source Computer Use runtime for supported AI agents. It exposes a stdio MCP server and a small command line interface; automation runs on the user's machine and never requires a hosted dashboard.

## Install

### macOS release installer

Prerequisites: macOS 14 or later, an Apple Silicon or Intel Mac, an interactive logged-in desktop session, and an agent that supports MCP/stdio. The public installer is a signed and notarized `Overseer-Computer-Use.pkg` from the latest stable release.

```bash
curl -fsSL https://raw.githubusercontent.com/michael-berardi/overseer-computer-use/main/scripts/install-overseer-computer-use.sh | bash
```

The installer downloads the latest stable package and its SHA-256 manifest, verifies the checksum before invoking `installer`, and places the app at `/Applications/Overseer Computer Use.app`. It never accepts an unsigned or ad-hoc release. For a local checkout, run `./scripts/install-overseer-computer-use.sh --local dist/Overseer\ Computer\ Use.pkg`.

### Agent setup

The installer places a generic `overseer` command in `~/.local/bin`. Add that directory to `PATH`, then run:

```bash
overseer computer-use doctor
# Start the stdio MCP server for any MCP-capable agent:
overseer computer-use mcp
```


(There is no agent-specific integration requirement. Configure your host's MCP entry with command `overseer` and arguments `["computer-use", "mcp"]`.)

## Permissions and first run

```bash
overseer computer-use doctor
```

The app shows a dark control-room onboarding window with truthful Accessibility and Screen & System Audio Recording cards. Choose **Allow** to request the corresponding macOS API and open System Settings. A card becomes **READY** only after macOS preflight/TCC reports the grant; opening a settings pane is never treated as success. Refresh happens while the window is active. The new bundle identity requires one final grant after upgrading from a legacy build; it then remains stable across installs and verified updates.

The first run also asks whether to **Share anonymous usage** or choose **No thanks**. Declining is silent and persistent. Run `overseer computer-use telemetry status|enable|disable` at any time; disabling deletes the local identifier, queued counters, and cadence markers.

## Commands

```bash
overseer computer-use doctor                 # permissions and local trust diagnostics
overseer computer-use list-apps              # targetable running/recent apps
overseer computer-use tools                  # supported tool catalog
overseer computer-use snapshot TextEdit      # read-only accessibility state
overseer computer-use call get_app_state --args '{"app":"TextEdit"}'
overseer computer-use mcp                    # stdio MCP transport
overseer computer-use telemetry status       # inspect opt-in state; enable/disable explicitly
```

Supported tools: `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, and `set_value`. Use `--help` for all options.

## Updates, uninstall, and diagnostics

Stable update metadata is checked at launch and at most once per UTC day. The prompt offers **Update now**, **Later**, and **Install updates automatically**. Automatic installation is opt-in. Every candidate must pass SHA-256, Developer ID Application identity, bundle identifier/team/designated requirement, and notarization checks before an atomic replace. The previous app is retained until replacement succeeds; failed replacement rolls back and leaves the running install unchanged.

```bash
# Check installed identity and permissions
overseer computer-use doctor --json
# Download and apply the latest verified release (interactive prompt is preferred)
overseer computer-use update
# Remove app, command shim, and host configuration
overseer computer-use uninstall
# Print local socket and signing diagnostics
overseer computer-use diagnostics
```

The Unix socket used between the command shim and the signed app agent lives in the user's temporary directory, is created with owner-only permissions, and is authenticated by a per-request nonce. It accepts local same-user clients only; it is not a network listener. Tool payloads stay local.

## Privacy and security

Telemetry is opt-in only. Before consent, there is no network request and no install UUID. Opt-in payloads use schema `lds.app-telemetry.event.v2` and contain only the app key, event (`launch`, `heartbeat`, or `usage`), random install UUID, semver, coarse platform/architecture, UTC day, and the fixed Computer Use counters. Usage events additionally carry a lowercase UUIDv4 `batchId`; launch and heartbeat events never do. Usage counters are persisted in an immutable in-flight batch for retries, while later counters accrue separately. No prompts, screenshots, coordinates, app/window names, arguments, paths, command text, user content, raw IP/UA, secrets, or hardware identifiers are sent. Identifier rows expire within 34 UTC days; ID-free daily totals within 360 days. Failures are silent and never block tools. See [`SECURITY.md`](./SECURITY.md) and [`docs/SECURITY.md`](./docs/SECURITY.md).

Computer Use can control visible applications after the user grants macOS permissions. It does not bypass TCC, cannot guarantee equivalent background input for every toolkit, and does not promise cross-compositor parity on experimental Linux/Windows runtimes. Coordinate actions can be affected by a window moving between snapshot and action; refresh state before retrying.

## Source lineage and license

This repository began from the open `iFurySt/open-codex-computer-use` project and preserves its MIT license and upstream attribution. Overseer Computer Use diverges in product identity, permission onboarding, telemetry consent, signed update safety, packaging, and generic agent setup. Upstream source and commit lineage are documented in [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md). Maintainers should periodically review upstream changes, port relevant fixes with tests, and record intentional divergence; no proprietary app bundle or extracted artwork is required or shipped.
