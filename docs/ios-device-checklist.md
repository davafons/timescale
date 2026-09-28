# iPhone release review

Use a physical iPhone on iOS 18 or later with a fresh install. Record the device, OS version, build, and result for each item before inviting TestFlight testers.

| Area | Check | Expected result |
| --- | --- | --- |
| First launch | Launch without granting any permission. | Day, week, month, quarter, and year appear immediately; no account is requested. |
| Calendar | Deny access, then grant access and select two calendars with overlapping events. | The dashboard and calendar widget explain unavailable data when denied; permitted events appear once with their source. |
| HEY subscription | Add a HEY calendar subscription in Apple Calendar and select it in Timescale. | Events appear in the dashboard and widget after Calendar refresh; an unavailable subscription is labeled stale. |
| Location | Deny location, then enable automatic location. | The dashboard remains usable when denied; sunrise and sunset use the current location after approval. |
| Notifications | Deny and then allow reminders; set overnight waking hours and a short threshold. | Denial is clear; reminders begin only after a check-in, stay within waking hours, and occur once per qualifying gap. |
| Check-ins | Open from a widget and a notification, then navigate inside the app. | Each external open records one check-in; in-app navigation and passive widget display record none. |
| Home widgets | Place Day Ring, Year Number, and Overview widgets together. Configure the two single-period widgets independently. | Each instance keeps its chosen period; shared styling applies to all; Overview follows the visible dashboard periods. |
| Lock widgets | Add circular, rectangular, and inline variants where offered. | Text and progress remain legible in grayscale and tinted rendering; sensitive calendar titles and life values match product settings. |
| Widget freshness | Change display mode, color, precision, visibility, calendar selection, and time zone. | Widgets refresh at the next allowed timeline update; compact numeric views show age or time context. |
| Accessibility | Review dashboard and widgets with VoiceOver, largest Dynamic Type, Reduce Motion, and high contrast. | Labels include period, mode, value, and boundaries; progress is understandable without color. |
| Live Activity | Start a period bar, background the app, change period settings, reopen, and stop it. | It begins only from the foreground, remains a temporary session of at most eight hours, reconciles after setting changes, and stops on request. |
| Shortcuts | Run Get Progress, Get Visible Progress, and Check In. | Progress results include boundaries, fractions, remaining time, 1% duration, and calculation time; Check In adds one history item and resets reminders. |

## Build evidence

- `swift test`: 40 Swift tests passed on 2026-09-28, including eleven iOS contract tests.
- `xcodebuild` simulator Debug build: passed on 2026-09-28.
- Release archive, signed export, and App Store Connect upload: passed on 2026-09-28; build 0.1.0 (15.1) reached internal testing.
- A TestFlight build was installed and opened on an iPhone on 2026-09-28; device version, build number, and first-launch results are being collected.
- Fresh iOS 26.5 iPhone 17 Pro simulator install: the dashboard opened without a permission prompt, with Day, Week, and Month visible in the initial viewport. It recorded one app-open check-in; a separate relaunch recorded one more. A direct `simctl openurl` stopped at iOS's first-use confirmation, so the widget-tap check remains pending.
- On that agent-owned simulator, revoking Calendar access left the dashboard launchable and saved the denied state with no event cache; granting access and relaunching cleared the denied state and created an empty event cache. Event display and subscribed-calendar behavior still need device checks.
- With Calendar access granted and a selected ID that did not exist, the simulator saved a missing-calendar count of one. The widget now uses that state for its unavailable message; its actual Home/Lock Screen rendering remains to be reviewed.
- Dashboard screenshot: `artifacts/ios/dashboard.png`.
- Fresh-install simulator screenshot: `artifacts/ios/dashboard-fresh-install.png`.
- Configured dashboard with sun, birthday, and life context: `artifacts/ios/dashboard-configured.png`.
- Large text, dark mode, high-contrast simulator screenshot: `artifacts/ios/dashboard-large-dark.png`.

Home and Lock Screen widget captures and the physical-device checks above remain to be recorded.
