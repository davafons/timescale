import Foundation

public enum ReminderPlanner {
  public static func nextReminder(
    after checks: [InteractionHistory.Check],
    now: Date,
    thresholdMinutes: Int,
    dayStartMinutes: Int,
    dayEndMinutes: Int,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    guard (5...480).contains(thresholdMinutes) else { return nil }
    let day = ProgressCalculator.activeDay(
      at: now, startMinutes: dayStartMinutes, endMinutes: dayEndMinutes,
      calendar: calendar)
    guard now >= day.start, now < day.end,
      let last = checks.last,
      last.timestamp >= day.start.timeIntervalSince1970,
      last.timestamp <= now.timeIntervalSince1970
    else { return nil }
    let trigger = Date(timeIntervalSince1970: last.timestamp)
      .addingTimeInterval(TimeInterval(thresholdMinutes * 60))
    guard trigger > now, trigger < day.end else { return nil }
    return trigger
  }
}
