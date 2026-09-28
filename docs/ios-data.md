# iOS local data and future sync

Timescale for iPhone stores settings, selected calendar IDs, cached event summaries, and the latest 500 check-ins in the app group `group.com.davafons.timescale.ios`. The app and widget extension share these versioned `UserDefaults` keys through `IOSStore`; the Mac and TUI configuration stays independent. Calendar subscriptions remain in Apple Calendar. Timescale stores event summaries for widgets, not subscription URLs or credentials.

If a later release adds cross-device sync, migrate only after the person opts in:

1. Decode the existing `ios.settings.v1`, `ios.checks.v1`, and calendar selection locally. Keep the v1 keys until the new store is written and verified so a failed migration can retry.
2. Give each historical check a durable identifier derived from a new device ID and its local sequence number. Preserve its timestamp and source; do not merge checks merely because their timestamps match.
3. Resolve settings conflicts explicitly. Keep this device's current choices by default, show remote choices before replacing them, and maintain the fixed dashboard period order. Keep calendar identifiers, cached event summaries, coordinates, and location mode local unless a later product decision explicitly expands sync.
4. Merge check histories by durable ID, sort them by timestamp, and keep the latest 500. Recalculate reminders from the merged latest check only after the migration commits.
5. Continue to support the v1 decoder for older local data and provide a clear rollback path before removing it in a later version.

The current release performs no cross-device sync and requires no account.
