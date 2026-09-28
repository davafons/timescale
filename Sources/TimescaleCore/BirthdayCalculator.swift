import Foundation

public enum BirthdayCalculator {
  public static func birthday(
    inYearOf date: Date, birthDate: Date,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let birthday = calendar.dateComponents([.month, .day], from: birthDate)
    guard let month = birthday.month, let requestedDay = birthday.day,
      let monthStart = calendar.date(from: DateComponents(
        year: calendar.component(.year, from: date), month: month,
        day: 1, hour: 12)),
      let days = calendar.range(of: .day, in: .month, for: monthStart)
    else { return nil }
    return calendar.date(byAdding: .day, value: min(requestedDay, days.count) - 1,
      to: monthStart)
  }

  public static func nextBirthday(
    after date: Date, birthDate: Date,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let thisYear = birthday(inYearOf: date, birthDate: birthDate,
      timeZone: timeZone)
    else { return nil }
    if calendar.startOfDay(for: thisYear) >= calendar.startOfDay(for: date) {
      return thisYear
    }
    guard let nextYear = calendar.date(byAdding: .year, value: 1, to: date) else {
      return nil
    }
    return birthday(inYearOf: nextYear, birthDate: birthDate, timeZone: timeZone)
  }
}
