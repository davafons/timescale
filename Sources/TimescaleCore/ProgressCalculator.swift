import Foundation

public struct TimeProgress: Equatable, Sendable {
  public let elapsed: Double
  public let start: Date
  public let end: Date

  public init(elapsed: Double, start: Date, end: Date) {
    self.elapsed = elapsed
    self.start = start
    self.end = end
  }
}

public enum ProgressCalculator {
  public static func day(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> TimeProgress {
    progress(for: .day, at: date, calendar: calendar)
  }

  public static func activeDay(
    at date: Date,
    startMinutes: Int,
    endMinutes: Int,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimeProgress {
    let startMinutes = min(max(startMinutes, 0), 1439)
    let endMinutes = min(max(endMinutes, 0), 1439)
    let minuteOfDay =
      calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

    if startMinutes < endMinutes {
      let start = wallTime(on: date, minutes: startMinutes, calendar: calendar)
      let end = wallTime(on: date, minutes: endMinutes, calendar: calendar)
      return TimeProgress(
        elapsed: fraction(now: date, start: start, end: end), start: start, end: end)
    }

    if minuteOfDay >= startMinutes {
      let start = wallTime(on: date, minutes: startMinutes, calendar: calendar)
      let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
      let end = wallTime(on: nextDay, minutes: endMinutes, calendar: calendar)
      return TimeProgress(
        elapsed: fraction(now: date, start: start, end: end), start: start, end: end)
    }

    let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
    let start = wallTime(on: previousDay, minutes: startMinutes, calendar: calendar)
    let end = wallTime(on: date, minutes: endMinutes, calendar: calendar)
    let elapsed = minuteOfDay < endMinutes ? fraction(now: date, start: start, end: end) : 1
    return TimeProgress(elapsed: elapsed, start: start, end: end)
  }

  public static func week(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> TimeProgress
  {
    progress(for: .weekOfYear, at: date, calendar: calendar)
  }

  public static func month(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> TimeProgress
  {
    progress(for: .month, at: date, calendar: calendar)
  }

  public static func quarter(
    at date: Date,
    startMonth: Int = 1,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimeProgress {
    let month = calendar.component(.month, from: date)
    let normalizedStartMonth = min(max(startMonth, 1), 12)
    let monthOffset = (month - normalizedStartMonth + 12) % 12
    let monthsIntoQuarter = monthOffset % 3
    let monthStart = calendar.dateInterval(of: .month, for: date)?.start

    guard let monthStart,
      let start = calendar.date(byAdding: .month, value: -monthsIntoQuarter, to: monthStart),
      let end = calendar.date(byAdding: .month, value: 3, to: start)
    else {
      return TimeProgress(elapsed: 0, start: date, end: date)
    }
    return TimeProgress(
      elapsed: fraction(now: date, start: start, end: end),
      start: start,
      end: end
    )
  }

  public static func quarterNumber(
    at date: Date,
    startMonth: Int = 1,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Int {
    let month = calendar.component(.month, from: date)
    let normalizedStartMonth = min(max(startMonth, 1), 12)
    return ((month - normalizedStartMonth + 12) % 12) / 3 + 1
  }

  public static func year(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> TimeProgress
  {
    progress(for: .year, at: date, calendar: calendar)
  }

  public static func life(
    at date: Date,
    birthDate: Date,
    expectedYears: Double,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimeProgress? {
    guard expectedYears > 0 else { return nil }

    let wholeYears = Int(expectedYears.rounded(.down))
    let partialYears = expectedYears - Double(wholeYears)
    guard let wholeYearEnd = calendar.date(byAdding: .year, value: wholeYears, to: birthDate),
      let end = calendar.date(
        byAdding: .day, value: Int((partialYears * 365.2425).rounded()), to: wholeYearEnd)
    else { return nil }

    return TimeProgress(
      elapsed: fraction(now: date, start: birthDate, end: end),
      start: birthDate,
      end: end
    )
  }

  private static func progress(
    for component: Calendar.Component,
    at date: Date,
    calendar: Calendar
  ) -> TimeProgress {
    guard let interval = calendar.dateInterval(of: component, for: date) else {
      return TimeProgress(elapsed: 0, start: date, end: date)
    }
    return TimeProgress(
      elapsed: fraction(now: date, start: interval.start, end: interval.end),
      start: interval.start,
      end: interval.end
    )
  }

  private static func fraction(now: Date, start: Date, end: Date) -> Double {
    let duration = end.timeIntervalSince(start)
    guard duration > 0 else { return 0 }
    return min(max(now.timeIntervalSince(start) / duration, 0), 1)
  }

  private static func wallTime(on day: Date, minutes: Int, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.hour = minutes / 60
    components.minute = minutes % 60
    components.second = 0

    if let exact = calendar.date(from: components) {
      return exact
    }

    return calendar.nextDate(
      after: calendar.startOfDay(for: day),
      matching: components,
      matchingPolicy: .nextTime,
      repeatedTimePolicy: .first,
      direction: .forward
    ) ?? calendar.startOfDay(for: day)
  }
}
