# Mac App Store distribution plan

Not started. This is the reference for shipping MicLid through the Mac App
Store, including what was already verified and what would have to change.

## Feasibility — tested 2026-11-17

A probe app was signed with `com.apple.security.app-sandbox` and run on this
Mac. Sandbox enforcement was confirmed (writes redirected into the container,
writes to `/Users/Shared` and `/private/tmp` denied). Inside that sandbox:

| Operation | Result |
|---|---|
| `AudioObjectSetPropertyData` for default input | `0` — succeeded |
| `IOPMrootDomain` → `AppleClamshellState` | read `1` |
| `CGGetOnlineDisplayList` / `CGDisplayIsBuiltin` | worked |

So the App Sandbox does **not** block the core mechanism. The work is policy,
signing and packaging — not capability.

## What must change

### 1. Lid detection (the only real review risk)

`AppleClamshellState` is an undocumented IORegistry property. Guideline 2.5.1
requires public APIs, so a reviewer could reject it even though it works.

Replace it with a public inference:

- laptop check: `sysctlbyname("hw.model")` contains `MacBook`, or a battery is
  present via `IOPSCopyPowerSourcesInfo`
- clamshell: no online display reports `CGDisplayIsBuiltin(id) != 0`, while at
  least one external display is online

This is equivalent for the real scenario. It is also what makes the app safe
on a Mac mini, where there is never a built-in display and therefore no lid.

Recommended: replace `LidState` entirely rather than keeping two paths, and
delete the `IOKit` import. The direct-download build benefits from the same
public-API cleanup.

Update `DeciderTests` for the new `Conditions` shape and keep the matrix
coverage.

### 2. Sandbox entitlement

Add `Resources/MicLid.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

Do **not** add `com.apple.security.device.audio-input`: the app never captures
audio and never requests microphone permission. If a reviewer asks, that is the
answer.

Everything else already behaves under sandbox: `NSStatusItem`, `NSPanel`,
`SMAppService`, `UserDefaults`, and `NSWorkspace.open(x-apple.systempreferences:…)`.

### 3. Signing and packaging

The current ad-hoc `scripts/build-app.sh` cannot produce a store build. Options:

- **Recommended:** add an Xcode project for archives only. `xcodegen` is
  installed on this Mac; keep `Package.swift` as the source of truth and add a
  `project.yml` that points at `Sources/MicLid`, plus the entitlements,
  bundle ID, team, and the App Sandbox capability. Archive and upload from
  Xcode Organizer.
- Or keep SwiftPM and sign manually with the Mac App Store distribution
  certificate plus provisioning profile, then upload with Transporter.

Required:

- Apple Developer Program membership ($99/year)
- Team ID and an Apple Development / Mac App Store distribution certificate
- Bundle ID registered in the developer portal (`com.gabrielathanasiou.miclid`,
  or a new one if taken)
- `CFBundleShortVersionString` / `CFBundleVersion` bumped for each upload
- Release archive built for `arm64` (a universal build is optional)

### 4. Metadata and review material

- App name: **MicLid** — verify availability in App Store Connect; store names
  are globally unique even when the repo name is not
- Category: Utilities; age rating 4+
- Privacy: **Data Not Collected** (no network, no analytics, no audio capture)
- Privacy policy URL — a page hosted from this repo (GitHub Pages) is enough
- Support URL — the GitHub repository or Issues page
- Screenshots: 1280×800, 1440×900, 2560×1600, 2880×1800 (at least one)
- Description and keywords: reuse the README's top section, not its marketing
- Review notes: explain the trigger and that the default mode asks first

## Review risks and mitigations

| Risk | Mitigation |
|---|---|
| Private API (`AppleClamshellState`) | Replace with public display + laptop detection |
| "Modifies system settings" objection | Default is Ask with an explicit 8-second cancel; Automatic is opt-in |
| Auto-switch after countdown seen as unexpected | If rejected, ship the store build with countdown auto-switch disabled — require a click, keep Automatic as an explicit preference |
| App name unavailable | Choose a store-specific name while keeping the bundle name |
| Menu bar-only app questioned | Accepted category; cite other menu bar utilities in review notes |

## Checklist

- [ ] Enrol in the Apple Developer Program
- [ ] Register the bundle ID and create the Mac App Store distribution cert
- [ ] Replace `AppleClamshellState` with public detection; update tests
- [ ] Add sandbox entitlements and an archive build (Xcode project or manual)
- [ ] Build a sandboxed release and run the full manual test pass
- [ ] Write privacy policy + support pages and host them
- [ ] Capture screenshots at the required sizes
- [ ] Create the App Store Connect record and fill metadata
- [ ] Upload, validate, submit for review
- [ ] Keep the direct-download build working (Developer ID + notarization)

## Manual test pass for the sandboxed build

1. Fresh launch on a MacBook in clamshell on an external display
2. Confirm the prompt appears and the countdown switches the input
3. Confirm **Not Now** suppresses until the setup changes
4. Open the lid and confirm the previous input is restored
5. Connect AirPods and confirm the prompt disappears / restore is skipped
6. Toggle **Launch at Login**, log out and back in
7. Check Console for sandbox denials while exercising the menu
8. Repeat on a second user account to catch container assumptions

## Cost and effort

- $99/year for the developer program
- Half a day for the code changes (lid detection, entitlements, tests)
- 1–2 hours for packaging and signing
- 1–2 hours for metadata and screenshots
- Review typically a few days; rejection and resubmission is common

## If the store rejects it

The direct-download build remains the primary distribution. Improve it with a
Developer ID certificate and notarization (`notarytool`), which removes the
Gatekeeper workaround from the README. Other channels: Homebrew Cask, Setapp.
