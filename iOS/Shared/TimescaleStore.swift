import Foundation
import TimescaleCore

enum IOSStore {
  static let appGroup = "group.com.davafons.timescale.ios"
  static let settingsKey = "ios.settings.v1"
  static let checksKey = "ios.checks.v1"
  static let eventsKey = "ios.events.v1"
  static let eventsUpdatedKey = "ios.events.updated.v1"
  static let calendarAccessDeniedKey = "ios.calendar.accessDenied.v1"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: appGroup)!
  }

  static func loadSettings() -> IOSSettings {
    guard let data = defaults.data(forKey: settingsKey),
      let settings = try? JSONDecoder().decode(IOSSettings.self, from: data)
    else { return IOSSettings() }
    return settings
  }

  static func saveSettings(_ settings: IOSSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: settingsKey)
  }

  static func loadChecks() -> [InteractionHistory.Check] {
    guard let data = defaults.data(forKey: checksKey),
      let checks = try? JSONDecoder().decode([InteractionHistory.Check].self, from: data)
    else { return [] }
    return Array(checks.sorted { $0.timestamp < $1.timestamp }
      .suffix(InteractionHistory.maximumCount))
  }

  static func saveChecks(_ checks: [InteractionHistory.Check]) {
    defaults.set(
      try? JSONEncoder().encode(Array(checks.suffix(InteractionHistory.maximumCount))),
      forKey: checksKey)
  }

  @discardableResult
  static func checkIn(source: String, at date: Date = .now) -> InteractionHistory.Check {
    let check = InteractionHistory.Check(timestamp: date.timeIntervalSince1970, source: source)
    var checks = loadChecks()
    checks.append(check)
    saveChecks(checks)
    return check
  }

  static func clearChecks() {
    defaults.removeObject(forKey: checksKey)
  }

  static func loadEvents() -> (events: [TimedEvent], updated: Date?) {
    let events = defaults.data(forKey: eventsKey)
      .flatMap { try? JSONDecoder().decode([TimedEvent].self, from: $0) } ?? []
    let updated = defaults.object(forKey: eventsUpdatedKey) as? Date
    return (events, updated)
  }

  static func saveEvents(_ events: [TimedEvent], at date: Date = .now) {
    defaults.set(try? JSONEncoder().encode(events), forKey: eventsKey)
    defaults.set(date, forKey: eventsUpdatedKey)
  }

  static func clearEvents() {
    defaults.removeObject(forKey: eventsKey)
    defaults.removeObject(forKey: eventsUpdatedKey)
  }

  static var calendarAccessDenied: Bool {
    defaults.bool(forKey: calendarAccessDeniedKey)
  }

  static func setCalendarAccessDenied(_ denied: Bool) {
    defaults.set(denied, forKey: calendarAccessDeniedKey)
  }
}

struct IOSSettings: Codable, Equatable {
  var visible: [SharedPeriod] = [.day, .week, .month, .quarter, .year]
  var collapsed: Set<SharedPeriod> = []
  var headline: SharedPeriod = .day
  var dayStartMinutes = 8 * 60
  var dayEndMinutes = 23 * 60
  var weekStartsOn: SharedWeekStart = .monday
  var quarterCycle: SharedQuarterCycle = .calendar
  var showRemaining = false
  var precision = 1
  var accent = "orange"
  var birthDate: CivilDate?
  var country = "Japan"
  var expectedYears = 84.0
  var latitude: Double?
  var longitude: Double?
  var locationMode = "manual"
  var longGapMinutes = 90
  var remindersEnabled = false
  var selectedCalendarIDs: [String]?

  private enum CodingKeys: String, CodingKey {
    case visible, collapsed, headline, dayStartMinutes, dayEndMinutes
    case weekStartsOn, quarterCycle, showRemaining, precision, accent
    case birthDate, country, expectedYears, latitude, longitude, locationMode
    case longGapMinutes, remindersEnabled, selectedCalendarIDs
  }

  init() {}

  init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    visible = try values.decodeIfPresent([SharedPeriod].self, forKey: .visible) ?? visible
    visible = SharedPeriod.allCases.filter { visible.contains($0) }
    collapsed = try values.decodeIfPresent(Set<SharedPeriod>.self, forKey: .collapsed) ?? collapsed
    headline = try values.decodeIfPresent(SharedPeriod.self, forKey: .headline) ?? headline
    dayStartMinutes = min(max(
      try values.decodeIfPresent(Int.self, forKey: .dayStartMinutes) ?? dayStartMinutes, 0), 1439)
    dayEndMinutes = min(max(
      try values.decodeIfPresent(Int.self, forKey: .dayEndMinutes) ?? dayEndMinutes, 0), 1439)
    weekStartsOn = try values.decodeIfPresent(SharedWeekStart.self, forKey: .weekStartsOn)
      ?? weekStartsOn
    quarterCycle = try values.decodeIfPresent(SharedQuarterCycle.self, forKey: .quarterCycle)
      ?? quarterCycle
    showRemaining = try values.decodeIfPresent(Bool.self, forKey: .showRemaining)
      ?? showRemaining
    precision = min(max(
      try values.decodeIfPresent(Int.self, forKey: .precision) ?? precision, 0), 3)
    accent = try values.decodeIfPresent(String.self, forKey: .accent) ?? accent
    if let civilDate = try? values.decode(CivilDate.self, forKey: .birthDate) {
      birthDate = civilDate
    } else if let legacyDate = try? values.decode(Date.self, forKey: .birthDate) {
      birthDate = CivilDate(date: legacyDate)
    }
    country = try values.decodeIfPresent(String.self, forKey: .country) ?? country
    expectedYears = min(max(
      try values.decodeIfPresent(Double.self, forKey: .expectedYears) ?? expectedYears, 1), 150)
    latitude = try values.decodeIfPresent(Double.self, forKey: .latitude)
    longitude = try values.decodeIfPresent(Double.self, forKey: .longitude)
    if !(latitude.map { (-90...90).contains($0) } ?? false)
      || !(longitude.map { (-180...180).contains($0) } ?? false)
    {
      latitude = nil
      longitude = nil
    }
    locationMode = try values.decodeIfPresent(String.self, forKey: .locationMode)
      ?? locationMode
    if locationMode != "automatic" { locationMode = "manual" }
    longGapMinutes = min(max(
      try values.decodeIfPresent(Int.self, forKey: .longGapMinutes) ?? longGapMinutes, 5), 480)
    remindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .remindersEnabled)
      ?? remindersEnabled
    selectedCalendarIDs = try values.decodeIfPresent(
      [String].self, forKey: .selectedCalendarIDs)
  }

  func snapshot(for period: SharedPeriod, at date: Date = .now) -> PeriodSnapshot? {
    PeriodSnapshotCalculator.snapshot(
      for: period, at: date,
      dayStartMinutes: dayStartMinutes, dayEndMinutes: dayEndMinutes,
      weekStartsOn: weekStartsOn, quarterCycle: quarterCycle,
      birthDate: birthDate?.date(), expectedYears: expectedYears,
      remaining: showRemaining)
  }
}

extension SharedPeriod {
  var title: String { rawValue.capitalized }
}
