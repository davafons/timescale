import Foundation
import Testing
@testable import TimescaleCore

struct IOSContractTests {
  private var tokyo: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }

  private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
    calendar: Calendar
  ) -> Date {
    calendar.date(from: DateComponents(
      year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  @Test func overnightAndFiscalQuarter() {
    let now = date(2026, 4, 1, 1, calendar: tokyo)
    let day = PeriodSnapshotCalculator.snapshot(
      for: .day, at: now, dayStartMinutes: 22 * 60, dayEndMinutes: 6 * 60,
      calendar: tokyo)!
    #expect(tokyo.component(.day, from: day.start) == 31)
    #expect(tokyo.component(.month, from: day.start) == 3)
    #expect(day.elapsedFraction > 0 && day.elapsedFraction < 1)

    let quarter = PeriodSnapshotCalculator.snapshot(
      for: .quarter, at: now, quarterCycle: .japanFiscal, calendar: tokyo)!
    #expect(tokyo.component(.month, from: quarter.start) == 4)
    #expect(tokyo.component(.month, from: quarter.end) == 7)
  }

  @Test func weekStartRemainsStableAcrossNewYear() {
    let now = date(2027, 1, 1, 12, calendar: tokyo)
    let monday = PeriodSnapshotCalculator.snapshot(
      for: .week, at: now, weekStartsOn: .monday, calendar: tokyo)!
    let sunday = PeriodSnapshotCalculator.snapshot(
      for: .week, at: now, weekStartsOn: .sunday, calendar: tokyo)!
    #expect(monday.start == date(2026, 12, 28, 0, calendar: tokyo))
    #expect(sunday.start == date(2026, 12, 27, 0, calendar: tokyo))
  }

  @Test func daylightSavingDayUsesRealDuration() {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    let now = date(2026, 3, 8, 4, calendar: newYork)
    let snapshot = PeriodSnapshotCalculator.snapshot(
      for: .day, at: now, dayStartMinutes: 0, dayEndMinutes: 8 * 60,
      calendar: newYork)!
    #expect(snapshot.end.timeIntervalSince(snapshot.start) == 7 * 3600)
    #expect(snapshot.elapsedFraction > 0.4 && snapshot.elapsedFraction < 0.5)
  }

  @Test func lifeRequiresBirthDate() {
    #expect(PeriodSnapshotCalculator.snapshot(for: .life, at: .now) == nil)
  }

  @Test func leapDayBirthdayUsesLastDayOfFebruary() {
    let birthDate = date(2000, 2, 29, 12, calendar: tokyo)
    let zone = tokyo.timeZone
    let leapYear = date(2024, 1, 1, 12, calendar: tokyo)
    let ordinaryYear = date(2025, 1, 1, 12, calendar: tokyo)
    #expect(BirthdayCalculator.birthday(
      inYearOf: leapYear, birthDate: birthDate, timeZone: zone)
      == date(2024, 2, 29, 12, calendar: tokyo))
    #expect(BirthdayCalculator.birthday(
      inYearOf: ordinaryYear, birthDate: birthDate, timeZone: zone)
      == date(2025, 2, 28, 12, calendar: tokyo))
    #expect(BirthdayCalculator.nextBirthday(
      after: date(2025, 3, 1, 12, calendar: tokyo),
      birthDate: birthDate, timeZone: zone)
      == date(2026, 2, 28, 12, calendar: tokyo))
  }

  @Test func birthCalendarDateStaysTheSameAcrossTimeZones() throws {
    let dateOnly = CivilDate(year: 2000, month: 2, day: 29)!
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    let tokyoDate = dateOnly.date(timeZone: tokyo.timeZone)!
    let losAngelesDate = dateOnly.date(timeZone: losAngeles)!
    #expect(tokyoDate != losAngelesDate)
    #expect(CivilDate(date: tokyoDate, timeZone: tokyo.timeZone) == dateOnly)
    #expect(CivilDate(date: losAngelesDate, timeZone: losAngeles) == dateOnly)
    let encoded = try JSONEncoder().encode(dateOnly)
    #expect(try JSONDecoder().decode(CivilDate.self, from: encoded) == dateOnly)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(CivilDate.self,
        from: Data(#"{"year":2001,"month":2,"day":29}"#.utf8))
    }
  }

  @Test func reminderStartsAfterCheckAndStaysAwake() {
    let now = date(2026, 9, 28, 10, calendar: tokyo)
    #expect(ReminderPlanner.nextReminder(
      after: [], now: now, thresholdMinutes: 90,
      dayStartMinutes: 8 * 60, dayEndMinutes: 23 * 60,
      calendar: tokyo) == nil)
    let check = InteractionHistory.Check(
      timestamp: date(2026, 9, 28, 9, 30, calendar: tokyo).timeIntervalSince1970,
      source: "app")
    let trigger = ReminderPlanner.nextReminder(
      after: [check], now: now, thresholdMinutes: 90,
      dayStartMinutes: 8 * 60, dayEndMinutes: 23 * 60,
      calendar: tokyo)
    #expect(trigger == date(2026, 9, 28, 11, calendar: tokyo))

    let lateCheck = InteractionHistory.Check(
      timestamp: date(2026, 9, 28, 22, calendar: tokyo).timeIntervalSince1970,
      source: "app")
    #expect(ReminderPlanner.nextReminder(
      after: [lateCheck], now: date(2026, 9, 28, 22, 10, calendar: tokyo),
      thresholdMinutes: 90, dayStartMinutes: 8 * 60, dayEndMinutes: 23 * 60,
      calendar: tokyo) == nil)
  }

  @Test func reminderOncePerOvernightGap() {
    let check = InteractionHistory.Check(
      timestamp: date(2026, 9, 28, 23, 30, calendar: tokyo).timeIntervalSince1970,
      source: "app")
    let waiting = date(2026, 9, 29, 0, 45, calendar: tokyo)
    #expect(ReminderPlanner.nextReminder(
      after: [check], now: waiting, thresholdMinutes: 90,
      dayStartMinutes: 22 * 60, dayEndMinutes: 6 * 60,
      calendar: tokyo) == date(2026, 9, 29, 1, calendar: tokyo))
    #expect(ReminderPlanner.nextReminder(
      after: [check], now: date(2026, 9, 29, 1, 1, calendar: tokyo),
      thresholdMinutes: 90, dayStartMinutes: 22 * 60,
      dayEndMinutes: 6 * 60, calendar: tokyo) == nil)
    let late = InteractionHistory.Check(
      timestamp: date(2026, 9, 29, 5, 30, calendar: tokyo).timeIntervalSince1970,
      source: "app")
    #expect(ReminderPlanner.nextReminder(
      after: [late], now: date(2026, 9, 29, 5, 40, calendar: tokyo),
      thresholdMinutes: 90, dayStartMinutes: 22 * 60,
      dayEndMinutes: 6 * 60, calendar: tokyo) == nil)
  }

  @Test func eventSelectionDeduplicatesSources() {
    let now = date(2026, 9, 28, 10, calendar: tokyo)
    let event = TimedEvent(
      id: "apple-1", source: "Apple Calendar",
      sourceIdentifier: "eventkit:work", externalUID: "shared-uid",
      title: "Review", start: now.addingTimeInterval(-60),
      end: now.addingTimeInterval(600))
    let copy = TimedEvent(
      id: "hey-1", source: "HEY", sourceIdentifier: "hey-cli",
      externalUID: "shared-uid",
      title: "Review", start: event.start, end: event.end)
    #expect(TimedEvents.deduplicated([event, copy]).count == 1)
    let noUIDCopy = TimedEvent(
      id: "hey-2", source: "HEY", sourceIdentifier: "hey-cli",
      title: "Review",
      start: event.start, end: event.end)
    #expect(TimedEvents.deduplicated([event, noUIDCopy]).count == 1)
    let separateEvent = TimedEvent(
      id: "other", source: "Other", sourceIdentifier: "eventkit:other",
      externalUID: "different",
      title: "Review", start: event.start, end: event.end)
    #expect(TimedEvents.deduplicated([event, separateEvent]).count == 2)
    let anotherCalendar = TimedEvent(
      id: "apple-2", source: "Personal",
      sourceIdentifier: "eventkit:personal", title: "Review",
      start: event.start, end: event.end)
    #expect(TimedEvents.deduplicated([event, anotherCalendar]).count == 2)
    #expect(TimedEvents.select([event, copy], at: now).current?.title == "Review")
  }

  @Test func cachedEventWithoutSourceIdentifierStillDecodes() throws {
    let data = Data(#"{"id":"legacy","source":"Work","title":"Review","start":0,"end":3600}"#.utf8)
    let event = try JSONDecoder().decode(TimedEvent.self, from: data)
    #expect(event.sourceIdentifier == nil)
    #expect(event.title == "Review")
  }

  @Test func eventLeadInRespectsWakingDayAndEightHours() {
    let now = date(2026, 9, 28, 10, calendar: tokyo)
    let day = ProgressCalculator.activeDay(
      at: now, startMinutes: 8 * 60, endMinutes: 23 * 60,
      calendar: tokyo)
    let eventStart = date(2026, 9, 28, 12, calendar: tokyo)
    let leadIn = TimedEvents.leadIn(to: eventStart, at: now, wakingDay: day)
    #expect(leadIn?.start == day.start)
    #expect(leadIn?.end == eventStart)
    #expect(leadIn?.elapsed == 0.5)
    #expect(TimedEvents.leadIn(
      to: date(2026, 9, 28, 19, calendar: tokyo),
      at: now, wakingDay: day) == nil)
    #expect(TimedEvents.leadIn(
      to: date(2026, 9, 29, 1, calendar: tokyo),
      at: now, wakingDay: day) == nil)
  }
}
