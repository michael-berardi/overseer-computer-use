# Overseer Computer Use architecture

## Product identity

The public macOS product is **Overseer Computer Use**, installed as `/Applications/Overseer Computer Use.app`, with bundle identifier `com.libertydesignstudio.overseer-computer-use`. `OpenComputerUse*` names are internal Swift target names only. A release is signed with Developer ID Application and team `T63VT9UAY2`; its designated requirement binds the bundle identifier and team. Updates preserve this identity so TCC grants remain valid after installation and updates.

## Runtime layers

- `apps/OpenComputerUse` is the macOS app and CLI entry point. It runs as an `LSUIElement` app agent when the CLI needs Accessibility, Screen Recording, screenshots, or input simulation.
- `packages/OpenComputerUseKit` contains the MCP stdio transport, permission diagnostics, app discovery, snapshots, input simulation, tool dispatch, telemetry consent/store, and update verifier.
- `apps/OpenComputerUseFixture` and `apps/OpenComputerUseSmokeSuite` provide deterministic local GUI and end-to-end smoke fixtures.
- `apps/OpenComputerUseLinux` and `apps/OpenComputerUseWindows` are experimental runtimes; they are not substitutes for the signed macOS installer.

The external transport is stdio MCP. CLI requests are proxied to the app agent through a local Unix-domain socket in the user's temporary directory. The socket is created with owner-only permissions and uses a per-process capability token; it is not a network listener. Tool payloads stay local.

## Permission onboarding

On first run, the native onboarding window shows truthful Accessibility and Screen Recording cards. Each card reads current TCC/runtime preflight state and refreshes after activation. The `Allow` action calls the appropriate system API and opens System Settings; navigation alone never changes a card to granted. The `Done` state is available only after the system API reports the grant. A new bundle identifier requires one new permission grant; later signed updates retain the same identity.

The onboarding flow is:

1. Show telemetry consent before generating an install ID or making a network request.
2. Offer `Share anonymous usage` and `No thanks`; closing the modal is equivalent to declining.
3. Show missing permission cards and request Accessibility/Screen Recording through macOS APIs.
4. Re-check live state on activation and after returning from Settings.
5. Close automatically only when all required grants are actually present.

## Tools

The MCP server exposes nine tools: `list_apps`, `get_app_state`, `click`, `drag`, `scroll`, `type_text`, `press_key`, `set_value`, and `perform_secondary_action`. Snapshots use an explicit tree/depth budget and action calls refresh state before acting. The runtime fails closed for unsupported or stale elements; it does not pretend that an application root or an off-screen window is actionable.

Actions may be affected by a target app moving, changing Space, becoming hidden/minimized, or enforcing its own input policy. Call `get_app_state` again before retrying. macOS permissions, a logged-in desktop session, and a visible target window are required for the corresponding capabilities.

## Telemetry and privacy

Telemetry is opt-in. Before consent, no event is sent and no install UUID exists. Declining is persisted silently. Disabling telemetry removes the UUID, counters, and cadence markers. After opt-in, the client sends only schema `lds.app-telemetry.event.v2` to `https://analytics.libertydesign.studio/api/app-telemetry/event`:

- event type: launch, at-most-daily heartbeat, or aggregate usage;
- random install UUID, app/version, coarse OS platform, architecture, and UTC day;
- usage events include a lowercase UUIDv4 `batchId`; launch and heartbeat omit it;
- usage counters are moved into an immutable in-flight batch before sending, with later counters stored separately and retries reusing the same batch ID/counters;
- fixed-category tool invocation/success/error counters capped at one million.

It never sends prompts, screenshots, coordinates, app/window names, arguments, file paths, command text, agent/tool payloads, user content, raw IP/UA, secrets, or machine identifiers. Network failures are silent and never block tools.

## Updates and release safety

At launch, and no more than once per UTC day, the app checks the latest stable semver release from `michael-berardi/overseer-computer-use`. The prompt offers `Update now`, `Later`, and `Install updates automatically`; automatic installation is disabled until explicitly selected. Candidates must pass SHA-256, Developer ID Application identity, bundle identifier, team `T63VT9UAY2`, stable designated requirement, and notarization checks. The updater extracts into a private temporary directory, verifies before replacement, atomically moves the current app to a rollback location, installs the candidate, and restores the previous app if replacement fails. A successful update terminates the old process so the next launch uses the verified candidate.

Public release scripts require Developer ID Application, Developer ID Installer, and notarization inputs. Ad-hoc or unsigned output is allowed only for explicit local development flags and can never be used by the public installer or updater. Release artifacts include the signed/notarized app and package, SHA-256 manifests, and a machine-readable release manifest.

## Build and distribution entry points

- `scripts/build-open-computer-use-app.sh`: local debug or signed release `.app` build; release signing/notary inputs are mandatory.
- `scripts/build-overseer-release.sh`: signed/notarized universal app, package, archive, checksums, and manifest.
- `scripts/install-overseer-computer-use.sh`: verifies a stable package and its checksum/signatures, installs to `/Applications`, and creates the `overseer computer-use` command shim.
- `scripts/build-apple-iconset.sh` and `scripts/render-open-computer-use-icon.swift`: generate the original geometric Overseer mark; no proprietary app artwork is required.

Common commands after install:

```text
overseer computer-use mcp
overseer computer-use doctor
overseer computer-use diagnostics
overseer computer-use uninstall
```

The spelling in the examples above is `overseer`; the command is intentionally generic and does not assume Codex, a personal path, or a particular agent vendor.

## Source lineage and maintenance

The project began from `iFurySt/open-codex-computer-use` and retains its MIT license and upstream attribution. The fork intentionally diverges in product identity, bundle signing, permission onboarding, opt-in telemetry, updater safety, packaging, and generic agent installation. See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) for lineage and legal notices. Maintainers should periodically review upstream changes, port relevant fixes with focused tests, and record intentional divergence; proprietary binaries, extracted app bundles, and copied artwork are not distributed.
