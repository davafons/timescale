import Foundation

public struct PeriodSnapshot: Equatable, Sendable {
  public let period: SharedPeriod
  public let calculatedAt: Date
  public let start: Date
  public let end: Date
  public let elapsedFraction: Double
  public let displayedFraction: Double
  public let remainingDuration: TimeInterval
  public let onePercentDuration: TimeInterval

  public init(period: SharedPeriod, calculatedAt: Date, progress: TimeProgress, remaining: Bool) {
    self.period = period
    self.calculatedAt = calculatedAt
    self.start = progress.start
    self.end = progress.end
    self.elapsedFraction = progress.elapsed
    self.displayedFraction = remaining ? 1 - progress.elapsed : progress.elapsed
    self.remainingDuration = max(0, progress.end.timeIntervalSince(calculatedAt))
    self.onePercentDuration = max(0, progress.end.timeIntervalSince(progress.start) / 100)
  }
}

public enum PeriodSnapshotCalculator {
  public static func snapshot(
    for period: SharedPeriod,
    at date: Date,
    dayStartMinutes: Int = 8 * 60,
    dayEndMinutes: Int = 23 * 60,
    weekStartsOn: SharedWeekStart = .monday,
    quarterCycle: SharedQuarterCycle = .calendar,
    birthDate: Date? = nil,
    expectedYears: Double = 84,
    remaining: Bool = false,
    calendar: Calendar = .autoupdatingCurrent
  ) -> PeriodSnapshot? {
    var localCalendar = calendar
    localCalendar.firstWeekday = weekStartsOn == .monday ? 2 : 1
    localCalendar.minimumDaysInFirstWeek = weekStartsOn == .monday ? 4 : 1
    let progress: TimeProgress
    switch period {
    case .day:
      progress = ProgressCalculator.activeDay(
        at: date, startMinutes: dayStartMinutes, endMinutes: dayEndMinutes,
        calendar: localCalendar)
    case .week:
      progress = ProgressCalculator.week(at: date, calendar: localCalendar)
    case .month:
      progress = ProgressCalculator.month(at: date, calendar: localCalendar)
    case .quarter:
      progress = ProgressCalculator.quarter(
        at: date, startMonth: quarterCycle == .japanFiscal ? 4 : 1,
        calendar: localCalendar)
    case .year:
      progress = ProgressCalculator.year(at: date, calendar: localCalendar)
    case .life:
      guard let birthDate,
        let value = ProgressCalculator.life(
          at: date, birthDate: birthDate, expectedYears: expectedYears,
          calendar: localCalendar)
      else { return nil }
      progress = value
    }
    return PeriodSnapshot(
      period: period, calculatedAt: date, progress: progress, remaining: remaining)
  }
}
