# Reliability and operations

## Supported smoke paths

The macOS runtime needs macOS 14+, a logged-in graphical session, and a visible target window. Grant Accessibility and Screen Recording to **Overseer Computer Use.app**, not Terminal or an agent launcher. The app reports live TCC/preflight state and fails closed when a target is stale, hidden, minimized, or unavailable.

Run local diagnostics with:

```text
overseer computer-use doctor
overseer computer-use diagnostics
overseer computer-use mcp
overseer computer-use call list_apps
overseer computer-use snapshot TextEdit
```

The deterministic fixture and smoke suite require a GUI session and are not headless tests. Linux and Windows runtimes are experimental and have separate desktop-session prerequisites.

## Troubleshooting order

1. Run `overseer computer-use doctor`. If a grant is missing, the native onboarding window opens; a System Settings page opening is not treated as success.
2. Return from System Settings and wait for the card to refresh. If it remains missing, verify that the signed app at `/Applications/Overseer Computer Use.app` is the client listed in the relevant TCC pane.
3. Run `overseer computer-use call list_apps`, then inspect the target with `overseer computer-use snapshot <app>` or `get_app_state`.
4. Refresh state before retrying an action after a window move, Space change, minimization, or target-app update. Element indexes and window-relative coordinates are not durable handles.
5. For update failures, run `overseer computer-use diagnostics`. A candidate is rejected when its checksum, Developer ID Application identity, bundle identifier, team, designated requirement, or notarization is wrong; the existing app remains the rollback source.
6. If telemetry is enabled, failures are intentionally silent and never block MCP tools. Disable it from the privacy setting to remove the local telemetry ID and counters.

## Release invariants

- Public builds require Developer ID Application and Developer ID Installer identities for team `T63VT9UAY2`, plus a notarytool profile.
- Ad-hoc/unsigned builds require `OPEN_COMPUTER_USE_LOCAL_DEVELOPMENT=1` and are development-only.
- The public installer verifies package SHA-256 and Developer ID Installer signature, then verifies the installed app's bundle/team/designated requirement and executable acceptance.
- Updates are checked at launch and at most once per UTC day. Automatic installation is opt-in; candidates are verified before atomic replacement.

Release and CI/CD conventions are described in [`CICD.md`](./CICD.md). No GitHub Actions workflow is required or shipped by this repository.
