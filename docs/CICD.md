# Release pipeline

Public releases are built locally or by an approved external runner; this repository intentionally contains no GitHub Actions workflow. The canonical entry point is `scripts/build-overseer-release.sh`.

Required release inputs:

- `OPEN_COMPUTER_USE_CODESIGN_IDENTITY`: Developer ID Application identity for team `T63VT9UAY2`.
- `OPEN_COMPUTER_USE_INSTALLER_IDENTITY`: Developer ID Installer identity for the same team.
- `OPEN_COMPUTER_USE_NOTARYTOOL_PROFILE`: configured `notarytool` keychain profile.
- Optional `OPEN_COMPUTER_USE_RELEASE_VERSION`: semver override.

The pipeline builds a universal `Overseer Computer Use.app`, checks the stable bundle identifier and designated requirement, creates a signed/notarized `Overseer-Computer-Use.pkg` and archive, staples the package, and writes `SHA256SUMS` plus a stable `release-manifest.json`. It hard-fails when signing or notarization inputs are missing. Ad-hoc or unsigned output is available only for explicit local development through `OPEN_COMPUTER_USE_LOCAL_DEVELOPMENT=1` and never feeds an installer or updater.

Suggested operator checks (not run as part of source changes):

```bash
OPEN_COMPUTER_USE_CODESIGN_IDENTITY='Developer ID Application: Name (T63VT9UAY2)' \
OPEN_COMPUTER_USE_INSTALLER_IDENTITY='Developer ID Installer: Name (T63VT9UAY2)' \
OPEN_COMPUTER_USE_NOTARYTOOL_PROFILE='profile' \
  ./scripts/build-overseer-release.sh
pkgutil --check-signature dist/release/overseer-computer-use/<version>/Overseer-Computer-Use.pkg
shasum -a 256 -c dist/release/overseer-computer-use/<version>/SHA256SUMS
```
