# Timescale for iOS — product requirements

Status: implementation brief. Updated 28 September 2026.

## Product

Timescale helps a person see how much of meaningful periods has elapsed. The iPhone app should preserve the Mac popover's quiet, readable dashboard, while making widgets a first class way to use it. Success means that someone can place several distinct Timescale widgets on the Home Screen and Lock Screen, understand them at a glance, and open one consistent dashboard for detail.

The first release targets iPhone on iOS 18 or newer, initially for personal use and TestFlight. It requires no Timescale account. iPad, Apple Watch, cross-device sync, file import/export, and named widget presets are later work. The iPhone data store is independent of the existing Mac/TUI configuration at launch.

The app and widgets have equal priority for single-period and multi-period views; Home Screen and Lock Screen have equal priority. Widgets should offer both different combinations of information and different visual treatments. The design vocabulary starts with bars, rings, and large numbers. The interface is English with device-local date and time formatting.

## Existing product to carry forward

- Waking-day progress with configurable start and end, including overnight schedules.
- Week, month, quarter, and year progress; Monday/Sunday week start and calendar/Japan fiscal quarter cycles.
- Elapsed or remaining mode, 0–3 decimal precision, remaining duration, and the duration represented by 1% of a period.
- Sunrise and sunset positioned within the waking day, using local coordinates.
- Birthday marker on the year bar; life progress using birth date, country, and editable population life expectancy.
- Selected visible periods and collapsible progress rows. The Mac menu bar source has no direct iOS equivalent.
- Current and upcoming timed calendar events, current-event progress, an eight-hour lead-in for the next event, description when available, and an open-event action.
- Check-in history: latest 500 entries, daily count, gap and long-gap threshold, hourly distribution, and history detail. Opening the Mac popover or TUI currently records a check.
- Local settings and operation with no Timescale account.

The duration counter and older routine features have been removed from the current Mac/TUI implementation and are excluded from iOS, widgets, Shortcuts, and Live Activities.

## Core journeys

1. **First run:** Open a useful dashboard showing day, week, month, quarter, and year immediately. Personal features are optional setup steps. Add a widget from clear gallery previews.
2. **Glance:** Place a Day ring and Year number together, or a multi-period overview. Each widget can show a different source; global display settings apply to all.
3. **Open detail:** Tap any widget to open the full dashboard and record one check-in.
4. **Calendar:** Grant calendar access, select enabled calendars, and see one combined current/next feed. A HEY calendar subscribed in Apple Calendar can participate.
5. **Review attention:** Open history, inspect gaps and patterns, and optionally enable one long-gap notification after the first check-in of a waking day.
6. **Automate:** Read current progress and the visible set, or record a deliberate check-in, through Shortcuts.

## App structure

The root view is one scrollable dashboard modeled on the Mac popover. A top summary shows the selected headline period and current time context; the body shows visible progress rows in the existing fixed order: day, week, month, quarter, year, life. Calendar and awareness sections follow when configured. Settings and history are secondary screens reachable from the dashboard. Avoid a persistent multi-tab shell for the first build.

Each row shows a clear period label, progress, elapsed/remaining meaning, boundary or time-left context, and 1% duration where useful. Users can show or hide periods, collapse individual rows, and choose the global accent, elapsed/remaining mode, and precision. The dashboard recalculates on foreground entry and time or time-zone changes.

The day bar supports overnight waking hours. Year includes the birthday marker after birth date setup. Life includes current age and the selected country/expectancy basis; label it as a population-average visualization, not a personal prediction. Sun positions require coordinates. Offer automatic location while travelling and manual coordinate entry as a user-selected mode. Only request location after choosing automatic mode; manual mode works offline. If location is denied, show a useful settings explanation and retain other progress.

## Widget system

Use WidgetKit with named templates and configuration within each template. A user can add many instances. A single-period instance chooses its own period. All instances share global color, numeric precision, and elapsed/remaining mode. An overview instance mirrors the app's visible periods. There is no separate per-widget period list and no named preset system at launch. Templates should have strong default configurations so the gallery is useful without editing.

| Template | Home Screen | Lock Screen | Content |
| --- | --- | --- | --- |
| Period bar | Small, medium | Rectangular | One chosen day, week, month, quarter, year, or life period; label, bar, and value where legible |
| Period ring | Small, medium | Circular, rectangular | One chosen period with ring and concise value |
| Period number | Small, medium | Inline, circular, rectangular | One chosen period with prominent percentage and meaning; show snapshot time when space permits |
| Overview | Medium, large | Rectangular summary | App-visible periods in fixed order, fit to family; state clearly when some are omitted for space |
| Day and sun | Small, medium | Rectangular | Waking-day progress with sunrise/sunset markers or next solar boundary |
| Year and birthday | Small, medium | Rectangular | Year progress and birthday marker or upcoming birthday context |
| Life | Small, medium | Rectangular | Life estimate with age/expectancy context after setup; setup prompt beforehand |
| Calendar | Small, medium, large | Inline, circular, rectangular | Current timed event or next event, title/time/progress as space allows |
| Time awareness | Small, medium | Inline, circular, rectangular | Last check-in, gap, or daily count; empty state before first check-in |

A template may use one WidgetKit implementation with per-instance parameters instead of a separate binary widget for each period. Gallery names and previews should make the style and information clear. Validate every claimed family on actual device and remove combinations that cannot remain legible. Lock Screen calendar titles and life data can be visible before unlock, per product choice.

Every widget's primary tap opens the full dashboard. Passive display does not record a check-in. Widgets do not expose Control Center or Action button controls. Numeric snapshots are approximate and show an update time in layouts that have room; very small layouts use a time-based visual or a short age indicator instead of implying live numeric precision. Use system time-based progress views and dynamic date text where they fit, and timeline entries around meaningful boundaries. Refresh when settings or calendar data changes, but do not promise exact minute-by-minute custom ring or number updates. Calendar widgets show unavailable/stale state if their source cannot refresh.

## Calendar source design, across Mac and iPhone

Use a source layer with normalized timed-event records and one current/next selection algorithm. On iPhone and Mac, EventKit reads user-selected Apple Calendar calendars. This includes HEY calendars that the user has subscribed to in Apple Calendar. Keep the current Mac HEY CLI source as an optional adapter. Combine enabled calendars in one feed and deduplicate overlapping EventKit and CLI copies with a stable combination of source identifier, external UID when available, start, end, and title. Preserve source attribution.

There is no documented supported HEY Calendar OAuth/API flow for third-party direct sign-in in the research so far. Do not build against private endpoints or ask for a HEY password. The supported HEY route is a read-only per-calendar ICS feed subscribed through Apple Calendar; Timescale then reads it with EventKit and need not store the feed URL. Explain that subscription refresh may lag. Revisit direct sign-in only if HEY publishes a supported API. Keep the Mac CLI adapter until EventKit plus subscriptions is proven equivalent for its users.

Request calendar permission in context. Let users enable or disable individual calendars and choose whether the Mac CLI adapter participates. An ongoing timed event with earliest end wins for current event; an upcoming timed event with earliest start wins for next event. Preserve the existing eight-hour lead-in within the waking day. Exclude all-day events from progress. Show event title, timing, progress, description if available, and source. Open an EventKit event in a supported Calendar view; use a HEY deep link only when the CLI provides one. Permission denial, missing subscription, or a failing source must not block other dashboard data.

## Time awareness and notifications

Record one check-in when the app becomes active from outside the app, including a widget or notification open. Do not create duplicate entries during normal in-app navigation or rapid lifecycle changes. Store at most 500 local checks. Preserve timestamp and known source; iOS has no frontmost-app attribution. A widget deep link may identify its source when reliable; otherwise use an app-open source. Historical checks referencing removed sources remain as historical entries, labeled unavailable.

History shows daily count, time since prior check, waking-day percentage since prior check, average gap, hourly activity, and a browsable list. Offer clear-history with confirmation. The long-gap threshold remains 5–480 minutes.

Reminders are off by default. Enabling them requests notification permission in context and allows an on/off setting. A reminder cycle starts only after the first check-in in a waking day. A later check-in resets its threshold timer. Deliver at most one reminder for a gap, and only inside the configured waking interval. If the threshold lands outside waking hours, skip that cycle; do not queue it for sleep hours. Recompute or cancel pending notifications when a check-in occurs, waking hours or threshold change, reminders are disabled, or the time zone changes. A notification opens the dashboard and its app-open check-in resolves the gap. Suggested copy: “It has been a while since your last Timescale check-in.” Do not put private calendar or life data in reminder copy.

## Shortcuts

Provide App Intents for **Get Progress** (chosen day/week/month/quarter/year/life period), **Get Visible Progress** (structured list in dashboard order), and **Check In**. Progress actions return period label, exact start/end timestamps, elapsed fraction, displayed fraction, remaining duration, 1% duration, and calculation timestamp. Calculate when invoked, independent of widget snapshots. Check In records one check without opening the app and returns the check timestamp; it resets the reminder cycle. If the user separately opens the app, the ordinary app-open rule applies, with normal lifecycle deduplication. Passive widget rendering never calls Check In.

No Control Center or Action button controls are in scope.

## Live Activity

At launch, the user can manually start a Live Activity for a chosen visible progress bar from the dashboard. It shows the period label, current progress, elapsed/remaining meaning, and a time-based visual on the Lock Screen and Dynamic Island. Only one Timescale Live Activity is active at a time; starting another replaces the previous one. The dashboard offers an explicit Stop Tracking action. Tapping the activity opens the full dashboard.

ActivityKit limits active duration to eight hours. A year, month, week, or full waking-day bar therefore cannot stay continuously live through its whole period. Explain this in the start flow: the Live Activity is a temporary tracking session for the selected bar, even if that bar spans a longer period. Start it while the app is foregrounded; let it end after eight hours or sooner if the user stops it or the period changes. A changed time zone or period settings should update or end it when the app next runs. Do not silently restart it to evade the limit. If Live Activities are disabled or unsupported on a device, the dashboard and widgets still work. No automatic calendar-event Live Activity is required.

## Data, architecture, and accessibility

Share one calculation contract between the iOS app, widgets, Shortcuts, and any Live Activity. Reuse the existing Swift core where portable; separate calendar and storage adapters from period math. Use an App Group container for iOS app/extension data. Store settings, check-in history, calendar selection, and cached event summaries locally. Do not request an account or create a backend. Do not sync with Mac in the first release. Specify a migration path if a later release adds sync.

Calendar titles, birth date, and coordinates are personal data. Keep them on device except for OS calendar access and any user-configured calendar subscription handled by Apple Calendar. Request only necessary permissions. The app must remain useful when Calendar, Location, Notifications, or Live Activities are denied. Support VoiceOver with period, mode, value, and boundaries; Dynamic Type; Reduce Motion; light/dark/tinted widget rendering; and readable grayscale Lock Screen layouts. Avoid using color as the only signal.

## Acceptance criteria

- A fresh install shows day, week, month, quarter, and year without permissions or an account; optional sections explain setup.
- A Day ring and Year number can appear together with independent sources and shared global styling. A multi-period widget mirrors the app's visible set.
- The dashboard, Shortcuts, and a widget timeline entry calculate the same value for the same timestamp, settings, and time zone. Numeric widgets disclose snapshot age.
- Overnight waking hours, daylight-saving transitions, local time-zone changes, calendar rollovers, Japan fiscal quarter boundaries, birthdays, and absent birth date are handled.
- Opening from a widget records exactly one check-in; merely seeing a widget records none. Reminders obey first-check-in, waking-hours, threshold, and once-per-gap rules.
- EventKit combines selected calendars, including an Apple Calendar HEY subscription. Mac can additionally use its CLI adapter without duplicate events. Permission denial and stale subscriptions have clear states.
- Global setting changes reach widgets at the next allowed refresh. Lock Screen and Home Screen layouts remain readable in their supported families and privacy/rendering modes.
- VoiceOver, large text, and high contrast convey progress meaning without relying on color.
- Existing Mac/TUI settings with removed timer fields load, preserve unrelated settings and history, and rewrite without timer fields.

## Delivery order and test evidence

1. Extract/shared period calculations and local storage contract; implement the scrollable iPhone dashboard and settings.
2. Add EventKit source layer to iPhone and Mac, including source selection, deduplication, and HEY subscription guidance.
3. Add the widget catalog, using device review for each offered family and visual style.
4. Add awareness history, local notifications, and the three Shortcuts actions.
5. Add manually started progress-bar Live Activity; validate its lifecycle and eight-hour limit.

The implementation agent should provide an iPhone simulator build, screenshots of the dashboard and representative Home/Lock Screen widgets, tests for period boundaries and notification scheduling, and a manual device checklist for permissions, widget freshness, calendar subscription behavior, and Live Activity behavior if included. TestFlight installation is the first distribution gate.

## Sources

- [WidgetKit](https://developer.apple.com/documentation/WidgetKit/), [widget strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy), and [widget freshness](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)
- [App Intents](https://developer.apple.com/documentation/appintents/app-intents)
- [EventKit calendar access](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui) and [subscribed calendar property](https://developer.apple.com/documentation/eventkit/ekcalendar/issubscribed)
- [ActivityKit constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) and [Live Activity design](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [HEY read-only calendar feeds](https://help.hey.com/article/829-share-a-hey-calendar) and [Apple Calendar subscription on iPhone](https://support.apple.com/en-lamr/guide/iphone/ipha0d932e96/26/ios/26)
