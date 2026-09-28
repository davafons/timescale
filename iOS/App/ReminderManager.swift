import Foundation
import TimescaleCore
import UserNotifications

@MainActor
enum ReminderManager {
  private static let identifier = "timescale.long-gap"

  static func setEnabled(_ enabled: Bool, settings: IOSSettings, checks: [InteractionHistory.Check]) async -> Bool {
    if !enabled {
      UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [identifier])
      return false
    }
    let granted = (try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    if granted { await reschedule(settings: settings, checks: checks) }
    return granted
  }

  static func reschedule(settings: IOSSettings, checks: [InteractionHistory.Check], now: Date = .now) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard settings.remindersEnabled,
      let triggerAt = ReminderPlanner.nextReminder(
        after: checks, now: now,
        thresholdMinutes: settings.longGapMinutes,
        dayStartMinutes: settings.dayStartMinutes,
        dayEndMinutes: settings.dayEndMinutes)
    else { return }
    let content = UNMutableNotificationContent()
    content.title = "Timescale"
    content.body = "It has been a while since your last Timescale check-in."
    let interval = max(1, triggerAt.timeIntervalSince(now))
    let request = UNNotificationRequest(
      identifier: identifier, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    try? await center.add(request)
  }
}
