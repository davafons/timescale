import Foundation
import Testing

@testable import TimescaleCore

@Suite("Progress calculations")
struct ProgressCalculatorTests {
  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }

  @Test("Midday is half of a day")
  func midday() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z"))
    let result = ProgressCalculator.day(at: date, calendar: utcCalendar)
    #expect(abs(result.elapsed - 0.5) < 0.0001)
  }

  @Test("Progress is clamped")
  func lifeProgressIsClamped() throws {
    let birth = try #require(ISO8601DateFormatter().date(from: "1900-01-01T00:00:00Z"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
    let result = try #require(
      ProgressCalculator.life(at: now, birthDate: birth, expectedYears: 80, calendar: utcCalendar))
    #expect(result.elapsed == 1)
  }

  @Test("A waking day uses configured start and end times")
  func activeDay() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T15:30:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 8 * 60, endMinutes: 23 * 60, calendar: utcCalendar)
    #expect(abs(result.elapsed - 0.5) < 0.0001)
  }

  @Test("An overnight waking day stays complete between sleep and wake")
  func overnightActiveDay() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T05:00:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 10 * 60, endMinutes: 2 * 60, calendar: utcCalendar)
    #expect(result.elapsed == 1)
    #expect(result.start == ISO8601DateFormatter().date(from: "2026-09-04T10:00:00Z"))
    #expect(result.end == ISO8601DateFormatter().date(from: "2026-09-05T02:00:00Z"))
  }

  @Test("Waking-day wall times do not shift on spring DST transition")
  func springDSTWallTimes() throws {
    var calendar = utcCalendar
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let date = try #require(ISO8601DateFormatter().date(from: "2026-03-08T16:00:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 8 * 60, endMinutes: 23 * 60, calendar: calendar)
    #expect(calendar.component(.hour, from: result.start) == 8)
    #expect(calendar.component(.hour, from: result.end) == 23)
  }

  @Test("Waking-day wall times do not shift on fall DST transition")
  func fallDSTWallTimes() throws {
    var calendar = utcCalendar
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let date = try #require(ISO8601DateFormatter().date(from: "2026-11-01T17:00:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 8 * 60, endMinutes: 23 * 60, calendar: calendar)
    #expect(calendar.component(.hour, from: result.start) == 8)
    #expect(calendar.component(.hour, from: result.end) == 23)
  }

  @Test("An overnight waking day remains active after midnight")
  func overnightAfterMidnight() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T01:00:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 22 * 60, endMinutes: 8 * 60, calendar: utcCalendar)
    #expect(abs(result.elapsed - 0.3) < 0.0001)
    #expect(result.start == ISO8601DateFormatter().date(from: "2026-09-04T22:00:00Z"))
    #expect(result.end == ISO8601DateFormatter().date(from: "2026-09-05T08:00:00Z"))
  }

  @Test("Equal waking times represent a full day")
  func equalWakingTimes() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z"))
    let result = ProgressCalculator.activeDay(
      at: date, startMinutes: 8 * 60, endMinutes: 8 * 60, calendar: utcCalendar)
    #expect(result.end.timeIntervalSince(result.start) == 24 * 60 * 60)
    #expect(abs(result.elapsed - (4.0 / 24.0)) < 0.0001)
  }

  @Test("Solar math is independent of the display calendar")
  func solarUsesGregorianCalendar() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T03:00:00Z"))
    let gregorian = try #require(
      SolarCalculator.events(
        on: date, latitude: 35.6762, longitude: 139.6503, calendar: utcCalendar))
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = utcCalendar.timeZone
    let alternate = try #require(
      SolarCalculator.events(on: date, latitude: 35.6762, longitude: 139.6503, calendar: buddhist))
    #expect(abs(gregorian.sunrise.timeIntervalSince(alternate.sunrise)) < 1)
    #expect(abs(gregorian.sunset.timeIntervalSince(alternate.sunset)) < 1)
  }

  @Test("Quarter progress uses calendar-quarter boundaries")
  func quarterBoundaries() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-08-16T00:00:00Z"))
    let result = ProgressCalculator.quarter(at: date, calendar: utcCalendar)
    #expect(result.start == ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    #expect(result.end == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
    #expect(abs(result.elapsed - 0.5) < 0.0001)
    #expect(ProgressCalculator.quarterNumber(at: date, startMonth: 1, calendar: utcCalendar) == 3)
    #expect(ProgressCalculator.quarterNumber(at: date, startMonth: 4, calendar: utcCalendar) == 2)
  }

  @Test("Solar events fall on the requested local date")
  func solarEvents() throws {
    var tokyoCalendar = utcCalendar
    tokyoCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T03:00:00Z"))
    let events = try #require(
      SolarCalculator.events(
        on: date, latitude: 35.6762, longitude: 139.6503, calendar: tokyoCalendar))
    let sunriseHour = tokyoCalendar.component(.hour, from: events.sunrise)
    let sunsetHour = tokyoCalendar.component(.hour, from: events.sunset)
    #expect((4...6).contains(sunriseHour))
    #expect((17...19).contains(sunsetHour))
  }
}
