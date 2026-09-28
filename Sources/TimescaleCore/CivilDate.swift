import Foundation

/// A Gregorian calendar date without a time or time zone.
public struct CivilDate: Codable, Equatable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  private enum CodingKeys: String, CodingKey { case year, month, day }

  public init?(year: Int, month: Int, day: Int) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: DateComponents(
      year: year, month: month, day: day, hour: 12)),
      calendar.dateComponents([.year, .month, .day], from: date)
        == DateComponents(year: year, month: month, day: day)
    else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  public init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    self.year = components.year!
    self.month = components.month!
    self.day = components.day!
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let year = try values.decode(Int.self, forKey: .year)
    let month = try values.decode(Int.self, forKey: .month)
    let day = try values.decode(Int.self, forKey: .day)
    guard let valid = Self(year: year, month: month, day: day) else {
      throw DecodingError.dataCorruptedError(
        forKey: .day, in: values, debugDescription: "Invalid Gregorian date")
    }
    self = valid
  }

  public func date(timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let noon = calendar.date(from: DateComponents(
      year: year, month: month, day: day, hour: 12))
    else { return nil }
    return calendar.startOfDay(for: noon)
  }

  public func pickerDate(timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(
      year: year, month: month, day: day, hour: 12))
  }
}
