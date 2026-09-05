import Foundation

public struct SolarEvents: Equatable, Sendable {
  public let sunrise: Date
  public let sunset: Date

  public init(sunrise: Date, sunset: Date) {
    self.sunrise = sunrise
    self.sunset = sunset
  }
}

public enum SolarCalculator {
  public static func events(
    on date: Date,
    latitude: Double,
    longitude: Double,
    calendar: Calendar = .autoupdatingCurrent
  ) -> SolarEvents? {
    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let day = gregorian.ordinality(of: .day, in: .year, for: date) ?? 1
    guard
      let sunriseHour = universalHour(
        day: day, latitude: latitude, longitude: longitude, sunrise: true),
      let sunsetHour = universalHour(
        day: day, latitude: latitude, longitude: longitude, sunrise: false),
      let sunrise = dateForUniversalHour(
        sunriseHour, matchingLocalDateOf: date, calendar: gregorian),
      let sunset = dateForUniversalHour(sunsetHour, matchingLocalDateOf: date, calendar: gregorian)
    else { return nil }
    return SolarEvents(sunrise: sunrise, sunset: sunset)
  }

  private static func universalHour(day: Int, latitude: Double, longitude: Double, sunrise: Bool)
    -> Double?
  {
    let longitudeHour = longitude / 15
    let approximateTime = Double(day) + ((sunrise ? 6 : 18) - longitudeHour) / 24
    let meanAnomaly = 0.9856 * approximateTime - 3.289
    var trueLongitude =
      meanAnomaly + 1.916 * sin(degrees: meanAnomaly) + 0.020 * sin(degrees: 2 * meanAnomaly)
      + 282.634
    trueLongitude = normalized(trueLongitude, maximum: 360)

    var rightAscension = atan(degrees: 0.91764 * tan(degrees: trueLongitude))
    rightAscension += floor(trueLongitude / 90) * 90 - floor(rightAscension / 90) * 90
    rightAscension /= 15

    let sinDeclination = 0.39782 * sin(degrees: trueLongitude)
    let cosDeclination = Foundation.cos(Foundation.asin(sinDeclination))
    let zenith = 90.833
    let cosHour =
      (cos(degrees: zenith) - sinDeclination * sin(degrees: latitude))
      / (cosDeclination * cos(degrees: latitude))
    guard (-1...1).contains(cosHour) else { return nil }

    let hourAngle = (sunrise ? 360 - acos(degrees: cosHour) : acos(degrees: cosHour)) / 15
    let localMeanTime = hourAngle + rightAscension - 0.06571 * approximateTime - 6.622
    return normalized(localMeanTime - longitudeHour, maximum: 24)
  }

  private static func dateForUniversalHour(
    _ hour: Double, matchingLocalDateOf date: Date, calendar: Calendar
  ) -> Date? {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let base = utc.date(from: components) else { return nil }
    let candidate = base.addingTimeInterval(hour * 3600)
    let target = calendar.dateComponents([.year, .month, .day], from: date)

    return [-1, 0, 1]
      .compactMap { utc.date(byAdding: .day, value: $0, to: candidate) }
      .first { calendar.dateComponents([.year, .month, .day], from: $0) == target }
  }

  private static func normalized(_ value: Double, maximum: Double) -> Double {
    let result = value.truncatingRemainder(dividingBy: maximum)
    return result < 0 ? result + maximum : result
  }

  private static func sin(degrees: Double) -> Double { Foundation.sin(degrees * .pi / 180) }
  private static func cos(degrees: Double) -> Double { Foundation.cos(degrees * .pi / 180) }
  private static func tan(degrees: Double) -> Double { Foundation.tan(degrees * .pi / 180) }
  private static func atan(degrees value: Double) -> Double { Foundation.atan(value) * 180 / .pi }
  private static func acos(degrees value: Double) -> Double { Foundation.acos(value) * 180 / .pi }
}
