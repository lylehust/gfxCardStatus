# gfxCardStatus 2.6 — macOS 15 (Sequoia) compatibility update

## Summary

This update makes gfxCardStatus run on **macOS 15.7.8 (Sequoia)** installed via
**OpenCore Legacy Patcher 2.4.1** on a **2013 early 15" MacBook Pro**
(MacBookPro10,1, Intel HD 4000 + NVIDIA GeForce GT 650M).

No Objective-C source changes were required: the app's core (IOKit
`AppleGraphicsControl` user client, GPU detection, menu bar, notifications)
already works on Sequoia. The changes are build configuration plus tooling.

## Changes

### 1. `gfxCardStatus.xcodeproj/project.pbxproj`

- **`MACOSX_DEPLOYMENT_TARGET` 10.9 → 10.13** (Debug + Release)

  Xcode 26's SDK no longer ships `libarclite`, so linking ARC code with a
  deployment target below 10.13 fails (`SDK does not contain 'libarclite'`).
  10.13 is the lowest target supported by the current toolchain.

- **`MARKETING_VERSION` 2.5 → 2.6**

- **Release code signing → local `Developer ID Application` certificate**

  Previously the Release config referenced `Apple Development` /
  `DEVELOPMENT_TEAM = LF22FTQC25` (the upstream author's certificate), which is
  not available on this machine and prevented Release builds. Now uses a
  local Developer ID certificate. Signing is Manual style.

  Note: the Xcode-produced signature was not notarization-ready (injected
  `get-task-allow`, no secure timestamps, Sparkle's nested `Autoupdate.app` /
  `fileop` left ad-hoc). For distribution the bundle must be re-signed
  inside-out first — see the notarization section below.

### 2. `gfxCardStatus-Info.plist`

- `NSHumanReadableCopyright` → `Copyright © 2010-2026 Cody Krieger, Ye Liu and contributors.`

### 3. `Credits.rtf`

- Added credit line: `macOS 15 (Sequoia) compatibility updates by Ye Liu.`

### 4. Notarization tooling (local only)

Notarization is done with a small local helper script (kept out of version
control, in `script/`) that wraps `xcrun notarytool`:

- Submits an artifact (`.dmg` / `.pkg` / `.app` / `.zip`) for notarization
  using an App Store Connect API key (`--wait`).
- Parses the JSON result; on rejection prints `notarytool log` details.
- Staples the ticket and validates it (for `.zip`: staples the `.app` inside,
  then re-zips).
- Credentials are supplied via environment variables at runtime; no secrets
  are stored in the repository.

## Verification (on the target machine, macOS 15.7.8 x86_64)

- Debug and Release builds succeed with Xcode 26.3.
- App launches; AGC driver connection opens; both GPUs detected
  (`Intel HD Graphics 4000`, `NVIDIA GeForce GT 650M`).
- GPU switching verified in both directions and holds:
  `--discrete` → NVIDIA GT 650M (held 30 s), `--integrated` → Intel HD 4000;
  graceful quit restores dynamic switching.
- `NSUserNotification` delivery confirmed working on Sequoia.
- `build/gfxCardStatus-2.6.dmg` (app + `/Applications` symlink):
  - signed with a local `Developer ID Application` certificate
  - notarized: **Accepted**
  - stapled: `stapler validate` passes
  - Gatekeeper: `spctl --assess` → `accepted (Notarized Developer ID)`

## Artifacts

- `build/gfxCardStatus-2.6.dmg` — notarized, stapled, ready to distribute.
- `/Applications/gfxCardStatus.app` — locally installed signed build.

## Usage

```bash
# build (Release):
xcodebuild -workspace gfxCardStatus.xcworkspace -scheme gfxCardStatus \
    -configuration Release build

# notarize + staple the DMG (helper script is local, in script/):
./script/notarize build/gfxCardStatus-2.6.dmg
```

## Notes

- Intermittent `0xe00002bc` (`kIOReturnError`) on one AGC policy call during
  forced switching is pre-existing driver behavior; it does not block switching
  (matches upstream issues #349/#368/#377).
- Pods (CocoaPods-generated, deployment target 10.9) produce harmless warnings.
- If distributing outside this machine, re-signing the app bundle with
  `--timestamp --options runtime` and empty entitlements is required before
  packaging (see the notarization notes above).
