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

- **Release code signing → ad-hoc (Manual), local re-signing for distribution**

  Previously the Release config referenced `Apple Development` /
  `DEVELOPMENT_TEAM` (the upstream author's certificate), which is not
  available on this machine and prevented Release builds. Now the project uses
  ad-hoc signing (no personal signing identity in the repository); the final
  artifact is re-signed locally with a `Developer ID Application` certificate
  before packaging (see the notarization section below).

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

## 2026-08-17 — Bug-fix round (code review findings)

### Build fix (blocker)

- The working tree had every committed symlink flattened into regular files
  (`Pods/Headers/*`, `Sparkle.framework/*`), which broke clean builds: RAC 1.x
  headers have no include guards, so the duplicate header copies produced
  `duplicate interface definition for class 'RACDisposable'` etc., and Xcode
  complained about the broken `Sparkle.framework/Versions/Current` symlink.
  Restored the committed symlinks (`git checkout -- Pods/Headers
  Sparkle.framework`). Debug + Release build cleanly again.
  ⚠️ Copy/zip the repo symlink-preservingly, or this silently breaks builds.

### Functional fixes

- **Main-thread AppKit**: the GPU-change delegate callback is now delivered on
  the main queue instead of the notification thread (GSGPU.m) — previously
  `updateMenu` touched `NSStatusItem`/`NSUserNotificationCenter` off-main.
- **1s UI freeze removed**: forced switches run their settle delay + `forceSwitch`
  on a background queue (GSMux.m `setMode:`); dynamic/toggle paths unchanged and
  still synchronous (they were always fast — quit/shutdown path unaffected).
- **`setMode:` now reports real IOKit results** instead of always `YES`, and the
  uninitialized `uint64_t output` in `isUsingIntegratedGPU` /
  `isUsingDynamicSwitching` is zeroed (no more garbage GPU state on failure).
- **`switcherOpen` closes the connection** if the `kOpen` call fails.
- **ReactiveCocoa ripped out of the app code** (was dead: RAC's KVO on
  `prefsDict.<key>` key paths can never fire for `NSMutableDictionary` keys, so
  the "Load at startup" toggle was broken — it could never be turned off).
  Replaced with `GSPreferencesDidChangeNotification` posted by
  `savePreferences`; the General prefs checkboxes now wire target/action in
  `loadView` so toggles persist + apply side effects immediately
  (`loadAtStartup`, updater sync, menu icon refresh).
  Note: the RAC pod itself is still in Pods/ (no CocoaPods on this machine);
  once `pod` is available: remove the `pod 'ReactiveCocoa'` line from the
  Podfile (and bump `platform :osx, '10.13'`), then run `pod install`.
- **IORegistry hardening** (GSGPU.m `getGPUNames`): missing/typed `model`
  values no longer crash (`addObject:nil` → exception) — model data is read up
  to its NUL terminator, bounded by buffer length; `io_iterator_t` and each
  `io_registry_entry_t` are now released (leaks fixed).
- **GSProcess hardening**: `task-list` key absence no longer crashes
  (`CFArrayGetCount(NULL)`); proc-name read is bounded by the sysctl result;
  per-task `NSNumber` leak removed.
- **Menu bar icon**: nil/empty GPU names fall back to "Integrated"/"Discrete"
  instead of crashing (`characterAtIndex:0` on empty string).
- **Preferences toolbar**: `setModules:` now clears all toolbar items (was
  keeping item 0 — latent bug if modules ever change).

### Verification

- `xcodebuild ... -configuration Debug` and `Release` both **BUILD SUCCEEDED**
  (Xcode 26.6); built app reports CFBundleShortVersionString 2.6.
- Runtime behavior (GPU switching, login item, notifications) still needs a
  smoke test on the target machine (macOS 15.7.8 / OCLP 2013 MBP).
