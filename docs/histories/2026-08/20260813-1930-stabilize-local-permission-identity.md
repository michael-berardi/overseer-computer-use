# Stabilize local permission identity

## User request

Repair OverSeer Computer Use after its macOS Accessibility and Screen Recording permissions stopped applying.

## Changes

- Added explicit `grave`, `backquote`, and `backtick` key aliases so `press_key` can emit the UltraTerm Option+Backquote shortcut.
- Added optional notarization and stable-path installation to the macOS app build script.
- Verify signatures after building and installing; verify Gatekeeper and stapling when notarization is enabled.
- Documented that replacing an authorized ad-hoc app with a differently signed build invalidates the prior TCC identity.

## Design

macOS TCC binds grants to code identity, not only bundle identifier or display name. Local automation now has one command that signs, notarizes, staples, installs, and verifies the same app artifact at a stable path, avoiding silent identity drift.

## Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/KeyMapping.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `README.md`
- `docs/ARCHITECTURE.md`
