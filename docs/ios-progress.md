# iOS implementation handoff — 2026-09-28

## Objective and current state

Implement the full [iOS PRD](ios-prd.md), including the Mac/TUI changes, and release iOS demos to TestFlight on every push to `main` using `../wariwari-ios` as an example. The goal is **active**. Do not mark it complete until the PRD's device, widget, accessibility, Calendar, notification, Shortcuts, and Live Activity checks have evidence. The user has installed and opened a TestFlight app on an iPhone, but has not yet supplied the device model, iOS version, installed build number, dashboard screenshot, or feature results.

The app, widgets, Shortcuts, Live Activity, Mac EventKit integration, TUI timer removal, shared period calculations, and TestFlight workflow have been implemented and pushed to `main`. See [device checklist](ios-device-checklist.md) for evidence and remaining physical-device checks. The latest **processed and available** TestFlight build verified before this note was `0.1.0 (20.1)`.

## Release in progress

- Latest pushed commit: `e898f23f5e64` — **Entitle iOS app and widgets for shared App Group data**. It adds `com.apple.security.application-groups` with `group.com.davafons.timescale.ios` to `iOS/TimescaleIOS.entitlements`, which is referenced by both Xcode targets. This fixed an empty entitlements file that could prevent app/widget data sharing on signed builds.
- GitHub Actions run: `36377246722`, https://github.com/davafons/timescale/actions/runs/36377246722 . At 2026-09-28 04:20 UTC it was **in progress**, in the Archive step. The interrupted `gh run watch` was only an observation; it did not cancel the workflow. Recheck the run with `gh run view 36377246722 --repo davafons/timescale --json status,conclusion,jobs,url` or watch it. This should be build `0.1.0 (21.1)` if successful.
- After upload, check App Store Connect processing and internal group availability. The agent-owned Brave wrapper activity is `timescale-testflight`: `~/bin/playwright-cli --activity=timescale-testflight ...`. If its session is gone, run `attach --extension`; stay in the verified owned tab group. Apple Developer showed **App Groups checked, Enabled App Groups (1)** for both `com.davafons.timescale.ios` and `com.davafons.timescale.ios.widgets`. No Apple portal changes are pending.
- The three GitHub App Store Connect secrets are configured. Never print the private key. Workflow is `.github/workflows/testflight-ios.yml`: Xcode 27, unsigned archive followed by signed export/upload with the App Store Connect API key. Earlier CI runs through build 20.1 succeeded, and builds appeared in the internal TestFlight group.

## Working copies and rules

- Shared repo: `/Users/davafons/workspace/timescale`. It has `.jj`. **Use jj, never mutating git. Keep development on a single linear trunk on top of `main`; rebase and resolve overlaps with the latest implementation as needed. Preserve other agents' unrelated changes.**
- Isolated publication checkout: `/tmp/timescale-ios-release-20260928`. It has `.jj`; its `@` was empty at `8515a46b`, parent `e898f23f main`, at the time of this note. This isolated checkout is historical. Continue development and publication from the shared repo on a single trunk above `main`, using jj and the user's push aliases.
- This handoff note is saved in the shared repo only. It has **not** been copied to the isolated checkout or pushed, so it does not trigger another TestFlight build.
- User's shared-desktop instruction prohibits native GUI activation or system-wide mouse/keyboard input without explicit permission for that run. Browser work through the configured browser skill's owned Brave group is pre-authorized. Headless `simctl` work has been used without opening Simulator.app. An earlier request for native GUI permission to place/capture widgets has no reply yet; do not assume authorization.
- Developer instruction: do not add or run tests unless the user asks. Simulator builds have been used to confirm edits compile.

## Evidence already collected

- `swift test`: 40 Swift tests passed previously, including 11 iOS contract tests. `cargo test --workspace`: 31 Rust tests passed previously. Several simulator Debug builds passed, most recently after the App Group entitlement change. `plutil -lint iOS/TimescaleIOS.entitlements` passed.
- Agent-owned headless iOS 26.5 iPhone 17 Pro simulator was used for fresh install/launch, check-in count, Calendar denied/granted state, missing selected calendar state, dark/high-contrast/large-text dashboard capture. It is shut down. Screenshots are in `artifacts/ios/` (`dashboard.png`, `dashboard-fresh-install.png`, `dashboard-configured.png`, `dashboard-large-dark.png`). The unsigned simulator app does not prove signed App Group sharing or actual Home/Lock Screen widget layout.
- User reported installing and opening the app on iOS. This establishes physical installation/launch, but the build/version and visual or behavior results are unknown.
- Build 20.1 was verified as ready for the internal TestFlight group in App Store Connect. The group distributes builds automatically.

## Most important next work

1. Check run `36377246722`. If it fails, inspect the archive/export logs and fix the App Group signing/provisioning issue. If it succeeds, verify build 21.1 finishes processing and joins the internal group in App Store Connect.
2. Obtain physical iPhone results for build 21.1 or later: device/iOS/build, first-run dashboard showing day/week/month/quarter/year, Home and Lock Screen widgets (including Day Ring, Year Number, Overview), widget tap check-in count, Calendar and subscribed HEY behavior, reminders, Shortcuts, Live Activity, accessibility and widget freshness. The pending question to the user asks for build/iOS/dashboard results; avoid repeatedly asking the same question.
3. Capture representative Home and Lock Screen widget screenshots only with user-provided screenshots or explicit native GUI permission for an agent-owned window/session. Browser permission does not authorize native Simulator GUI input.
4. Continue a requirement-by-requirement audit of `docs/ios-prd.md`. Do not infer physical behavior from code, simulator dashboard screenshots, or a successful upload. Keep the goal active until every explicit acceptance item and delivery artifact is proven.

## Recent code changes

- Build 18.1: Settings explains denied notification permission.
- Build 19.1: Dashboard updates progress every 30 seconds while active and refreshes Calendar data after 15 minutes in foreground.
- Build 20.1: Manual latitude/longitude fields retain partial negative and decimal input; valid values are range checked.
- Pending build 21.1: App and widget App Group entitlement.

Do not put App Store Connect private key material, provisioning certificates, or user personal data in this file.
